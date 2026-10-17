// Commander4Mac original code: GPL-3.0-only with the Citadel linking permission.
// See LICENSE and LICENSE-EXCEPTION at the repository root.

import SwiftUI
import CommanderCore

struct LocationBarView: View {
    var controller: WorkspaceController
    var paneID: PaneID
    @FocusState private var pathFocused: Bool
    @State private var path = ""
    var body: some View {
        let tab = controller.workspace.pane(paneID).activeTab
        HStack(spacing: 6) {
            Button { controller.history(paneID, forward: false) } label: { Image(systemName: "chevron.left") }.disabled(!tab.canGoBack).help("Back")
            Button { controller.history(paneID, forward: true) } label: { Image(systemName: "chevron.right") }.disabled(!tab.canGoForward).help("Forward")
            Button { controller.open(tab.location.parent, in: paneID) } label: { Image(systemName: "arrow.up") }.help("Parent Folder")
            TextField("Folder path", text: $path)
                .font(Font(AppearanceFont.resolve(tab.options.navigationFont, size: tab.options.navigationTextSize)))
                .frame(minHeight: max(tab.options.navigationIconSize, AppearanceFont.lineHeight(AppearanceFont.resolve(tab.options.navigationFont, size: tab.options.navigationTextSize))))
                .layoutPriority(1)
                .focused($pathFocused)
                .accessibilityLabel(paneID == .left ? "Left folder path" : "Right folder path")
                .textFieldStyle(.plain).accessibilityIdentifier(paneID.rawValue + ".path")
                .onSubmit {
                    controller.openPath(path, in: paneID)
                }
        }
        .font(.system(size: tab.options.navigationIconSize))
        .buttonStyle(.borderless).padding(.horizontal, 10).padding(.vertical, 8)
        .onChange(of: controller.focusRequest?.id) {
            if let request = controller.focusRequest, request.pane == paneID, request.field == .path { pathFocused = true }
        }
        .onChange(of: tab.location, initial: true) { _, value in path = value.url.path }
    }
}
