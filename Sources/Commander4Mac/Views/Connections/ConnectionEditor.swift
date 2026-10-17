// Commander4Mac original code: GPL-3.0-only with the Citadel linking permission.
// See LICENSE and LICENSE-EXCEPTION at the repository root.

import SwiftUI
import AppKit
import CommanderCore

struct ConnectionEditor: View {
    var controller: WorkspaceController
    @Environment(\.dismiss) private var dismiss
    @State private var draft: ConnectionDraft
    @State private var busy = false
    @State private var submission = ConnectionSubmission()
    @State private var error: String?
    init(controller: WorkspaceController, profile: ConnectionProfile?, request: ConnectionOpenRequest? = nil) {
        self.controller = controller
        let initial = request?.credentialEntryProfile ?? profile ?? ConnectionProfile(username: NSUserName())
        _draft = State(initialValue: ConnectionDraft(profile: initial))
    }
    private var profile: ConnectionProfile {
        get { draft.profile }
        nonmutating set { draft.profile = newValue }
    }
    private var savedSelection: Binding<UUID?> {
        Binding(get: { controller.services.connections.profiles.contains(where: { $0.id == profile.id }) ? profile.id : nil },
                set: { id in
                    let selected = controller.services.connections.profiles.first { $0.id == id }
                    draft.select(selected ?? ConnectionProfile(username: NSUserName())); error = nil
                })
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Server Connection", systemImage: "network").font(.title2).fontWeight(.semibold)
            Text("Open a secure file server in either pane.").foregroundStyle(.secondary)
            HStack {
                Picker("Saved", selection: savedSelection) {
                    Text("New Connection").tag(UUID?.none)
                    ForEach(controller.services.connections.profiles) { saved in
                        Text(saved.name + " · " + saved.endpointSummary).tag(Optional(saved.id))
                    }
                }.accessibilityIdentifier("connection.saved")
                Button("New") { savedSelection.wrappedValue = nil }.accessibilityIdentifier("connection.new")
                if savedSelection.wrappedValue != nil {
                    Button(role: .destructive) { removeSaved() } label: { Image(systemName: "trash") }
                        .help("Remove Saved Connection").accessibilityLabel("Remove Saved Connection").accessibilityIdentifier("connection.remove")
                }
            }.disabled(busy)
            Text("Saved connections stay in the sidebar for quick access.").font(.caption).foregroundStyle(.secondary)
            Form {
                Picker("Protocol", selection: Binding(get: { profile.protocolKind }, set: { draft.setProtocol($0) })) {
                    Text("SFTP").tag(ConnectionProtocol.sftp)
                    Text("SMB").tag(ConnectionProtocol.smb)
                    Text("WebDAV").tag(ConnectionProtocol.webdav)
                }.accessibilityIdentifier("connection.protocol")
                TextField("Name", text: $draft.profile.name).accessibilityIdentifier("connection.name")
                TextField("Server", text: $draft.profile.host).accessibilityIdentifier("connection.host")
                TextField("Port", value: $draft.profile.port, format: .number.grouping(.never)).accessibilityIdentifier("connection.port")
                if profile.protocolKind == .smb {
                    TextField("Share", text: $draft.profile.share).accessibilityIdentifier("connection.share")
                    TextField("Domain (optional)", text: $draft.profile.domain).accessibilityIdentifier("connection.domain")
                }
                if profile.protocolKind == .webdav {
                    TextField("Base collection", text: $draft.profile.basePath).accessibilityIdentifier("connection.basePath")
                    Toggle("Use HTTPS", isOn: Binding(get: { profile.secure }, set: { draft.setSecure($0) })).accessibilityIdentifier("connection.https")
                    if !profile.secure { Text("HTTP is allowed only for numeric loopback servers.").font(.caption).foregroundStyle(.secondary) }
                }
                TextField("Username", text: $draft.profile.username).disabled(profile.authentication == .guest).accessibilityIdentifier("connection.username")
                TextField("Start folder", text: $draft.profile.initialPath).accessibilityIdentifier("connection.path")
                Picker("Authentication", selection: Binding(get: { profile.authentication }, set: { draft.setAuthentication($0) })) {
                    Text("Password").tag(SFTPAuthentication.password)
                    if profile.protocolKind == .sftp { Text("OpenSSH Ed25519 key").tag(SFTPAuthentication.ed25519Key) }
                    else { Text(profile.protocolKind == .webdav ? "Anonymous" : "Guest").tag(SFTPAuthentication.guest) }
                }.accessibilityIdentifier("connection.authentication")
                if profile.authentication == .ed25519Key {
                    HStack {
                        TextField("Private key", text: $draft.keyPath).accessibilityIdentifier("connection.keyPath")
                        Button("Choose…") {
                            let panel = NSOpenPanel(); panel.canChooseDirectories = false; panel.canChooseFiles = true; panel.allowsMultipleSelection = false
                            panel.message = "Choose an OpenSSH Ed25519 private key."
                            if panel.runModal() == .OK, let url = panel.url { draft.keyPath = url.path }
                        }
                    }
                }
                if profile.authentication != .guest {
                    SecureField(profile.authentication == .password ? "Password" : "Key passphrase", text: $draft.secret)
                        .accessibilityIdentifier("connection.secret")
                    Toggle("Remember credential in Keychain", isOn: $draft.remember)
                }
                Picker("Open in", selection: Binding(get: { profile.destination?.rawValue ?? "default" }, set: { profile.destination = OpenDestination(rawValue: $0) })) {
                    Text("App default").tag("default")
                    Text("Current pane").tag(OpenDestination.current.rawValue)
                    Text("Left pane").tag(OpenDestination.left.rawValue)
                    Text("Right pane").tag(OpenDestination.right.rawValue)
                }
            }.disabled(busy)
            Text("Leave the credential blank to use Keychain. Nothing connects automatically on launch.").font(.caption).foregroundStyle(.secondary)
            Text("Copy regular files and folders between a local pane and a server. Contents and folder structure are copied; permissions, dates, and extended metadata are not preserved. Remote moves and Trash are unavailable.").font(.caption).foregroundStyle(.secondary)
            if let error { Text(error).font(.callout).foregroundStyle(.red).textSelection(.enabled).fixedSize(horizontal: false, vertical: true) }
            HStack {
                Button("Cancel") {
                    submission.cancel(); dismiss()
                }.keyboardShortcut(.cancelAction).accessibilityIdentifier("connection.cancel")
                Spacer()
                if busy { ProgressView().controlSize(.small) }
                Button("Save Connection") { submit(connect: false) }.disabled(busy).accessibilityIdentifier("connection.save")
                Button("Save and Connect") { submit(connect: true) }.keyboardShortcut(.defaultAction).disabled(busy)
                    .accessibilityIdentifier("connection.connect")
            }
        }.padding(24).frame(width: 510).interactiveDismissDisabled(busy)
            .onDisappear { submission.cancel() }
    }
    private func removeSaved() {
        let removed = profile; busy = true; error = nil
        Task {
            do { try await controller.services.connections.remove(removed); draft.select(ConnectionProfile(username: NSUserName())) }
            catch { self.error = error.localizedDescription }
            busy = false
        }
    }
    private func submit(connect: Bool) {
        let pane = controller.workspace.activePane
        let defaultDestination = controller.services.preferences.defaultDestination
        let candidate = profile; let selectedKeyPath = draft.keyPath; let capturedSecret = draft.secret; let remember = draft.remember
        busy = true; error = nil
        submission.start(prepare: {
            var candidate = candidate
            if candidate.authentication == .ed25519Key {
                guard !selectedKeyPath.isEmpty else { throw FileOperationError.message("Choose an OpenSSH Ed25519 private key.") }
                if candidate.keyReference?.displayURL.path != selectedKeyPath {
                    candidate.keyReference = try await BlockingFileWorker.run {
                        try LocationResolver().reference(for: .local(URL(fileURLWithPath: (selectedKeyPath as NSString).expandingTildeInPath)))
                    }
                }
            }
            try Task.checkCancellation()
            let saved = try await controller.services.connections.save(candidate, secret: capturedSecret.isEmpty ? nil : capturedSecret, remember: remember)
            try Task.checkCancellation()
            // Keep the committed identity even when credential entry must retry.
            profile = saved
            var credential = capturedSecret
            if connect, credential.isEmpty {
                if let stored = try await controller.services.connections.secret(for: saved) { credential = stored }
                else if saved.authentication == .password { throw FileOperationError.message("Enter a password. There is no saved credential for this server and username.") }
            }
            return (saved, credential)
        }, perform: { saved, credential in
            profile = saved
            if connect {
                let request = try ConnectionOpenRequest(profile: saved, activePane: pane, defaultDestination: defaultDestination)
                try await controller.establishConnection(request, secret: credential, onProfileChange: { profile = $0 })
            }
        }, completion: { result in
            busy = false
            switch result {
            case .success: draft.secret = ""; dismiss()
            case .failure(let failure): if !(failure is CancellationError) { error = failure.localizedDescription }
            }
        })
    }
}
