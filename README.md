# SA-MP Android Plugin Tools

[English](README.md) | [简体中文](README.zh-CN.md) | [Русский](README.ru.md)

Public developer tools and examples for building SA-MP Android Lua plugins.

This repository does not contain the SA-MP Android client source code. The client is closed source, and plugins interact with the host exclusively through the documented Lua API.

## Contents

- `samp-plugin`: a cross-platform Go CLI for validating plugin projects and creating `.splug` packages.
- `api/schema.json`: a machine-readable snapshot of the current Plugin API 1.0 contract.
- `examples/`: independent example plugins that can be validated, packaged, and installed.

## Install

Download the archive for your operating system and architecture from the [latest GitHub Release](https://github.com/SA-MP-Android/Plugin-Tools/releases/latest):

1. Choose the archive whose name matches your platform, such as `windows_amd64`, `linux_arm64`, or `darwin_arm64`.
2. Extract `samp-plugin` or `samp-plugin.exe`.
3. Move the executable to a directory on `PATH`, or invoke it using its full path.

Release archives include binaries for Windows, Linux, and macOS on amd64 and arm64. Verify downloaded files against `checksums.txt` when integrity matters.

Check the installed CLI version with `samp-plugin version`.

## Validate a plugin

Validate a source directory:

```bash
samp-plugin validate examples/fps-counter
```

Validate an existing package:

```bash
samp-plugin validate fps-counter-1.0.0.splug
```

Validation covers manifest field types and limits, SemVer, API compatibility, permissions, contexts, the Lua entry file, portable and safe paths, file counts, and the same package size limits enforced by the client.

## Package a plugin

```bash
samp-plugin pack examples/fps-counter
```

By default, the package is written to the parent of the source directory as `<plugin-id>-<version>.splug`. Specify a different destination when needed:

```bash
samp-plugin pack --output dist/fps-counter.splug examples/fps-counter
```

The tool never overwrites an existing file. It writes sorted portable paths, fixed timestamps, and fixed file permissions, so identical input produces identical bytes and SHA-256 hashes. `manifest.json` is always stored at the archive root.

## Plugin layout

The minimal project layout is:

```text
my-plugin/
├── manifest.json
└── main.lua
```

Optional directories include `modules/`, `assets/`, and `locales/`. Package paths always use `/` and may not contain absolute paths, backslashes, empty segments, `.` segments, or `..` segments.

Refer to the official SA-MP Android documentation for the complete Lua API, event arguments, permissions, and runtime limits. `api/schema.json` is the contract snapshot shipped for a client release; changes to it must be accompanied by updated tests and examples.

## Development

Go 1.24 or newer is required. The CLI uses only the Go standard library.

```bash
go test ./...
go vet ./...
go build -o bin/samp-plugin ./cmd/samp-plugin
```

Generated binaries and `.splug` packages are not committed. Release tags matching `v*` trigger the release workflow, which tests the project, builds all supported platform archives, generates SHA-256 checksums, and publishes a GitHub Release.

## License

This repository is licensed under the [MIT License](LICENSE).
