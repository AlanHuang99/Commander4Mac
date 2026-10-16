# Commander4Mac

A native macOS file explorer built around two independent panes, fast keyboard navigation, and useful defaults.

## Project status

As of October 16, 2026, this repository contains the proposed design and reference research. Application implementation has not started.

- [Proposed design](docs/superpowers/specs/2026-10-16-commander4mac-design.md)
- [Reference observations and sources](docs/research/2026-10-16-reference-review.md)

## Product direction

- Two panes with independent tabs, history, selection, and view options.
- Favorites, connections, and a shared shelf for staging files from multiple locations.
- Locked pins and navigable pins with a saved home location.
- System, Light, and Dark appearance; separate text and icon sizes.
- Explicit destination routing to the current, left, or right pane.
- Reliable local file operations, followed by integrated SFTP, SMB, and WebDAV.
- An original interface informed by established file-management workflows.

## Development direction

Use the Build macOS Apps plugin workflows. The proposed implementation combines SwiftUI scenes and settings with AppKit file tables. Keep browsing state, file access, transfer execution, and persistence separate.

The first implementation milestone is a working local file manager. Remote protocols are planned follow-up milestones, not implemented features.

## Environment prerequisite

On October 16, 2026, the installed Xcode toolchain reported that its license agreements had not been accepted. The user must review and accept Apple's agreements before compilation can be verified. No license acceptance or system permission changes were performed.
