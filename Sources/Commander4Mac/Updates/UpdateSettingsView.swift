// Commander4Mac original code: GPL-3.0-only with the Citadel linking permission.
// See LICENSE and LICENSE-EXCEPTION at the repository root.

import SwiftUI

struct UpdateSettingsView: View {
    @Bindable private var updater = UpdaterController.shared
    @Bindable private var services = AppServices.shared
    var body: some View {
        Form {
            LabeledContent("Installed version") {
                Text((Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "") +
                     " (" + (Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "") + ")")
            }
            if updater.isEligible {
                Toggle("Check for updates automatically", isOn: $updater.automaticallyChecks)
                Toggle("Download updates automatically", isOn: $updater.automaticallyDownloads).disabled(!updater.automaticallyChecks)
                Text("Updates come from Commander4Mac’s GitHub Releases and are verified before installation. A restart waits for file operations to finish and saves your workspace.")
                    .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                Button("Check for Updates…") { updater.checkForUpdates() }.disabled(!updater.canCheckForUpdates)
                    .accessibilityIdentifier("updates.check")
                switch services.updateRelaunch.phase {
                case .waitingForOperations: Label("Update ready. Waiting for file operations to finish…", systemImage: "hourglass")
                case .savingWorkspace: Label("Saving your workspace before restarting…", systemImage: "arrow.down.doc")
                case .saveFailed:
                    Text(services.startupDiagnostic ?? "The workspace could not be saved. Commander4Mac will stay open.").foregroundStyle(.red)
                    Button("Retry Saving and Install") { services.updateRelaunch.retryStateSave() }
                case .installing: Text("Restarting to install the update…")
                case .idle: EmptyView()
                }
            } else {
                Text("Automatic updates are available in the release app installed in Applications. Development and UI test builds use a separate identity.")
                    .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                Link("Download Commander4Mac", destination: URL(string: "https://github.com/AlanHuang99/Commander4Mac/releases/latest")!)
            }
        }.padding(24)
    }
}
