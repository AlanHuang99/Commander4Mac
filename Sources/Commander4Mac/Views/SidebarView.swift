import SwiftUI
import CommanderCore

struct SidebarView: View {
    var controller: WorkspaceController
    private let locations: [(String, String, URL)] = [
        ("Home", "house", FileManager.default.homeDirectoryForCurrentUser),
        ("Desktop", "desktopcomputer", FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Desktop")),
        ("Documents", "doc", FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Documents")),
        ("Downloads", "arrow.down.circle", FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads")),
        ("Applications", "square.grid.2x2", URL(fileURLWithPath: "/Applications"))
    ]
    var body: some View {
        List {
            Section("Favorites") {
                ForEach(controller.services.favorites.items) { favorite in
                    Button { controller.openFavorite(favorite) } label: { Label(favorite.name, systemImage: "star") }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button("Open in Current Pane") { controller.openFavorite(favorite, destination: .current) }
                            Button("Open in Left Pane") { controller.openFavorite(favorite, destination: .left) }
                            Button("Open in Right Pane") { controller.openFavorite(favorite, destination: .right) }
                            Button("Open in New Tab") { controller.openFavorite(favorite, newTab: true) }
                            Divider()
                            Button("Rename…") { controller.renameFavorite(favorite) }
                            Button("Move Up") {
                                if let index = controller.services.favorites.items.firstIndex(where: { $0.id == favorite.id }) {
                                    controller.services.favorites.move(id: favorite.id, to: max(0, index - 1)); controller.services.saveSoon()
                                }
                            }
                            Button("Remove Favorite") { controller.services.favorites.remove(id: favorite.id); controller.services.saveSoon() }
                        }
                }
                Button { controller.addFavorite() } label: { Label("Add Current Folder", systemImage: "plus") }
                    .buttonStyle(.plain).foregroundStyle(.secondary)
            }
            Section("Locations") {
                ForEach(locations, id: \.0) { title, icon, url in
                    Button { controller.open(.local(url)) } label: { Label(title, systemImage: icon) }
                        .buttonStyle(.plain).padding(.vertical, 3)
                }
            }
            Section("Volumes") {
                ForEach(FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: nil, options: [.skipHiddenVolumes]) ?? [], id: \.self) { url in
                    Button { controller.open(.local(url)) } label: { Label(url.lastPathComponent, systemImage: "externaldrive") }.buttonStyle(.plain)
                }
            }
        }.listStyle(.sidebar)
    }
}
