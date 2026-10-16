import SwiftUI
import CommanderCore

struct WorkspaceView: View {
    @Environment(\.openWindow) private var openWindow
    @State private var controller = WorkspaceController()
    @AppStorage("accessSetupAcknowledged") private var acknowledged = false
    @State private var showAccessSetup = false
    var body: some View {
        HStack(spacing: 0) {
            if controller.sidebarVisible {
                SidebarView(controller: controller).frame(width: 190)
                Divider()
            }
            GeometryReader { geometry in
                HStack(spacing: 0) {
                    PaneView(controller: controller, paneID: .left)
                        .frame(width: max(290, min(geometry.size.width - 295, geometry.size.width * controller.workspace.splitRatio)))
                    Rectangle().fill(Color.primary.opacity(0.1)).frame(width: 5)
                        .contentShape(Rectangle())
                        .gesture(DragGesture(coordinateSpace: .named("panes")).onChanged { value in
                            controller.workspace.splitRatio = min(0.8, max(0.2, value.location.x / geometry.size.width))
                        }.onEnded { _ in controller.services.saveSoon() })
                        .help("Drag to resize panes")
                    PaneView(controller: controller, paneID: .right).frame(maxWidth: .infinity)
                }.coordinateSpace(name: "panes")
            }
        }
        .frame(minWidth: 980, minHeight: 620)
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button { controller.sidebarVisible.toggle() } label: { Image(systemName: "sidebar.left") }.help("Toggle Sidebar")
            }
            ToolbarItemGroup {
                Button { controller.addFavorite() } label: { Image(systemName: "star.badge.plus") }.help("Favorite Current Folder")
                Button { Task { await controller.refresh(.left); await controller.refresh(.right) } } label: { Image(systemName: "arrow.clockwise") }.help("Refresh")
                Button { showAccessSetup = true } label: { Image(systemName: "externaldrive.badge.checkmark") }.help("Full Disk Access Setup")
            }
        }
        .sheet(isPresented: $showAccessSetup) {
            AccessSetupView { acknowledged = true; showAccessSetup = false }
        }
        .task {
            showAccessSetup = !acknowledged
            let count = await controller.start()
            for _ in 0..<count { openWindow(id: "workspace") }
        }
        .onDisappear { controller.services.unregister(controller) }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.willResignActiveNotification)) { _ in controller.services.saveNow() }
        .alert("Commander4Mac", isPresented: Binding(get: { controller.errorMessage != nil }, set: { if !$0 { controller.errorMessage = nil } })) {
            Button("OK") { controller.errorMessage = nil }
        } message: { Text(controller.errorMessage ?? "") }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            Task { await controller.refresh(.left); await controller.refresh(.right) }
        }
    }
}
