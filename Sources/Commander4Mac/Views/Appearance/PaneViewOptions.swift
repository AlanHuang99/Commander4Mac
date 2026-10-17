// Commander4Mac original code: GPL-3.0-only with the Citadel linking permission.
// See LICENSE and LICENSE-EXCEPTION at the repository root.

import SwiftUI
import CommanderCore

struct PaneViewOptions: View {
    let controller: WorkspaceController
    let paneID: PaneID
    let close: () -> Void
    @State private var showNavigation = false
    @State private var showFolderOptions = false
    private var prefix: String { paneID.rawValue + ".appearance" }
    private var style: Binding<ViewAppearance> {
        Binding(get: { controller.workspace.pane(paneID).activeTab.options.viewAppearance },
                set: { controller.services.updateAppearance($0, for: controller.workspace.pane(paneID).activeTab) })
    }
    var body: some View {
        @Bindable var tab = controller.workspace.pane(paneID).activeTab
        @Bindable var services = controller.services
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("View Options").font(.headline)
                Spacer()
                Button("Done", action: close).accessibilityIdentifier(prefix + ".done")
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Picker("View", selection: $tab.options.mode) {
                        Text("List").tag(BrowserViewMode.list); Text("Icons").tag(BrowserViewMode.icons)
                    }.pickerStyle(.segmented)
                    AppearanceSharingToggle(shared: $services.preferences.shareAppearanceChanges, prefix: prefix)
                    Divider()
                    FileAppearanceControls(appearance: style, prefix: prefix)
                    DisclosureGroup("Navigation", isExpanded: $showNavigation) {
                        NavigationAppearanceControls(appearance: style, prefix: prefix).padding(.top, 10)
                    }
                    Divider()
                    DisclosureGroup("Sort and Columns", isExpanded: $showFolderOptions) {
                        VStack(alignment: .leading, spacing: 12) {
                            Picker("Sort by", selection: $tab.options.sortColumn) {
                                Text("Name").tag(SortColumn.name); Text("Size").tag(SortColumn.size)
                                Text("Modified").tag(SortColumn.modified); Text("Kind").tag(SortColumn.kind)
                            }
                            Toggle("Ascending", isOn: $tab.options.ascending)
                            Toggle("Folders first", isOn: $tab.options.foldersFirst)
                            Toggle("Show hidden files", isOn: $tab.options.includeHidden)
                                .onChange(of: tab.options.includeHidden) { Task { await controller.refresh(paneID) } }
                            ForEach(["size", "modified"], id: \.self) { column in
                                Toggle("Show " + column + " column", isOn: Binding(get: { tab.options.visibleColumns.contains(column) }, set: { enabled in
                                    if enabled && !tab.options.visibleColumns.contains(column) { tab.options.visibleColumns.append(column) }
                                    if !enabled { tab.options.visibleColumns.removeAll { $0 == column } }
                                }))
                            }
                        }.padding(.top, 10)
                    }
                    Button("Reset This View’s Appearance") { services.updateAppearance(.init(), for: tab) }
                }.padding(.trailing, 3)
            }.frame(maxHeight: 510)
        }.font(.system(size: 13)).padding(18).frame(width: 330)
    }
}
