import SwiftUI
import AppKit
import CommanderCore

struct ActivityView: View {
    var services: AppServices
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Activity", systemImage: "arrow.left.arrow.right").fontWeight(.semibold)
                Spacer()
                Button("Clear Finished") { Task { await services.transferQueue.dismissFinished() } }.font(.caption)
            }
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    if let diagnostic = services.recoveryDiagnostic { Label(diagnostic, systemImage: "exclamationmark.triangle").textSelection(.enabled) }
                    if services.jobs.isEmpty && services.recoveryRecords.isEmpty { Text("No file operations yet").foregroundStyle(.secondary) }
                    ForEach(services.jobs.reversed()) { job in
                        VStack(alignment: .leading, spacing: 5) {
                            HStack {
                                Text("\(job.request.kind == .copy ? "Copy" : "Move") \(job.request.sources.count) item\(job.request.sources.count == 1 ? "" : "s")").fontWeight(.medium)
                                Text(stateLabel(job.state)).foregroundStyle(.secondary)
                                Spacer()
                                if !job.state.isTerminal {
                                    Button("Cancel") { Task { await services.transferQueue.cancel(jobID: job.id) } }.disabled(job.state == .cancelRequested)
                                }
                            }
                            Text(LocationPresentation.text(for: job.request.destinationDirectory.url, endpoint: endpoint(for: job.request.destinationDirectory))).lineLimit(1).truncationMode(.middle).foregroundStyle(.secondary)
                            if !job.state.isTerminal {
                                HStack {
                                    ProgressView().controlSize(.small)
                                    Text("\(ByteCountFormatter.string(fromByteCount: job.progress.bytesCopied, countStyle: .file)) copied · \(job.progress.completedItems) files finished")
                                }
                            }
                            ForEach(job.outcomes) { outcome in
                                HStack(alignment: .top) {
                                    Image(systemName: outcome.state == .completed ? "checkmark.circle" : "info.circle")
                                    VStack(alignment: .leading) {
                                        Text("\(outcome.source.url.lastPathComponent): \(outcome.state.rawValue)")
                                        if let detail = outcome.detail { Text(detail).foregroundStyle(.secondary).textSelection(.enabled) }
                                    }
                                    Spacer()
                                    if let destination = outcome.destination { locationButton("Reveal", url: destination.url, endpoint: endpoint(for: destination)) }
                                }
                            }
                        }.padding(9).background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 6))
                    }
                    ForEach(services.recoveryRecords, id: \.itemID) { record in
                        VStack(alignment: .leading, spacing: 5) {
                            Label("Interrupted operation requires review", systemImage: "exclamationmark.triangle")
                            Text(record.detail ?? "Review both locations before moving or removing any remaining files.")
                            if let endpoint = record.endpointSnapshot { Text(endpoint.label).foregroundStyle(.secondary).textSelection(.enabled) }
                            Text("Source: \(LocationPresentation.text(for: record.source.url, endpoint: record.endpointSnapshot))\nDestination: \(LocationPresentation.text(for: record.destination, endpoint: record.endpointSnapshot))").textSelection(.enabled)
                            if let staging = record.staging { Text("Recovery file: \(LocationPresentation.text(for: staging, endpoint: record.endpointSnapshot))").textSelection(.enabled) }
                            HStack {
                                Button("Keep Files and Dismiss") { services.keepRecoveryFiles(record) }
                                locationButton("Show Source", url: record.source.url, endpoint: record.endpointSnapshot)
                                locationButton("Show Destination", url: record.destination, endpoint: record.endpointSnapshot)
                                if let staging = record.staging { locationButton("Show Recovery File", url: staging, endpoint: record.endpointSnapshot) }
                            }
                        }.padding(9).background(.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
                    }
                }.font(.system(size: 11))
            }.frame(height: 90)
        }.padding(12).frame(minHeight: 70)
    }
    private func endpoint(for location: FileLocation) -> RemoteEndpointSnapshot? {
        services.connections.profiles.first { $0.id == location.profileID }.map { RemoteEndpointSnapshot(profile: $0) }
    }
    @ViewBuilder private func locationButton(_ localTitle: String, url: URL, endpoint: RemoteEndpointSnapshot?) -> some View {
        switch LocationPresentation.action(for: url, endpoint: endpoint) {
        case .revealLocal(let file): Button(localTitle) { NSWorkspace.shared.activateFileViewerSelecting([file]) }
        case .copyRemotePath(let path): Button("Copy Remote Path") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(path, forType: .string) }.help(path)
        }
    }
    private func stateLabel(_ state: JobState) -> String {
        switch state {
        case .queued: "Queued"
        case .planning: "Checking files"
        case .running: "Running"
        case .awaitingConflict: "Needs a decision"
        case .cancelRequested: "Stopping safely"
        case .completed: "Completed"
        case .failed: "Review results"
        case .canceled: "Canceled"
        }
    }
}
