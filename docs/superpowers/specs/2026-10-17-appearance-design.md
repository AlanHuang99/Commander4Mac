# Shared appearance and themes

## Intent and scope

Make typography and navigation as adjustable as file icons, with consistent changes across existing and future workspaces by default. The user's screenshot identifies the path/filter/navigation strip as a required surface. Full authorization covers inline design and implementation without further approval handoffs. Reuse the existing isolated worktree and preserve installed app identity, permissions, connections and workspace state.

## Chosen approach

Share only visual fields through app preferences, with an opt-out for tab-local edits. Per-folder configuration would add complexity; replacing every tab's ViewOptions would destroy independent sorting and filtering. Keep appearance, browser behavior and location state separate.

`ViewAppearance` contains file font, text size, list/grid icon sizes, navigation font/text/icon sizes. Font choices include System, Rounded, Serif, Monospaced and installed font families, with safe System fallback for unavailable families. Existing ViewOptions JSON retains its legacy fields; missing new values gain defaults without discarding old preferences or sessions. Clamp finite file text to 10...28, list icons to 12...40, grid icons to 32...160, navigation text to 10...24 and navigation icons to 12...28. Defaults retain file text 13, list icons 20 and grid icons 64; new navigation defaults are System 13 and icons 16.

`shareAppearanceChanges` defaults true. Settings changes update defaults and all existing tabs/windows when enabled. Pane appearance edits do the same when enabled; when disabled they affect only that tab and persist through folder navigation and session restore. Settings then adjust defaults for future tabs without overwriting existing tab styles. Re-enabling sharing applies the current defaults everywhere. Sidebar uses the app's navigation defaults, with configurable width 180...320 (default 220). Themes and light/dark/system mode remain app-wide.

## UI and rendering

Settings Appearance contains theme swatches, readable grouped typography controls, sidebar width, sharing toggle, live preview and reset. Pane View Options exposes the same visual controls and sharing toggle, while keeping sort/columns/mode local. Path, filter, navigation buttons and tab strip honor navigation sizing. AppKit tables and collections honor chosen fonts and icon sizes, with row/cell geometry adapting and selection/scroll state retained.

System uses native materials and colors. Ocean, Forest, Sand and Plum provide original palettes inspired by the user's Color Hunt reference, without runtime palette requests. Each has light/dark content, chrome, text, secondary text, accent and selection colors. Text/background pairs must achieve measured contrast of at least 4.5:1. Native menus and dialogs retain macOS behavior.

## Verification

Test legacy decoding, malformed values, independent clamping, preference/session round trips, sharing across multiple panes/windows, opt-out, re-enabling, nested navigation, restored/new tabs and preservation of sort/filter/pins/history/selection. Check all curated palette text contrasts. Build and inspect the installed development app at minimum and maximum sizes, both view modes, multiple windows, light/dark/system and theme switching. Restore the user's appearance after visual checks unless their new choice is explicit.
