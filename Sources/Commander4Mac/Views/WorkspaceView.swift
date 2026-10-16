import SwiftUI
import CommanderCore

struct WorkspaceView: View {
    @State private var controller = WorkspaceController()
    @AppStorage("accessSetupAcknowledged") private var acknowledged = false
    @State private var showAccessSetup = false
    var body: some View {
        HStack(spacing: 0) {
            if controller.sidebarVisible {
                SidebarView(controller: controller).frame(width: 190)
                Divider()
            }
            HSplitView {
                PaneView(controller: controller, paneID: .left).frame(minWidth: 300)
                PaneView(controller: controller, paneID: .right).frame(minWidth: 300)
            }
        }
        .frame(minWidth: 980, minHeight: 620)
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button { controller.sidebarVisible.toggle() } label: { Image(systemName: "sidebar.left") }.help("Toggle Sidebar")
            }
            ToolbarItemGroup {
                Button { Task { await controller.refresh(.left); await controller.refresh(.right) } } label: { Image(systemName: "arrow.clockwise") }.help("Refresh")
                Button { showAccessSetup = true } label: { Image(systemName: "externaldrive.badge.checkmark") }.help("Full Disk Access Setup")
            }
        }
        .sheet(isPresented: $showAccessSetup) {
            AccessSetupView { acknowledged = true; showAccessSetup = false }
        }
        .task { showAccessSetup = !acknowledged; await controller.start() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            Task { await controller.refresh(.left); await controller.refresh(.right) }
        }
    }
}
