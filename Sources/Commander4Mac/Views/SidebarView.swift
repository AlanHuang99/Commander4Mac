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
