// Commander4Mac original code: GPL-3.0-only with the Citadel linking permission.
// See LICENSE and LICENSE-EXCEPTION at the repository root.

import SwiftUI
import CommanderCore

struct TabStripView: View {
    var controller: WorkspaceController
    var paneID: PaneID
    var body: some View {
        let pane = controller.workspace.pane(paneID)
        let options = pane.activeTab.options
        HStack(spacing: 2) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 3) {
                    ForEach(pane.tabs) { tab in
                        HStack(spacing: 4) {
                            Button { controller.selectTab(tab, pane: paneID) } label: {
                                HStack(spacing: 5) {
                                    Image(systemName: tab.pin.isLocked ? "lock.fill" : (tab.pin.isPinned ? "pin.fill" : "folder"))
                                        .font(.system(size: max(10, options.navigationIconSize - 4))).foregroundStyle(tab.pin.isPinned ? Color.accentColor : .secondary)
                                    Text(tab.title).lineLimit(1)
                                    if let home = tab.pin.home, home != tab.location { Image(systemName: "arrow.uturn.backward").font(.caption2) }
                                }.padding(.leading, 9).padding(.vertical, 8)
                            }.buttonStyle(.plain)
                                .accessibilityLabel(tab.title + (tab.pin.isLocked ? ", locked pin" : (tab.pin.isPinned ? ", navigable pin" : ", tab")))
                                .help(tab.location.url.path)
                            if !tab.pin.isPinned && pane.tabs.count > 1 {
                                Button { _ = pane.close(tabID: tab.id); Task { await controller.refresh(paneID) } } label: { Image(systemName: "xmark").font(.system(size: max(9, options.navigationIconSize - 6))) }.buttonStyle(.plain).padding(.trailing, 7)
                            }
                        }
                        .padding(.trailing, tab.pin.isPinned || pane.tabs.count == 1 ? 9 : 0)
                        .background(pane.activeTabID == tab.id ? Color.primary.opacity(0.09) : .clear, in: RoundedRectangle(cornerRadius: 5))
                        .contextMenu {
                            Button("Pin Folder (Locked)") { tab.pin = .locked(home: tab.location) }
                            Button("Pin Folder (Allow Navigation)") { tab.pin = .navigable(home: tab.location) }
                            if tab.pin.isPinned {
                                Button("Return to Pinned Folder") { controller.selectTab(tab, pane: paneID) }
                                Button("Use Current Folder as Pin Home") { tab.pin = tab.pin.isLocked ? .locked(home: tab.location) : .navigable(home: tab.location) }
                                Button("Unpin") { tab.pin = .none }
                            }
                            Button("Duplicate Tab") { controller.open(tab.location, in: paneID, newTab: true) }
                        }
                    }
                }
            }
            Button { controller.open(pane.activeTab.location, in: paneID, newTab: true) } label: { Image(systemName: "plus").font(.system(size: options.navigationIconSize)) }.buttonStyle(.borderless).help("New Tab")
        }.font(Font(AppearanceFont.resolve(options.navigationFont, size: options.navigationTextSize)))
            .padding(.horizontal, 7).padding(.vertical, 5)
    }
}
