package plugin

import (
	"archive/zip"
	"crypto/sha256"
	"encoding/hex"
	"errors"
	"fmt"
	"io"
	"io/fs"
	"os"
	"path/filepath"
	"sort"
	"strings"
	"time"
)

const (
	maxArchiveBytes   = 32 * 1024 * 1024
	maxExtractedBytes = 64 * 1024 * 1024
	maxSingleFile     = 16 * 1024 * 1024
	maxLuaSource      = 2 * 1024 * 1024
	maxFileCount      = 512
)

var zipTimestamp = time.Date(1980, 1, 1, 0, 0, 0, 0, time.UTC)

type fileEntry struct {
	absolutePath string
	archivePath  string
	size         int64
}

type PackageInfo struct {
	Manifest Manifest
	Files    int
	Bytes    int64
}

type PackResult struct {
	Path   string
	SHA256 string
	Files  int
}

func Validate(path string) (PackageInfo, error) {
	info, err := os.Stat(path)
	if err != nil {
		return PackageInfo{}, err
	}
	if info.IsDir() {
		manifest, entries, total, err := validateDirectory(path)
		if err != nil {
			return PackageInfo{}, err
		}
		return PackageInfo{Manifest: manifest, Files: len(entries), Bytes: total}, nil
	}
	return validateArchive(path)
}

func Pack(source, output string) (PackResult, error) {
	manifest, entries, _, err := validateDirectory(source)
	if err != nil {
		return PackResult{}, err
	}

	source, err = filepath.Abs(source)
	if err != nil {
		return PackResult{}, err
	}
	if output == "" {
		output = filepath.Join(
			filepath.Dir(source),
			fmt.Sprintf("%s-%s.splug", manifest.ID, manifest.Version),
		)
	}
	output, err = filepath.Abs(output)
	if err != nil {
		return PackResult{}, err
	}
	if !strings.EqualFold(filepath.Ext(output), ".splug") {
		return PackResult{}, errors.New("output file must use the .splug extension")
	}
	if inside, err := isInside(output, source); err != nil {
		return PackResult{}, err
	} else if inside {
		return PackResult{}, errors.New("output file must be outside the plugin source directory")
	}
	if _, err := os.Stat(output); err == nil {
		return PackResult{}, fmt.Errorf("output already exists: %s", output)
	} else if !errors.Is(err, os.ErrNotExist) {
		return PackResult{}, err
	}
	if err := os.MkdirAll(filepath.Dir(output), 0o755); err != nil {
		return PackResult{}, err
	}

	temp, err := os.CreateTemp(filepath.Dir(output), ".samp-plugin-*.tmp")
	if err != nil {
		return PackResult{}, err
	}
	tempPath := temp.Name()
	cleanup := true
	defer func() {
		_ = temp.Close()
		if cleanup {
			_ = os.Remove(tempPath)
		}
	}()

	archive := zip.NewWriter(temp)
	for _, entry := range entries {
		header := &zip.FileHeader{
			Name:     entry.archivePath,
			Method:   zip.Deflate,
			Modified: zipTimestamp,
		}
		header.SetMode(0o644)
		writer, err := archive.CreateHeader(header)
		if err != nil {
			return PackResult{}, err
		}
		input, err := os.Open(entry.absolutePath)
		if err != nil {
			return PackResult{}, err
		}
		_, copyErr := io.Copy(writer, input)
		closeErr := input.Close()
		if copyErr != nil {
			return PackResult{}, copyErr
		}
		if closeErr != nil {
			return PackResult{}, closeErr
		}
	}
	if err := archive.Close(); err != nil {
		return PackResult{}, err
	}
	if err := temp.Sync(); err != nil {
		return PackResult{}, err
	}
	if err := temp.Close(); err != nil {
		return PackResult{}, err
	}
	info, err := os.Stat(tempPath)
	if err != nil {
		return PackResult{}, err
	}
	if info.Size() > maxArchiveBytes {
		return PackResult{}, fmt.Errorf("package exceeds %d bytes", maxArchiveBytes)
	}
	if err := os.Rename(tempPath, output); err != nil {
		return PackResult{}, err
	}
	cleanup = false

	digest, err := fileSHA256(output)
	if err != nil {
		return PackResult{}, err
	}
	return PackResult{
		Path:   output,
		SHA256: digest,
		Files:  len(entries),
	}, nil
}

