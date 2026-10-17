// Commander4Mac original code: GPL-3.0-only with the Citadel linking permission.
// See LICENSE and LICENSE-EXCEPTION at the repository root.

import SwiftUI
import CommanderCore

struct WorkspaceView: View {
    @Environment(\.undoManager) private var undoManager
    @Environment(\.openWindow) private var openWindow
    @State private var controller = WorkspaceController()
    @AppStorage("accessSetupAcknowledged") private var acknowledged = false
    @State private var showAccessSetup = false
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        VStack(spacing: 0) {
        if controller.services.updateRelaunch.phase != .idle {
            UpdateStatusBanner(services: controller.services)
        }
        HStack(spacing: 0) {
            if controller.sidebarVisible {
                SidebarView(controller: controller).frame(width: controller.services.preferences.sidebarWidth)
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
        }.disabled(controller.services.updateRelaunch.blocksNewOperations)
            if controller.shelfVisible { Divider(); ShelfView(controller: controller) }
            if controller.activityVisible { Divider(); ActivityView(services: controller.services) }
        }
        .background(WindowRegistration(controller: controller).frame(width: 0, height: 0))
        .frame(minWidth: 980, minHeight: 620)
        .preferredColorScheme(controller.services.preferences.appearance.colorScheme)
        .tint(controller.services.preferences.theme.palette(isDark: scheme == .dark)?.accent.color ?? .accentColor)
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button { controller.sidebarVisible.toggle() } label: { Image(systemName: "sidebar.left") }.help("Toggle Sidebar")
            }
            ToolbarItemGroup {
                Button { controller.manageConnection() } label: { Label("Connect", systemImage: "network") }
                    .help("Connect to Server").accessibilityIdentifier("connections.open")
                Button { controller.shelfVisible.toggle() } label: { Image(systemName: "tray.full") }.help("Toggle Shelf")
                Button { controller.activityVisible.toggle() } label: {
                    Label("Activity \(controller.services.activeJobCount)", systemImage: "arrow.left.arrow.right")
                }.help("Show File Operations")
                Button { controller.addFavorite() } label: { Image(systemName: "star") }.help("Favorite Current Folder")
                Button { Task { await controller.refresh(.left); await controller.refresh(.right) } } label: { Image(systemName: "arrow.clockwise") }.help("Refresh")
                Button { showAccessSetup = true } label: { Image(systemName: "externaldrive.badge.checkmark") }.help("Full Disk Access Setup")
            }
        }
        .sheet(isPresented: $controller.showConnections) { ConnectionEditor(controller: controller, profile: controller.editingConnection, request: controller.editingConnectionRequest) }
        .sheet(isPresented: $showAccessSetup) {
            AccessSetupView { acknowledged = true; showAccessSetup = false }
        }
        .sheet(item: Binding(get: {
            controller.services.conflictPresenter == controller.workspace.id ? controller.services.pendingConflict : nil
        }, set: { _ in })) { conflict in
            ConflictSheet(conflict: conflict) { controller.services.resolve(conflict, $0) }
        }
        .task {
            controller.services.openWorkspaceWindow = { openWindow(id: "workspace") }
            controller.undoManager = undoManager
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

private struct UpdateStatusBanner: View {
    let services: AppServices
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "arrow.triangle.2.circlepath")
            switch services.updateRelaunch.phase {
            case .waitingForOperations: Text("Update ready. File operations will finish before Commander4Mac restarts.")
            case .savingWorkspace: Text("Saving your workspace before installing the update…")
            case .saveFailed:
                Text("Your workspace could not be saved. Commander4Mac will stay open.")
                Button("Retry") { services.updateRelaunch.retryStateSave() }
            case .installing: Text("Restarting to install the update…")
            case .idle: EmptyView()
            }
            Spacer()
        }.font(.callout).padding(10).background(.bar)
    }
}
