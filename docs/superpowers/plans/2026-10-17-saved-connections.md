# Saved Connections Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans inline as already requested. Steps use checkbox syntax.

**Goal:** Make saving and opening existing remote connections clear and fast.
**Architecture:** Reuse transactional profile/Keychain persistence. Add a catalog chooser to the existing connection editor and keep sidebar actions routed through the existing connection controller.
**Tech Stack:** SwiftUI, CommanderCore, XCTest UI tests.
**Spec:** `docs/superpowers/specs/2026-10-17-saved-connections-design.md`

## Global Constraints

- Preserve all protocols, profile identities, saved secrets and host-key verification.
- Never connect automatically on launch; never expose credentials in UI evidence or logs.
- Reuse the active worktree and execute inline without approval handoffs.

## Review Focus

- Loading a saved profile must not trigger protocol defaults that overwrite its custom endpoint.
- Switching profiles must clear transient secrets and errors without crossing credential scopes.
- Save without Connect must create a reusable profile and perform no network operation.
- Duplicate display names must still identify distinct endpoints and profile IDs.
- Relaunch must retain the connection and removal must use transactional cleanup.

### Task 1: Saved chooser and clear persistence actions

**Files:** modify `ConnectionEditor.swift`, `SidebarView.swift`, `Tests/Commander4MacUITests/ConnectionUITests.swift`; add a focused saved-connection chooser if needed.
**Interfaces:** Existing `ConnectionController.profiles/save/secret/remove`, `ConnectionProfile` and `ConnectionSubmission` remain authoritative. Bind a chooser to profile ID; loading a saved profile atomically replaces non-secret editor state while clearing transient values.

- [ ] Add UI tests for saving an owned synthetic SMB profile without connecting, relaunching, loading its port/share/path unchanged, switching profiles without secret carryover and removing it. Expected: saved chooser/action labels are absent before implementation.
- [ ] Implement chooser, New Connection, Save Connection and Save and Connect labels and explanatory quick-access text. Keep retry/cancel/host-key behavior intact.
- [ ] Run `./script/test.sh` and focused connection UI tests. Expected: core suite and owned UI flows pass. Inspect Cmd-K and sidebar quick access in installed Dev app without changing real saved profiles. Commit UI and tests.
