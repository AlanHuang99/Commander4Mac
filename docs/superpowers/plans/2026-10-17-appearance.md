# Shared Appearance Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans inline as already requested. Steps use checkbox syntax.

**Goal:** Make file and navigation appearance configurable and shared by default, with optional tab-local changes and polished themes.
**Architecture:** Keep visual values separate from tab behavior. Preferences publish visual updates through all registered workspaces; native renderers consume those same values.
**Tech Stack:** Swift 6, Observation, SwiftUI, AppKit, XCTest.
**Spec:** `docs/superpowers/specs/2026-10-17-appearance-design.md`

## Global Constraints

- Preserve existing sessions, profiles, permissions, production/dev identities and macOS 15+.
- Share appearance by default; never overwrite independent sorting, filtering, view modes, pins, selection or location history.
- Preserve old JSON; ranges/defaults and theme names follow the spec exactly.
- Full authorization permits inline work, installation and publication without additional approval gates.

## Review Focus

- Corrupt or old font/style fields must not discard unrelated saved preferences or session state.
- A settings change while another window/tab is inactive must apply when it becomes visible.
- Turning sharing off must preserve local styling through nested navigation and relaunch.
- Large fonts/icons must not clip editable paths, file labels, buttons or selection indicators.
- Theme changes must retain readable selected/inactive rows in list and icon modes.

### Task 1: Appearance model and sharing semantics

**Files:** create `Sources/CommanderCore/Models/ViewAppearance.swift`, `Sources/CommanderCore/Models/Theme.swift`, `Tests/CommanderCoreTests/AppearanceTests.swift`; modify `ViewOptions.swift`, `PreferencesStore.swift`, `WorkspaceSession.swift` and preference tests.
**Interfaces:** Produce `ViewAppearance`, `FontChoice`, `ThemeID`, `ThemePalette`, `ViewOptions.viewAppearance`, `WorkspaceSession.applyAppearance(_:)`, and Preferences sharing/theme/sidebar values. Existing flat size fields remain encoded for compatibility.

- [ ] Write tests for old JSON preserving sizes and new defaults, invalid/clamped values, round trips, multi-pane visual-only propagation, nested navigation/local restore and palette contrast. Run `./script/test.sh AppearanceTests`; Expected: missing behavior fails before implementation.
- [ ] Implement models, validated decoding and `applyAppearance(_:)` that updates defaults/current tabs without changing behavioral fields. Add font-family validation/fallback and adaptive palettes.
- [ ] Run `./script/test.sh`; Expected: all core tests pass, opt-in integration skips only. Commit models and tests.

### Task 2: Shared UI, fonts, navigation and themes

**Files:** modify `AppServices.swift`, `WorkspaceController.swift`, `SettingsView.swift`, `PaneView.swift`, `LocationBarView.swift`, `TabStripView.swift`, `SidebarView.swift`, `WorkspaceView.swift`, native table/grid files; create focused appearance controls and rendering helpers under `Sources/Commander4Mac/Views/Appearance` and `Support`.
**Interfaces:** Consume Task 1. `AppServices.updateAppearance(_:for:)` routes pane edits; Settings edit shared defaults. Registration/restoration applies current shared appearance. Theme rendering reaches native tables/grids as well as SwiftUI chrome.

- [ ] Add an owned UI regression for shared existing tabs/windows and opt-out; Expected: current fixed path/default-only behavior fails. Preserve user state by using the UITest identity.
- [ ] Implement grouped settings, font-family pickers, theme swatches, preview, reset, sharing toggle and pane appearance controls. Connect fonts/sizes/colors to every relevant renderer and sidebar width.
- [ ] Run `./script/test.sh`, a Debug app build and focused appearance UI acceptance; Expected: tests/build pass and actual rendered controls respond. Inspect minimum/maximum sizing in installed Dev app and retain evidence. Commit UI.
