# Mont-E Architecture & Engineering Standards

This document outlines the architectural patterns, concurrency model, packaging rules, and release automation pipelines for Mont-E.

---

## 🏛️ Core Principles

1. **Pure Swift 6 & Complete Strict Concurrency**:
   - UI-bound types (`MonteViewModel`, SwiftUI Views) are marked `@MainActor`.
   - Asynchronous telemetry collectors conform to `Sendable` or execute within dedicated actors/locks.
   - Zero `@unchecked Sendable` without strict justification.
2. **AppKit Lifecycle Integration**:
   - Menu bar resident accessory (`LSUIElement = YES` in `Info.plist`).
   - Managed by `AppDelegate` conforming to `NSApplicationDelegate`.
   - Uses `NSStatusItem` and native `NSMenu` to support complex dynamic nested submenus and popovers without UIKit/Catalyst overhead.
3. **Safe Subprocess Execution**:
   - All external helper processes (e.g. `pmset`, `system_profiler`, `smartctl`, `battery`) are invoked via Foundation `Process` and `Pipe` with explicit argument arrays.
   - String concatenation and shell execution via `/bin/sh -c` are strictly avoided.
4. **Pre-Commit Privacy & Security Guarantee**:
   - Never commit machine-specific paths (e.g. `/Users/<username>/...`).
   - Never commit sensitive developer credentials, certificates, or tokens.

---

## 📦 Packaging & Distribution Pipeline

* **Centralized Package Output**: All production builds generate self-contained, ad-hoc codesigned macOS DMG installers into `Packages/`:
  $$\text{MontE/Packages/Monte-<version>.dmg}$$
* **Automated Build Tooling (`./build.sh`)**:
  - Compiles release binary with `swift build -c release`.
  - Assembles macOS `.app` bundle with `Info.plist` and `AppIcon.icns`.
  - Performs ad-hoc code signing (`codesign --force --deep --sign -`).
  - Assembles a read-write disk image, applies the volume icon with `SetFile`, converts to compressed `UDZO` format, and places it in `Packages/`.
  - Automatically installs/replaces the version in `/Applications/Monte.app`.

---

## 🔄 Release Automation & Versioning

* **Version Management (`./scripts/bump-version.sh`)**:
  - Automatically updates `VERSION`, `Info.plist`, `Sources/Monte/Resources/Info.plist`, and `Packages/README.md`.
  - Supports `major`, `minor`, `patch`, or explicit semver targets (e.g. `2.1.0`).
* **GitHub Actions Workflows**:
  - `release-auto-minor.yml`: Triggers on push to `main`, bumps minor version, generates the release DMG, creates a signed Git tag (`vX.Y.Z`), and uploads the DMG asset to GitHub Releases.
  - `release-manual-major.yml`: Workflow dispatch allowing manual control over version increments and pre-release flags.
