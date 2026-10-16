import SwiftUI
import CommanderCore

struct PaneView: View {
    var controller: WorkspaceController
    var paneID: PaneID
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
                    .accessibilityIdentifier(paneID.rawValue + ".filter")
                if !tab.filter.isEmpty { Button { tab.filter = "" } label: { Image(systemName: "xmark.circle.fill") }.buttonStyle(.plain).foregroundStyle(.secondary) }
                Menu {
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
                    onCommand: { controller.tableCommand($0, pane: paneID) })
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
            HStack {
                Text(tab.selection.isEmpty ? "\(tab.visibleEntries.count) items" : "\(tab.selection.count) selected")
                Spacer()
                if tab.isLoading { ProgressView().controlSize(.mini) }
                Text(paneID == .left ? "Left" : "Right").foregroundStyle(.tertiary)
            }.font(.system(size: 11)).foregroundStyle(.secondary).padding(.horizontal, 11).padding(.vertical, 7)
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
