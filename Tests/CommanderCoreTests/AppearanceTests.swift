// Commander4Mac original code: GPL-3.0-only with the Citadel linking permission.
// See LICENSE and LICENSE-EXCEPTION at the repository root.

import XCTest
import CommanderCore

@MainActor final class AppearanceTests: XCTestCase {
    func testComfortableTextAndIconsAreNotReducedToOldMaximums() {
        var options = ViewOptions()
        options.textSize = 26; options.listIconSize = 40; options.gridIconSize = 160
        let restored = options.validated()
        XCTAssertEqual(restored.textSize, 26)
        XCTAssertEqual(restored.listIconSize, 40)
        XCTAssertEqual(restored.gridIconSize, 160)
    }

    func testLegacyPreferencesKeepTheirValuesAndGainSharedAppearance() throws {
        let fixture = try FixtureDirectory()
        let store = PreferencesStore(directory: fixture.url)
        try Data("""
        {"appearance":"dark","view":{"textSize":17,"listIconSize":24,"gridIconSize":80,"sortColumn":"modified","ascending":false},"defaultDestination":"right","restoreSession":false}
        """.utf8).write(to: store.fileURL)
        let value = store.load()
        XCTAssertEqual(value.appearance, .dark)
        XCTAssertEqual(value.defaultDestination, .right)
        XCTAssertFalse(value.restoreSession)
        XCTAssertEqual(value.view.textSize, 17)
        XCTAssertEqual(value.view.listIconSize, 24)
        XCTAssertEqual(value.view.sortColumn, .modified)
        XCTAssertFalse(value.view.ascending)
        let encoded = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(value)) as? [String: Any])
        XCTAssertEqual(encoded["shareAppearanceChanges"] as? Bool, true)
        XCTAssertEqual(encoded["sidebarWidth"] as? Double, 220)
    }

    func testSharingUpdatesInactiveTabsAndWindowsWithoutChangingBehaviorOrSelection() async throws {
        let fixture = try FixtureDirectory(); let file = try fixture.file("keep.txt")
        let first = WorkspaceSession(left: .local(fixture.url), right: .local(fixture.url))
        let second = WorkspaceSession(left: .local(fixture.url), right: .local(fixture.url))
        let tab = first.left.activeTab
        tab.options.sortColumn = .size; tab.options.ascending = false; tab.options.mode = .icons
        tab.options.includeHidden = true; tab.options.visibleColumns = ["name", "size"]
        tab.pin = .navigable(home: tab.location)
        _ = tab.apply(try await LocalFileSystem().list(tab.location, options: .init()), for: tab.requestNavigation(to: tab.location))
        tab.selection = [EntryID(file)]; tab.scrollAnchor = EntryID(file); tab.filter = "keep"
        first.left.tabs.append(TabSession(location: .local(fixture.url)))
        var style = ViewAppearance(); style.textSize = 23; style.navigationTextSize = 19
        style.font = .rounded; style.navigationFont = .monospaced; style.listIconSize = 36
        let preferences = AppearanceSharing.update(style, selectedTab: tab, preferences: .init(), workspaces: [first, second])
        for workspace in [first, second] {
            for pane in [workspace.left, workspace.right] {
                for item in pane.tabs {
                    XCTAssertEqual(item.options.textSize, 23)
                    XCTAssertEqual(item.options.navigationTextSize, 19)
                    XCTAssertEqual(item.options.font, .rounded)
                }
            }
            XCTAssertEqual(workspace.defaultOptions.navigationFont, .monospaced)
        }
        XCTAssertEqual(preferences.view.listIconSize, 36)
        XCTAssertEqual(tab.options.sortColumn, .size); XCTAssertFalse(tab.options.ascending)
        XCTAssertEqual(tab.options.mode, .icons); XCTAssertTrue(tab.options.includeHidden)
        XCTAssertEqual(tab.options.visibleColumns, ["name", "size"])
        XCTAssertEqual(tab.filter, "keep"); XCTAssertEqual(tab.selection, [EntryID(file)])
        XCTAssertEqual(tab.scrollAnchor, EntryID(file)); XCTAssertEqual(tab.pin, .navigable(home: .local(fixture.url)))
        XCTAssertEqual(tab.history, [.local(fixture.url)])
    }

    func testOptOutKeepsStyleLocalThroughNavigationAndSessionRoundTrip() throws {
        let fixture = try FixtureDirectory()
        let workspace = WorkspaceSession(left: .local(fixture.url))
        var preferences = Preferences(); preferences.shareAppearanceChanges = false
        var style = ViewAppearance(); style.textSize = 24; style.navigationIconSize = 28
        preferences = AppearanceSharing.update(style, selectedTab: workspace.left.activeTab, preferences: preferences, workspaces: [workspace])
        _ = workspace.open(.local(fixture.url.appendingPathComponent("child")))
        XCTAssertEqual(workspace.left.activeTab.options.textSize, 24)
        XCTAssertEqual(workspace.right.activeTab.options.textSize, 13)
        XCTAssertEqual(preferences.view.textSize, 13)
        let restored = try JSONDecoder().decode(WorkspaceSnapshot.self, from: JSONEncoder().encode(WorkspaceSnapshot(workspace))).restore()
        XCTAssertEqual(restored.left.activeTab.options.textSize, 24)
        XCTAssertEqual(restored.left.activeTab.options.navigationIconSize, 28)
        XCTAssertEqual(restored.right.activeTab.options.textSize, 13)
        _ = workspace.open(.local(fixture.url), inNewTab: true)
        XCTAssertEqual(workspace.left.activeTab.options.textSize, 13)
    }

    func testDefaultOnlyEditAndEnablingSharingUseCurrentDefaults() {
        let workspace = WorkspaceSession(); var preferences = Preferences()
        preferences.shareAppearanceChanges = false
        var local = ViewAppearance(); local.textSize = 22
        _ = AppearanceSharing.update(local, selectedTab: workspace.left.activeTab, preferences: preferences, workspaces: [workspace])
        var defaults = ViewAppearance(); defaults.textSize = 17; defaults.gridIconSize = 104
        preferences = AppearanceSharing.update(defaults, selectedTab: nil, preferences: preferences, workspaces: [workspace])
        XCTAssertEqual(workspace.left.activeTab.options.textSize, 22)
        XCTAssertEqual(workspace.right.activeTab.options.textSize, 13)
        XCTAssertEqual(workspace.defaultOptions.gridIconSize, 104)
        preferences.shareAppearanceChanges = true
        preferences = AppearanceSharing.update(preferences.view.viewAppearance, selectedTab: nil, preferences: preferences, workspaces: [workspace])
        XCTAssertEqual(workspace.left.activeTab.options.textSize, 17)
        XCTAssertEqual(workspace.right.activeTab.options.textSize, 17)
        _ = workspace.open(.local(URL(fileURLWithPath: "/tmp")), inNewTab: true)
        XCTAssertEqual(workspace.activeTab.options.gridIconSize, 104)
    }

    func testInvalidVisualFieldsClampIndependentlyAndDoNotErasePreferences() throws {
        let fixture = try FixtureDirectory(); let store = PreferencesStore(directory: fixture.url)
        try Data("""
        {"appearance":"dark","theme":"future-theme","shareAppearanceChanges":false,"sidebarWidth":999,"defaultDestination":"left","restoreSession":false,"view":{"textSize":-9,"listIconSize":900,"gridIconSize":1,"navigationTextSize":900,"navigationIconSize":0,"font":{"kind":"family","family":"bad\\nfont"},"navigationFont":{"kind":"future-font"}}}
        """.utf8).write(to: store.fileURL)
        let value = store.load()
        XCTAssertEqual(value.appearance, .dark); XCTAssertEqual(value.defaultDestination, .left)
        XCTAssertFalse(value.shareAppearanceChanges); XCTAssertFalse(value.restoreSession)
        XCTAssertEqual(value.theme, .system); XCTAssertEqual(value.sidebarWidth, 320)
        XCTAssertEqual(value.view.textSize, 10); XCTAssertEqual(value.view.listIconSize, 40)
        XCTAssertEqual(value.view.gridIconSize, 32); XCTAssertEqual(value.view.navigationTextSize, 24)
        XCTAssertEqual(value.view.navigationIconSize, 12); XCTAssertEqual(value.view.font, .system)
        XCTAssertEqual(value.view.navigationFont, .system)
    }

    func testVisualDefaultsAndCustomFontsSurvivePreferencesRoundTrip() throws {
        let fixture = try FixtureDirectory(); let store = PreferencesStore(directory: fixture.url)
        var value = Preferences(); value.theme = .forest; value.sidebarWidth = 280
        value.view.font = .family("Avenir Next"); value.view.navigationFont = .serif
        value.view.navigationTextSize = 20; value.view.navigationIconSize = 24
        try store.save(value)
        XCTAssertEqual(store.load(), value)
        var invalid = ViewAppearance(); invalid.textSize = .nan; invalid.navigationTextSize = .infinity
        invalid.navigationIconSize = -.infinity
        XCTAssertEqual(invalid.validated().textSize, 13)
        XCTAssertEqual(invalid.validated().navigationTextSize, 13)
        XCTAssertEqual(invalid.validated().navigationIconSize, 16)
    }

    func testPaletteLuminanceAndEveryThemeKeepTextReadable() throws {
        XCTAssertEqual(ThemeColor(hex: 0x000000).contrastRatio(with: ThemeColor(hex: 0xffffff)), 21, accuracy: 0.001)
        XCTAssertEqual(ThemeColor(hex: 0x777777).contrastRatio(with: ThemeColor(hex: 0x777777)), 1, accuracy: 0.001)
        for theme in ThemeID.allCases where theme != .system {
            for isDark in [false, true] {
                let palette = try XCTUnwrap(theme.palette(isDark: isDark))
                for surface in [palette.background, palette.chrome] {
                    XCTAssertGreaterThanOrEqual(palette.text.contrastRatio(with: surface), 4.5, "\(theme), dark=\(isDark)")
                    XCTAssertGreaterThanOrEqual(palette.secondaryText.contrastRatio(with: surface), 4.5, "\(theme), dark=\(isDark)")
                }
                XCTAssertGreaterThanOrEqual(palette.selectedText.contrastRatio(with: palette.selection), 4.5)
            }
        }
    }
}
