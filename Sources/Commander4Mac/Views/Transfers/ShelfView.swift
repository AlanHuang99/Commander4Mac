// Commander4Mac original code: GPL-3.0-only with the Citadel linking permission.
// See LICENSE and LICENSE-EXCEPTION at the repository root.

import SwiftUI
import UniformTypeIdentifiers
import CommanderCore

struct ShelfView: View {
    var controller: WorkspaceController
    @State private var dropTargeted = false
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Shelf", systemImage: "tray.full").fontWeight(.semibold)
                Text(controller.services.shelf.items.isEmpty ? "Drop files here to collect them for later" : "Stage files from any folder").foregroundStyle(.secondary)
                Spacer()
                Button("Add Selection") { controller.stageSelection() }
                    .disabled(controller.workspace.activeTab.selection.isEmpty)
                Button("Clear") { controller.services.shelf.clear(); controller.services.saveSoon() }
                    .disabled(controller.services.shelf.items.isEmpty)
                Button { controller.shelfVisible = false } label: { Image(systemName: "xmark") }.buttonStyle(.plain).help("Hide Shelf")
            }.font(.system(size: 12))
            if !controller.services.shelf.items.isEmpty {
                ScrollView(.horizontal) {
                    HStack(spacing: 7) {
                        ForEach(controller.services.shelf.items) { item in
                            HStack(spacing: 6) {
                                Image(systemName: controller.services.shelf.unavailable[item.id] == nil ? "doc" : "exclamationmark.triangle")
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.displayName).lineLimit(1)
                                    Text(item.reference.displayURL.deletingLastPathComponent().path).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
                                }.frame(maxWidth: 200, alignment: .leading)
                                Button {
                                    controller.services.shelf.remove(ids: [item.id]); controller.services.saveSoon()
                                } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }.buttonStyle(.plain).help("Remove from Shelf")
                            }.contextMenu { Button("Relink Item…") { controller.relinkStagedItem(item) } }
                                .help(controller.services.shelf.unavailable[item.id] ?? item.reference.displayURL.path)
                                .font(.system(size: 12)).padding(7).background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 6))
                        }
                    }
                }.frame(height: 48)
            }
            if !controller.services.shelf.items.isEmpty {
                HStack(spacing: 18) {
                    transferButtons(.left)
                    Divider().frame(height: 26)
                    transferButtons(.right)
                }
            }
        }
        .padding(12)
        .background(dropTargeted ? Color.accentColor.opacity(0.1) : Color(nsColor: .controlBackgroundColor))
        .onDrop(of: [UTType.fileURL.identifier], isTargeted: $dropTargeted) { providers in
            stageProviders(providers, controller: controller)
        }
        .accessibilityIdentifier("stagingShelf")
    }
    private func transferButtons(_ pane: PaneID) -> some View {
        HStack(spacing: 8) {
            Text(pane == .left ? "Left:" : "Right:").fontWeight(.medium)
            Text(controller.workspace.pane(pane).activeTab.location.url.path).lineLimit(1).truncationMode(.middle).foregroundStyle(.secondary)
            Spacer(minLength: 2)
            Button(pane == .left ? "Copy to Left" : "Copy to Right") { controller.transferShelf(.copy, to: pane) }
            Button(pane == .left ? "Move to Left" : "Move to Right") { controller.transferShelf(.move, to: pane) }
        }.font(.system(size: 11))
    }
}

@MainActor @discardableResult
func stageProviders(_ providers: [NSItemProvider], controller: WorkspaceController) -> Bool {
    let supported = providers.filter { $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) }
    guard !supported.isEmpty else { return false }
    Task {
        do {
            var locations: [FileLocation] = []
            for provider in supported {
                let data: Data = try await withCheckedThrowingContinuation { continuation in
                    provider.loadDataRepresentation(forTypeIdentifier: UTType.fileURL.identifier) { data, error in
                        if let data { continuation.resume(returning: data) }
                        else { continuation.resume(throwing: error ?? CocoaError(.fileReadCorruptFile)) }
                    }
                }
                if let url = URL(dataRepresentation: data, relativeTo: nil), url.isFileURL { locations.append(.local(url)) }
            }
            try await controller.services.shelf.stage(locations); controller.services.saveSoon(); controller.shelfVisible = true
        } catch { controller.errorMessage = error.localizedDescription }
    }
    return true
}
