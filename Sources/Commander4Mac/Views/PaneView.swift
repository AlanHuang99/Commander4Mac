// Commander4Mac original code: GPL-3.0-only with the Citadel linking permission.
// See LICENSE and LICENSE-EXCEPTION at the repository root.

import SwiftUI
import CommanderCore

struct PaneView: View {
    var controller: WorkspaceController
    var paneID: PaneID
    @FocusState private var filterFocused: Bool
    @State private var showViewOptions = false
    @Environment(\.colorScheme) private var scheme
    private var workspace: WorkspaceSession { controller.workspace }
    private var tab: TabSession { workspace.pane(paneID).activeTab }
    private var palette: ThemePalette? { controller.services.preferences.theme.palette(isDark: scheme == .dark) }

    var body: some View {
        let tab = self.tab
        styledContent
            .onChange(of: controller.focusRequest?.id) {
                if let request = controller.focusRequest, request.pane == paneID, request.field == .filter { filterFocused = true }
            }
            .onChange(of: tab.pin) { controller.services.saveSoon() }
            .onChange(of: tab.options) { controller.services.saveSoon() }
            .task(id: tab.id.uuidString + tab.location.providerID + tab.location.url.path) {
                await watchDirectory(tab)
            }
    }

    private var content: some View {
        VStack(spacing: 0) {
            TabStripView(controller: controller, paneID: paneID)
            Rectangle().fill(workspace.activePane == paneID ? (palette?.accent.color ?? Color.accentColor) : Color.primary.opacity(0.07)).frame(height: 2)
            LocationBarView(controller: controller, paneID: paneID)
            filterBar
            Divider()
            ZStack { browserContent; listingOverlay }
            Divider()
            transferActions
            Divider()
            statusBar
        }
    }

    private var styledContent: some View {
        content.background(palette?.chrome.color ?? Color.clear)
            .foregroundStyle(palette?.text.color ?? Color.primary)
    }

    private func watchDirectory(_ tab: TabSession) async {
        for await _ in DirectoryWatcher().events(for: tab.location) {
            do { try await Task.sleep(for: .milliseconds(150)) } catch { return }
            if Task.isCancelled { return }
            await controller.refresh(paneID)
        }
    }

    private var filterBar: some View {
        @Bindable var tab = self.tab
        return HStack(spacing: 6) {
            Image(systemName: "line.3.horizontal.decrease").font(.system(size: tab.options.navigationIconSize)).foregroundStyle(palette?.secondaryText.color ?? .secondary)
            TextField("Filter this folder", text: $tab.filter).textFieldStyle(.plain)
                .focused($filterFocused)
                .accessibilityLabel(paneID == .left ? "Filter left folder" : "Filter right folder")
                .accessibilityIdentifier(paneID.rawValue + ".filter")
            if !tab.filter.isEmpty { Button { tab.filter = "" } label: { Image(systemName: "xmark.circle.fill") }.buttonStyle(.plain).foregroundStyle(.secondary) }
            Button { showViewOptions.toggle() } label: {
                Image(systemName: "slider.horizontal.3").font(.system(size: tab.options.navigationIconSize))
            }.buttonStyle(.borderless).help("View Options").accessibilityLabel("View Options")
                .accessibilityIdentifier(paneID.rawValue + ".viewOptions")
                .popover(isPresented: $showViewOptions, arrowEdge: .top) {
                    PaneViewOptions(controller: controller, paneID: paneID) { showViewOptions = false }
                }
        }.font(Font(AppearanceFont.resolve(tab.options.navigationFont, size: tab.options.navigationTextSize)))
            .padding(.horizontal, 11).padding(.bottom, 8)
    }

    private var browser: FileTableView {
        let workspace = self.workspace
        let tab = self.tab
        return FileTableView(tab: tab, revision: tab.entriesRevision, paneID: paneID, destination: workspace.pane(paneID.opposite).activeTab.location, isActive: workspace.activePane == paneID,
            onFocus: { workspace.activePane = paneID },
            onActivate: { controller.activate($0, pane: paneID) },
            onCommand: { controller.tableCommand($0, pane: paneID) },
            renameRequest: controller.renamePane == paneID ? controller.renameRequest : nil,
            onRename: { controller.rename($0, to: $1, pane: paneID) },
            onDrop: { controller.acceptDrop($0) }, previewController: controller.quickLook,
            focusRequest: controller.focusRequest?.pane == paneID && controller.focusRequest?.field == .files ? controller.focusRequest?.id : nil,
            palette: palette)
    }

    @ViewBuilder private var browserContent: some View {
        if tab.options.mode == .list { browser } else { FileGridView(browser: browser) }
    }

    @ViewBuilder private var listingOverlay: some View {
        if let failure = tab.failure {
            VStack(spacing: 12) {
                Image(systemName: failure.category == .accessDenied ? "lock.shield" : "folder.badge.questionmark").font(.largeTitle)
                Text(failure.detail).multilineTextAlignment(.center).font(.callout).frame(maxWidth: 330)
                Button("Retry") { Task { await controller.refresh(paneID) } }
            }.padding(24).frame(maxWidth: .infinity, maxHeight: .infinity).background(.background)
        } else if tab.isLoading && tab.visibleEntries.isEmpty {
            ProgressView().controlSize(.small)
        } else if tab.snapshot != nil && tab.visibleEntries.isEmpty {
            Text(tab.filter.isEmpty ? "This folder is empty" : "No matching files").foregroundStyle(.secondary)
        }
    }

    private var transferActions: some View {
        HStack(spacing: 10) {
            Button("Copy to \(paneID == .left ? "Right" : "Left")") { controller.transferSelection(.copy, from: paneID) }
                .disabled(!TransferCapabilities.canTransfer(.copy, from: tab.location, to: workspace.pane(paneID.opposite).activeTab.location, entries: tab.selectedEntries))
                .help("Copy to the other pane. Remote copies support regular files and folders.")
            Button("Move to \(paneID == .left ? "Right" : "Left")") { controller.transferSelection(.move, from: paneID) }.disabled(!tab.location.isLocal || !workspace.pane(paneID.opposite).activeTab.location.isLocal)
            Button("Stage") { workspace.activePane = paneID; controller.stageSelection() }.disabled(!tab.location.isLocal)
            Spacer()
        }.font(Font(AppearanceFont.resolve(tab.options.navigationFont, size: max(10, tab.options.navigationTextSize - 2))))
            .buttonStyle(.borderless).padding(.horizontal, 11).padding(.vertical, 6)
            .disabled(tab.selection.isEmpty || tab.failure != nil)
            .help("Destination: " + workspace.pane(paneID.opposite).activeTab.location.url.path)
    }

    private var statusBar: some View {
        HStack {
            Text(tab.failure != nil ? "Unavailable" : (tab.selection.isEmpty ? "\(tab.visibleEntries.count) items" : "\(tab.selection.count) selected"))
            Spacer()
            if tab.isLoading { ProgressView().controlSize(.mini) }
            if let id = tab.location.profileID {
                Text(controller.services.connections.profiles.first(where: { $0.id == id })?.name ?? "Connection")
                    .lineLimit(1).help(controller.services.connections.states[id]?.rawValue ?? "Disconnected")
            }
            Text(paneID == .left ? "Left" : "Right").foregroundStyle(.tertiary)
        }.font(Font(AppearanceFont.resolve(tab.options.navigationFont, size: max(10, tab.options.navigationTextSize - 2))))
            .foregroundStyle(palette?.secondaryText.color ?? .secondary).padding(.horizontal, 11).padding(.vertical, 7)
    }
}