func validateDirectory(root string) (Manifest, []fileEntry, int64, error) {
	root, err := filepath.Abs(root)
	if err != nil {
		return Manifest{}, nil, 0, err
	}
	entries := make([]fileEntry, 0)
	var total int64
	err = filepath.WalkDir(root, func(path string, entry fs.DirEntry, walkErr error) error {
		if walkErr != nil {
			return walkErr
		}
		if path == root {
			return nil
		}
		if entry.Type()&os.ModeSymlink != 0 {
			return fmt.Errorf("symbolic links are not supported: %s", path)
		}
		if entry.IsDir() {
			return nil
		}
		info, err := entry.Info()
		if err != nil {
			return err
		}
		if !info.Mode().IsRegular() {
			return fmt.Errorf("unsupported file type: %s", path)
		}
		relative, err := filepath.Rel(root, path)
		if err != nil {
			return err
		}
		archivePath := filepath.ToSlash(relative)
		if !safeRelativePath(archivePath) {
			return fmt.Errorf("unsafe package path: %s", archivePath)
		}
		if err := validateFileSize(archivePath, info.Size()); err != nil {
			return err
		}
		total += info.Size()
		if total > maxExtractedBytes {
			return fmt.Errorf("package expands beyond %d bytes", maxExtractedBytes)
		}
		entries = append(entries, fileEntry{
			absolutePath: path,
			archivePath:  archivePath,
			size:         info.Size(),
		})
		if len(entries) > maxFileCount {
			return fmt.Errorf("package contains more than %d files", maxFileCount)
		}
		return nil
	})
	if err != nil {
		return Manifest{}, nil, 0, err
	}
	sort.Slice(entries, func(i, j int) bool {
		return entries[i].archivePath < entries[j].archivePath
	})
	manifestPath := filepath.Join(root, "manifest.json")
	manifestData, err := os.ReadFile(manifestPath)
	if err != nil {
		if errors.Is(err, os.ErrNotExist) {
			return Manifest{}, nil, 0, errors.New("manifest.json must be at the package root")
		}
		return Manifest{}, nil, 0, err
	}
	manifest, err := ParseManifest(manifestData)
	if err != nil {
		return Manifest{}, nil, 0, err
	}
	entryPath := filepath.Join(root, filepath.FromSlash(manifest.Entry))
	info, err := os.Stat(entryPath)
	if err != nil || !info.Mode().IsRegular() || info.Size() > maxLuaSource {
		return Manifest{}, nil, 0, errors.New("plugin entry file is missing or too large")
	}
	return manifest, entries, total, nil
}

