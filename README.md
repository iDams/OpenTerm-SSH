# OpenTerm SSH

OpenTerm SSH is an open source SSH/SFTP client project built around a reusable C core on top of vendored `libssh`.

Current vendored `libssh` version: `0.11.3`

## What This Project Is

OpenTerm SSH is a personal SSH client project focused on:

- a reusable SSH/SFTP core in C
- a macOS-first app layer in SwiftUI
- a clean separation between the transport/core layer and future platform UIs
- experimenting with ideas commonly seen in modern SSH clients

This project is inspired by the general experience and feature direction of other SSH clients, but it is its own independent implementation.

## Current Scope

Today the project includes:

- SSH connections with strict host key verification by default
- password, public key, and keyboard-interactive authentication support
- SFTP support in the core
- a macOS app in active development
- a reusable C core intended to support future platform layers
- a manual CLI tool for smoke testing and debugging

## Project Status

This is an experimental project for learning, exploration, and personal use.

It is not a production-ready SSH client yet.

You should expect:

- incomplete features
- implementation changes
- bugs
- rough edges
- possible security issues or other vulnerabilities

I do not recommend using this project for professional, business-critical, or security-sensitive workloads until it reaches a clearly stable release.

This is not a project I am working on full-time. My main focus is on other projects, and this repository is developed in my spare time for experimentation and entertainment while sharing progress publicly.

## Responsible Use Notice

If you notice:

- legal issues
- licensing mistakes
- trademark concerns
- security problems
- serious architectural problems

please open an issue or submit a pull request describing the problem clearly.

If there is any infringement or compliance issue that I am not aware of, I would rather have it pointed out and corrected than ignored.

## Architecture

```text
┌────────────────────────────────────────┐
│  libssh + OpenSSL                      │
│  ↓ SSH foundation                      │
├────────────────────────────────────────┤
│  openterm_core (C wrapper layer)       │
├────────────────────────────────────────┤
│  Platform UI layers                    │
│  - SwiftUI (macOS, current platform)   │
│  - iOS/Windows/Linux (future)          │
└────────────────────────────────────────┘
```

## Repository Layout

```text
term/
├── core/           # C wrapper over libssh
├── platforms/      # Platform-specific implementations
│   └── macos/      # Current SwiftUI app layer
├── docs/           # Project documentation
├── scripts/        # Build scripts
├── tools/          # Manual CLI / smoke-test tools
└── tests/          # Tests
```

## Development Status

Current maintained paths in this repository:

- the C core is built with CMake
- the macOS app uses `dist/OpenTermCore.xcframework`
- the current product direction and phases live in [docs/ROADMAP.md](docs/ROADMAP.md)
- the `libssh` update process lives in [docs/UPDATING_LIBSSH.md](docs/UPDATING_LIBSSH.md)
- the stable public core surface lives in [docs/CORE_API.md](docs/CORE_API.md)
- the Apple dependency migration path lives in [docs/APPLE_BUILD.md](docs/APPLE_BUILD.md)

Dependency contracts today:

- the general core build uses `vendor/libssh`
- the supported macOS app build uses Apple-native artifacts under `vendor/apple/`

The supported macOS app path is `./scripts/build_macos_app.sh`.

## Minimum Requirements

| Tool | Purpose |
|------|---------|
| CMake 3.20+ | Core build system |
| Git | Source management |
| C compiler | `gcc`, `clang`, or MSVC-compatible toolchain |

In most development environments, you should not need to install `libssh` manually.

## Build The Core

Check requirements:

```bash
./scripts/check-requirements.sh
```

Build:

```bash
./scripts/build.sh
```

## Manual CLI Smoke Test

The manual CLI lives in `tools/` and is meant for smoke testing and debugging, not as the main product surface.

Example:

```bash
cd core/build
./openterm_cli <host> <user> "ls -la"
```

It will try default private keys from `~/.ssh/` (`id_ed25519`, `id_ecdsa`, `id_rsa`).

It also supports explicit flags such as:

```bash
./openterm_cli --host example.com --user alice --command "uname -a" --port 22
./openterm_cli --host example.com --user alice --key ~/.ssh/id_ed25519
```

## macOS App

Official macOS build path:

1. build Apple OpenSSL artifacts
2. build Apple `libssh` artifacts
3. generate `dist/OpenTermCore.xcframework`
4. build the Swift package in `platforms/macos/`

Recommended command:

```bash
./scripts/build_macos_app.sh
```

That command is the supported one-command macOS build for Apple Silicon. It prepares the Apple dependency chain itself before building the Swift package.

Explicit step-by-step path:

```bash
./scripts/build_apple_openssl.sh
./scripts/build_apple_libssh.sh
./scripts/build_apple_xcframework.sh
swift build --package-path platforms/macos
```

Prerequisites:

- Xcode / Swift toolchain with macOS support
- Apple dependency artifacts prepared under `vendor/apple/`
- Apple Silicon (`arm64`) Mac
- OpenSSL is part of the Apple dependency chain and remains relevant not only technically but also for license/compliance review when distributing binaries

Important:

- `platforms/macos/Package.swift` depends on `dist/OpenTermCore.xcframework`
- if that artifact does not exist yet, the package will fail explicitly
- the official Apple-platform path in this repo is currently centered on the macOS app, not iOS
- the supported macOS build target is Apple Silicon (`arm64`) only
- the official Apple dependency story is described in [docs/APPLE_BUILD.md](docs/APPLE_BUILD.md)
- the Apple dependency path uses prepared artifacts under `vendor/apple/`, generated from sources under `vendor/sources/`

## Tests

Automated core tests live in `core/tests/`.

The manual CLI lives in `tools/`.

## Licensing

- Project code: GPL-3.0, see [LICENSE](LICENSE)
- Third-party dependencies and notices: see [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)
- OpenSSL remains part of the shipped/native dependency story, so binary distribution should review its license and notices in addition to `libssh`

## Contributing

Contributions are welcome, especially when they improve:

- correctness
- reproducibility
- security
- documentation clarity
- platform build hygiene

See [docs/DEV.md](docs/DEV.md).

## FAQ

### Do I need Homebrew to build this?

Not for the official Apple path anymore.

The intended Apple build now uses prepared Apple-native OpenSSL and `libssh` artifacts under `vendor/apple/`. Homebrew may still be convenient in some local development scenarios, but it is no longer the official dependency story for the macOS package.

### Is this ready for professional use?

No. Treat it as an experimental project until there is a stable release with a clearer security and distribution story.

### Can I distribute it?

Yes, with conditions. If you distribute binaries, you must comply with GPL-3.0 and with the licenses and notices of bundled or linked dependencies.

### Can I publish it in an app store?

That requires specific legal review. Some store terms may conflict with GPL-style distribution models.
