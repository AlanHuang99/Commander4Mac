// Commander4Mac original code: GPL-3.0-only with the Citadel linking permission.
// See LICENSE and LICENSE-EXCEPTION at the repository root.

import SwiftUI
import CommanderCore

struct SidebarView: View {
    var controller: WorkspaceController
    @Environment(\.colorScheme) private var scheme
    private let locations: [(String, String, URL)] = [
        ("Home", "house", FileManager.default.homeDirectoryForCurrentUser),
        ("Desktop", "desktopcomputer", FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Desktop")),
        ("Documents", "doc", FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Documents")),
        ("Downloads", "arrow.down.circle", FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads")),
        ("Applications", "square.grid.2x2", URL(fileURLWithPath: "/Applications"))
    ]
    private func setDestination(_ favorite: Favorite, _ destination: OpenDestination?) {
        if let index = controller.services.favorites.items.firstIndex(where: { $0.id == favorite.id }) {
            controller.services.favorites.items[index].destination = destination; controller.services.saveSoon()
        }
    }
    var body: some View {
        let options = controller.services.preferences.view
        let palette = controller.services.preferences.theme.palette(isDark: scheme == .dark)
        List {
            Section("Favorites") {
                ForEach(controller.services.favorites.items) { favorite in
                    Button { controller.openFavorite(favorite) } label: { Label(favorite.name, systemImage: "star").frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle()) }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button("Open in Current Pane") { controller.openFavorite(favorite, destination: .current) }
                            Button("Open in Left Pane") { controller.openFavorite(favorite, destination: .left) }
                            Button("Open in Right Pane") { controller.openFavorite(favorite, destination: .right) }
                            Button("Open in New Tab") { controller.openFavorite(favorite, newTab: true) }
                            Divider()
                            Menu("Default Destination") {
                                Button("Use App Default") { setDestination(favorite, nil) }
                                Button("Current Pane") { setDestination(favorite, .current) }
                                Button("Left Pane") { setDestination(favorite, .left) }
                                Button("Right Pane") { setDestination(favorite, .right) }
                            }
                            Button("Relink Folder…") { controller.relinkFavorite(favorite) }
                            Button("Rename…") { controller.renameFavorite(favorite) }
                            Button("Move Up") {
                                if let index = controller.services.favorites.items.firstIndex(where: { $0.id == favorite.id }) {
                                    controller.services.favorites.move(id: favorite.id, to: max(0, index - 1)); controller.services.saveSoon()
                                }
                            }
                            Button("Move Down") {
                                if let index = controller.services.favorites.items.firstIndex(where: { $0.id == favorite.id }) {
                                    controller.services.favorites.move(id: favorite.id, to: index + 1); controller.services.saveSoon()
                                }
                            }
                            Button("Remove Favorite") { controller.services.favorites.remove(id: favorite.id); controller.services.saveSoon() }
                        }
                }
                Button { controller.addFavorite() } label: { Label("Add Current Folder", systemImage: "plus").frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle()) }
                    .buttonStyle(.plain).foregroundStyle(.secondary)
            }
            Section("Saved Connections") {
                ForEach(controller.services.connections.profiles) { profile in
                    SavedConnectionRow(controller: controller, profile: profile, options: options, palette: palette)
                }
                Button { controller.manageConnection() } label: { Label("New Connection…", systemImage: "plus").frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle()) }.buttonStyle(.plain)
                if let diagnostic = controller.services.connections.diagnostic { Text(diagnostic).font(.caption).foregroundStyle(.secondary) }
            }
            Section("Locations") {
                ForEach(locations, id: \.0) { title, icon, url in
                    Button { controller.open(.local(url)) } label: { Label(title, systemImage: icon).frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle()) }
                        .buttonStyle(.plain).padding(.vertical, 3)
                }
            }
            Section("Volumes") {
                ForEach(FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: nil, options: [.skipHiddenVolumes]) ?? [], id: \.self) { url in
                    Button { controller.open(.local(url)) } label: { Label(url.lastPathComponent, systemImage: "externaldrive").frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle()) }.buttonStyle(.plain)
                }
            }
        }.listStyle(.sidebar)
            .font(Font(AppearanceFont.resolve(options.navigationFont, size: options.navigationTextSize)))
            .labelStyle(SidebarNavigationLabelStyle(iconSize: options.navigationIconSize))
            .scrollContentBackground(palette == nil ? .automatic : .hidden)
            .background(palette?.chrome.color ?? .clear)
            .foregroundStyle(palette?.text.color ?? .primary)
    }
}

private struct SidebarNavigationLabelStyle: LabelStyle {
    let iconSize: Double
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 9) {
            configuration.icon.font(.system(size: iconSize)).frame(width: iconSize + 3)
            configuration.title.lineLimit(1)
        }
    }
}

private struct SavedConnectionRow: View {
    let controller: WorkspaceController
    let profile: ConnectionProfile
    let options: ViewOptions
    let palette: ThemePalette?
    private var status: String { controller.services.connections.states[profile.id]?.rawValue ?? "Disconnected" }
    private var captionFont: Font { Font(AppearanceFont.resolve(options.navigationFont, size: max(10, options.navigationTextSize - 2))) }
    var body: some View {
        Button { controller.connectSaved(profile) } label: { connectionLabel }
            .buttonStyle(.plain)
            .accessibilityLabel(profile.name + ", " + profile.endpointSummary + ", " + status)
            .help("\(profile.username)@\(profile.host):\(profile.port) · \(status)")
            .contextMenu { connectionActions }
    }
    private var connectionLabel: some View {
        Label {
            VStack(alignment: .leading, spacing: 3) {
                Text(profile.name)
                Text(profile.endpointSummary).font(captionFont).foregroundStyle(palette?.secondaryText.color ?? Color.secondary)
            }
        } icon: { Image(systemName: "network") }
            .frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
    }
    @ViewBuilder private var connectionActions: some View {
        Button("Open in Current Pane") { controller.connectSaved(profile, destination: .current) }
        Button("Open in Left Pane") { controller.connectSaved(profile, destination: .left) }
        Button("Open in Right Pane") { controller.connectSaved(profile, destination: .right) }
        Button("Edit Connection…") { controller.manageConnection(profile) }
        Button("Disconnect") { disconnect() }
        Button("Remove Connection") { remove() }
    }
    private func disconnect() {
        Task { await controller.services.remote.disconnect(profile.id); await controller.refresh(.left); await controller.refresh(.right) }
    }
    private func remove() {
        Task { do { try await controller.services.connections.remove(profile) } catch { controller.errorMessage = error.localizedDescription } }
    }
}
