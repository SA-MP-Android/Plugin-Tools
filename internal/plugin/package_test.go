package plugin

import (
	"archive/zip"
	"bytes"
	"os"
	"path/filepath"
	"runtime"
	"testing"
)

func TestExamplesValidateAndPackDeterministically(t *testing.T) {
	root := repositoryRoot(t)
	examples := []string{
		"api-showcase",
		"crosshair-guide",
		"fps-counter",
		"session-timer",
	}
	expectedVersions := map[string]string{
		"api-showcase":    "1.0.0",
		"crosshair-guide": "1.0.0",
		"fps-counter":     "1.1.0",
		"session-timer":   "1.0.0",
	}
	for _, name := range examples {
		t.Run(name, func(t *testing.T) {
			source := filepath.Join(root, "examples", name)
			info, err := Validate(source)
			if err != nil {
				t.Fatalf("validate source: %v", err)
			}
			if info.Manifest.Version != expectedVersions[name] {
				t.Fatalf("unexpected version %q", info.Manifest.Version)
			}

			first := filepath.Join(t.TempDir(), "first.splug")
			second := filepath.Join(t.TempDir(), "second.splug")
			firstResult, err := Pack(source, first)
			if err != nil {
				t.Fatalf("first pack: %v", err)
			}
			secondResult, err := Pack(source, second)
			if err != nil {
				t.Fatalf("second pack: %v", err)
			}
			if firstResult.SHA256 != secondResult.SHA256 {
				t.Fatalf("packages are not reproducible: %s != %s", firstResult.SHA256, secondResult.SHA256)
			}
			if _, err := Validate(first); err != nil {
				t.Fatalf("validate package: %v", err)
			}
		})
	}
}

func TestArchiveRejectsUnsafePath(t *testing.T) {
	path := filepath.Join(t.TempDir(), "unsafe.splug")
	file, err := os.Create(path)
	if err != nil {
		t.Fatal(err)
	}
	archive := zip.NewWriter(file)
	writer, err := archive.Create("../main.lua")
	if err != nil {
		t.Fatal(err)
	}
	if _, err := writer.Write([]byte("return true")); err != nil {
		t.Fatal(err)
	}
	if err := archive.Close(); err != nil {
		t.Fatal(err)
	}
	if err := file.Close(); err != nil {
		t.Fatal(err)
	}
	if _, err := Validate(path); err == nil {
		t.Fatal("unsafe archive unexpectedly passed validation")
	}
}

func TestManifestRejectsUnsupportedPermission(t *testing.T) {
	data := []byte(`{
		"schemaVersion": 1,
		"id": "top.example.invalid",
		"name": "Invalid",
		"version": "1.0.0",
		"apiVersion": "^1.0",
		"entry": "main.lua",
		"permissions": ["native.memory.read"]
	}`)
	if _, err := ParseManifest(data); err == nil {
		t.Fatal("unsupported permission unexpectedly passed validation")
	}
}

func TestAPIVersionCompatibilityMatchesClient(t *testing.T) {
	tests := map[string]bool{
		"1.0":     true,
		"^1.0":    true,
		"1.1":     true,
		"^1.1":    true,
		"1.2":     false,
		"^1.2":    false,
		"2.0":     false,
		"^0.1":    false,
		"1.00000": false,
	}
	for requirement, want := range tests {
		t.Run(requirement, func(t *testing.T) {
			if got := supportsAPI(requirement, "1.1"); got != want {
				t.Fatalf("supportsAPI(%q, %q) = %v, want %v", requirement, "1.1", got, want)
			}
		})
	}
}

func TestManifestAcceptsAPI11Contract(t *testing.T) {
	data := []byte(`{
		"schemaVersion": 1,
		"id": "top.example.api11",
		"name": "API 1.1",
		"version": "1.0.0",
		"apiVersion": "1.1",
		"entry": "main.lua",
		"permissions": ["network.inspect", "game.camera.control"]
	}`)
	manifest, err := ParseManifest(data)
	if err != nil {
		t.Fatalf("parse API 1.1 manifest: %v", err)
	}
	if manifest.APIVersion != "1.1" {
		t.Fatalf("unexpected API version %q", manifest.APIVersion)
	}
}

func TestManifestMatchesClientNumericAndStringLimits(t *testing.T) {
	tooLargeVersion := []byte(`{
		"schemaVersion": 1,
		"id": "top.example.invalid",
		"name": "Invalid",
		"version": "2147483648.0.0",
		"apiVersion": "^1.0",
		"entry": "main.lua"
	}`)
	if _, err := ParseManifest(tooLargeVersion); err == nil {
		t.Fatal("32-bit version overflow unexpectedly passed validation")
	}

	// Each supplementary character occupies two UTF-16 code units in Kotlin.
	tooLongName := []byte(`{
		"schemaVersion": 1,
		"id": "top.example.invalid",
		"name": "` + string(bytes.Repeat([]byte("😀"), 65)) + `",
		"version": "1.0.0",
		"apiVersion": "^1.0",
		"entry": "main.lua"
	}`)
	if _, err := ParseManifest(tooLongName); err == nil {
		t.Fatal("UTF-16 display length overflow unexpectedly passed validation")
	}
}

func TestPackagePlacesManifestAtRoot(t *testing.T) {
	source := filepath.Join(repositoryRoot(t), "examples", "fps-counter")
	output := filepath.Join(t.TempDir(), "plugin.splug")
	if _, err := Pack(source, output); err != nil {
		t.Fatal(err)
	}
	data, err := os.ReadFile(output)
	if err != nil {
		t.Fatal(err)
	}
	reader, err := zip.NewReader(bytes.NewReader(data), int64(len(data)))
	if err != nil {
		t.Fatal(err)
	}
	if len(reader.File) == 0 || reader.File[0].Name != "main.lua" {
		t.Fatalf("entries are not sorted: first entry is %q", reader.File[0].Name)
	}
	found := false
	for _, entry := range reader.File {
		if entry.Name == "manifest.json" {
			found = true
		}
	}
	if !found {
		t.Fatal("manifest.json is not at archive root")
	}
}

func repositoryRoot(t *testing.T) string {
	t.Helper()
	_, filename, _, ok := runtime.Caller(0)
	if !ok {
		t.Fatal("cannot locate test source")
	}
	return filepath.Clean(filepath.Join(filepath.Dir(filename), "..", ".."))
}
