import SwiftUI
import CommanderCore

struct PaneView: View {
    var controller: WorkspaceController
    var paneID: PaneID
    @FocusState private var filterFocused: Bool
    var body: some View {
        let workspace = controller.workspace
        @Bindable var tab = workspace.pane(paneID).activeTab
        VStack(spacing: 0) {
            TabStripView(controller: controller, paneID: paneID)
            Rectangle().fill(workspace.activePane == paneID ? Color.accentColor : Color.primary.opacity(0.07)).frame(height: 2)
            LocationBarView(controller: controller, paneID: paneID)
            HStack(spacing: 6) {
                Image(systemName: "line.3.horizontal.decrease").foregroundStyle(.secondary)
                TextField("Filter this folder", text: $tab.filter).textFieldStyle(.plain)
                    .focused($filterFocused)
                    .accessibilityLabel(paneID == .left ? "Filter left folder" : "Filter right folder")
                    .accessibilityIdentifier(paneID.rawValue + ".filter")
                if !tab.filter.isEmpty { Button { tab.filter = "" } label: { Image(systemName: "xmark.circle.fill") }.buttonStyle(.plain).foregroundStyle(.secondary) }
                Menu {
                    Menu("Text Size") {
                        ForEach(11...20, id: \.self) { size in Button("\(size) pt") { tab.options.textSize = Double(size) } }
                    }
                    Menu("List Icon Size") {
                        ForEach([16,20,24,28,32], id: \.self) { size in Button("\(size) pt") { tab.options.listIconSize = Double(size) } }
                    }
                    Divider()
                    Toggle("Folders First", isOn: $tab.options.foldersFirst)
                    Toggle("Show Hidden Files", isOn: $tab.options.includeHidden)
                        .onChange(of: tab.options.includeHidden) { Task { await controller.refresh(paneID) } }
                } label: { Image(systemName: "slider.horizontal.3") }.menuStyle(.borderlessButton).fixedSize().help("View Options")
            }.font(.system(size: 12)).padding(.horizontal, 11).padding(.bottom, 8)
            Divider()
            ZStack {
                FileTableView(tab: tab, paneID: paneID, isActive: workspace.activePane == paneID,
                    onFocus: { workspace.activePane = paneID },
                    onActivate: { controller.activate($0, pane: paneID) },
                    onCommand: { controller.tableCommand($0, pane: paneID) },
                    renameRequest: controller.renamePane == paneID ? controller.renameRequest : nil,
                    onRename: { controller.rename($0, to: $1, pane: paneID) },
                    onDrop: { controller.acceptDrop($0) }, previewController: controller.quickLook,
                    focusRequest: controller.focusRequest?.pane == paneID && controller.focusRequest?.field == .files ? controller.focusRequest?.id : nil)
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
            Divider()
            HStack(spacing: 10) {
                Button("Copy to \(paneID == .left ? "Right" : "Left")") { controller.transferSelection(.copy, from: paneID) }
                Button("Move to \(paneID == .left ? "Right" : "Left")") { controller.transferSelection(.move, from: paneID) }
                Button("Stage") { workspace.activePane = paneID; controller.stageSelection() }
                Spacer()
            }.font(.system(size: 11)).buttonStyle(.borderless).padding(.horizontal, 11).padding(.vertical, 6)
                .disabled(tab.selection.isEmpty)
                .help("Destination: " + workspace.pane(paneID.opposite).activeTab.location.url.path)
            Divider()
            HStack {
                Text(tab.selection.isEmpty ? "\(tab.visibleEntries.count) items" : "\(tab.selection.count) selected")
                Spacer()
                if tab.isLoading { ProgressView().controlSize(.mini) }
                Text(paneID == .left ? "Left" : "Right").foregroundStyle(.tertiary)
            }.font(.system(size: 11)).foregroundStyle(.secondary).padding(.horizontal, 11).padding(.vertical, 7)
        }
        .onChange(of: controller.focusRequest?.id) {
            if let request = controller.focusRequest, request.pane == paneID, request.field == .filter { filterFocused = true }
        }
        .onChange(of: tab.pin) { controller.services.saveSoon() }
        .onChange(of: tab.options) { controller.services.saveSoon() }
        .task(id: tab.id.uuidString + tab.location.url.path) {
            for await _ in DirectoryWatcher().events(for: tab.location) {
                do { try await Task.sleep(for: .milliseconds(150)) } catch { return }
                if Task.isCancelled { return }
                await controller.refresh(paneID)
            }
        }
    }
}
