import SwiftUI
import AppKit
import CommanderCore

struct ConnectionEditor: View {
    var controller: WorkspaceController
    @Environment(\.dismiss) private var dismiss
    @State private var profile: ConnectionProfile
    @State private var keyPath: String
    @State private var secret = ""
    @State private var remember = true
    @State private var busy = false
    @State private var submission = ConnectionSubmission()
    @State private var error: String?
    init(controller: WorkspaceController, profile: ConnectionProfile?, request: ConnectionOpenRequest? = nil) {
        self.controller = controller
        let initial = request?.credentialEntryProfile ?? profile ?? ConnectionProfile(username: NSUserName())
        _profile = State(initialValue: initial)
        _keyPath = State(initialValue: initial.keyReference?.displayURL.path ?? "")
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Server Connection", systemImage: "network").font(.title2).fontWeight(.semibold)
            Text("Open a secure file server in either pane.").foregroundStyle(.secondary)
            Form {
                Picker("Protocol", selection: $profile.protocolKind) {
                    Text("SFTP").tag(ConnectionProtocol.sftp)
                    Text("SMB").tag(ConnectionProtocol.smb)
                    Text("WebDAV").tag(ConnectionProtocol.webdav)
                }.accessibilityIdentifier("connection.protocol")
                TextField("Name", text: $profile.name).accessibilityIdentifier("connection.name")
                TextField("Server", text: $profile.host).accessibilityIdentifier("connection.host")
                TextField("Port", value: $profile.port, format: .number.grouping(.never)).accessibilityIdentifier("connection.port")
                if profile.protocolKind == .smb {
                    TextField("Share", text: $profile.share).accessibilityIdentifier("connection.share")
                    TextField("Domain (optional)", text: $profile.domain).accessibilityIdentifier("connection.domain")
                }
                if profile.protocolKind == .webdav {
                    TextField("Base collection", text: $profile.basePath).accessibilityIdentifier("connection.basePath")
                    Toggle("Use HTTPS", isOn: $profile.secure).accessibilityIdentifier("connection.https")
                    if !profile.secure { Text("HTTP is allowed only for numeric loopback servers.").font(.caption).foregroundStyle(.secondary) }
                }
                TextField("Username", text: $profile.username).disabled(profile.authentication == .guest).accessibilityIdentifier("connection.username")
                TextField("Start folder", text: $profile.initialPath).accessibilityIdentifier("connection.path")
                Picker("Authentication", selection: $profile.authentication) {
                    Text("Password").tag(SFTPAuthentication.password)
                    if profile.protocolKind == .sftp { Text("OpenSSH Ed25519 key").tag(SFTPAuthentication.ed25519Key) }
                    else { Text(profile.protocolKind == .webdav ? "Anonymous" : "Guest").tag(SFTPAuthentication.guest) }
                }.accessibilityIdentifier("connection.authentication")
                if profile.authentication == .ed25519Key {
                    HStack {
                        TextField("Private key", text: $keyPath).accessibilityIdentifier("connection.keyPath")
                        Button("Choose…") {
                            let panel = NSOpenPanel(); panel.canChooseDirectories = false; panel.canChooseFiles = true; panel.allowsMultipleSelection = false
                            panel.message = "Choose an OpenSSH Ed25519 private key."
                            if panel.runModal() == .OK, let url = panel.url { keyPath = url.path }
                        }
                    }
                }
                if profile.authentication != .guest {
                    SecureField(profile.authentication == .password ? "Password" : "Key passphrase", text: $secret)
                        .accessibilityIdentifier("connection.secret")
                    Toggle("Remember credential in Keychain", isOn: $remember)
                }
                Picker("Open in", selection: Binding(get: { profile.destination?.rawValue ?? "default" }, set: { profile.destination = OpenDestination(rawValue: $0) })) {
                    Text("App default").tag("default")
                    Text("Current pane").tag(OpenDestination.current.rawValue)
                    Text("Left pane").tag(OpenDestination.left.rawValue)
                    Text("Right pane").tag(OpenDestination.right.rawValue)
                }
            }.disabled(busy)
            Text("Leave the credential blank to use Keychain. Nothing connects automatically on launch.").font(.caption).foregroundStyle(.secondary)
            Text("Remote copies currently support individual files without preserving permissions, timestamps, or extended metadata. Folder transfers, remote moves, and remote Trash are not available yet.").font(.caption).foregroundStyle(.secondary)
            if let error { Text(error).font(.callout).foregroundStyle(.red).textSelection(.enabled).fixedSize(horizontal: false, vertical: true) }
            HStack {
                Button("Cancel") {
                    submission.cancel(); dismiss()
                }.keyboardShortcut(.cancelAction).accessibilityIdentifier("connection.cancel")
                Spacer()
                if busy { ProgressView().controlSize(.small) }
                Button("Save") { submit(connect: false) }.disabled(busy)
                Button("Connect") { submit(connect: true) }.keyboardShortcut(.defaultAction).disabled(busy)
                    .accessibilityIdentifier("connection.connect")
            }
        }.padding(24).frame(width: 510).interactiveDismissDisabled(busy)
            .onDisappear { submission.cancel() }
            .onChange(of: profile.secure) { _, secure in
                if profile.protocolKind == .webdav && (profile.port == 80 || profile.port == 443) { profile.port = secure ? 443 : 80 }
            }
            .onChange(of: profile.protocolKind) { _, kind in
                profile.port = kind.defaultPort; profile.authentication = .password; profile.keyReference = nil; profile.serverKey = nil
                profile.initialPath = "/"; profile.share = ""; profile.domain = ""; profile.basePath = "/"; profile.secure = true
                keyPath = ""; secret = ""
            }
    }
    private func submit(connect: Bool) {
        let pane = controller.workspace.activePane
        let defaultDestination = controller.services.preferences.defaultDestination
        let candidate = profile; let selectedKeyPath = keyPath; let capturedSecret = secret; let remember = remember
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
            case .success: secret = ""; dismiss()
            case .failure(let failure): if !(failure is CancellationError) { error = failure.localizedDescription }
            }
        })
    }
}