func validateArchive(path string) (PackageInfo, error) {
	if !strings.EqualFold(filepath.Ext(path), ".splug") {
		return PackageInfo{}, errors.New("plugin package must use the .splug extension")
	}
	info, err := os.Stat(path)
	if err != nil {
		return PackageInfo{}, err
	}
	if info.Size() > maxArchiveBytes {
		return PackageInfo{}, fmt.Errorf("package exceeds %d bytes", maxArchiveBytes)
	}
	reader, err := zip.OpenReader(path)
	if err != nil {
		return PackageInfo{}, fmt.Errorf("open plugin package: %w", err)
	}
	defer reader.Close()
	if len(reader.File) == 0 {
		return PackageInfo{}, errors.New("plugin package is empty")
	}
	if len(reader.File) > maxFileCount {
		return PackageInfo{}, fmt.Errorf("package contains more than %d entries", maxFileCount)
	}

	seen := make(map[string]struct{}, len(reader.File))
	var total int64
	var manifestData []byte
	regularFiles := 0
	entryNames := make(map[string]struct{})
	for _, entry := range reader.File {
		name := strings.TrimSuffix(entry.Name, "/")
		if !safeRelativePath(name) {
			return PackageInfo{}, fmt.Errorf("unsafe package path: %s", entry.Name)
		}
		if _, ok := seen[entry.Name]; ok {
			return PackageInfo{}, fmt.Errorf("duplicate package path: %s", entry.Name)
		}
		seen[entry.Name] = struct{}{}
		if entry.FileInfo().IsDir() {
			continue
		}
		if !entry.Mode().IsRegular() {
			return PackageInfo{}, fmt.Errorf("unsupported package entry type: %s", entry.Name)
		}
		limit := int64(maxSingleFile)
		if strings.HasSuffix(strings.ToLower(name), ".lua") {
			limit = maxLuaSource
		}
		data, err := readZipEntry(entry, limit)
		if err != nil {
			return PackageInfo{}, fmt.Errorf("%s: %w", name, err)
		}
		total += int64(len(data))
		if total > maxExtractedBytes {
			return PackageInfo{}, fmt.Errorf("package expands beyond %d bytes", maxExtractedBytes)
		}
		regularFiles++
		entryNames[name] = struct{}{}
		if name == "manifest.json" {
			manifestData = data
		}
	}
	if manifestData == nil {
		return PackageInfo{}, errors.New("manifest.json must be at the package root")
	}
	manifest, err := ParseManifest(manifestData)
	if err != nil {
		return PackageInfo{}, err
	}
	if _, ok := entryNames[manifest.Entry]; !ok {
		return PackageInfo{}, errors.New("plugin entry file is missing")
	}
	return PackageInfo{
		Manifest: manifest,
		Files:    regularFiles,
		Bytes:    total,
	}, nil
}

func readZipEntry(entry *zip.File, limit int64) ([]byte, error) {
	reader, err := entry.Open()
	if err != nil {
		return nil, err
	}
	defer reader.Close()
	data, err := io.ReadAll(io.LimitReader(reader, limit+1))
	if err != nil {
		return nil, err
	}
	if int64(len(data)) > limit {
		return nil, fmt.Errorf("file exceeds %d bytes", limit)
	}
	return data, nil
}

func validateFileSize(name string, size int64) error {
	limit := int64(maxSingleFile)
	if strings.HasSuffix(strings.ToLower(name), ".lua") {
		limit = maxLuaSource
	}
	if size > limit {
		return fmt.Errorf("%s exceeds %d bytes", name, limit)
	}
	if name == "manifest.json" && size > maxManifestBytes {
		return fmt.Errorf("manifest.json exceeds %d bytes", maxManifestBytes)
	}
	return nil
}

func safeRelativePath(path string) bool {
	if strings.TrimSpace(path) == "" ||
		strings.HasPrefix(path, "/") ||
		strings.HasPrefix(path, `\`) ||
		strings.Contains(path, `\`) ||
		strings.ContainsRune(path, '\x00') {
		return false
	}
	for _, part := range strings.Split(path, "/") {
		if part == "" || part == "." || part == ".." {
			return false
		}
	}
	return true
}

func isInside(path, parent string) (bool, error) {
	if !strings.EqualFold(filepath.VolumeName(path), filepath.VolumeName(parent)) {
		return false, nil
	}
	relative, err := filepath.Rel(parent, path)
	if err != nil {
		return false, err
	}
	return relative != ".." &&
			!strings.HasPrefix(relative, ".."+string(filepath.Separator)),
		nil
}

func fileSHA256(path string) (string, error) {
	file, err := os.Open(path)
	if err != nil {
		return "", err
	}
	defer file.Close()
	digest := sha256.New()
	if _, err := io.Copy(digest, file); err != nil {
		return "", err
	}
	return hex.EncodeToString(digest.Sum(nil)), nil
}
