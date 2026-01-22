import SwiftUI
import AppKit

struct FileRowView: View {
    let file: StuckFile
    let onRevealInFinder: () -> Void
    let onQuitProcess: () -> Void

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 12) {
            // File icon
            Image(nsImage: NSWorkspace.shared.icon(forFile: file.path))
                .resizable()
                .frame(width: 32, height: 32)

            // File info
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(file.fileName)
                        .font(.system(size: 13, weight: .medium))
                        .lineLimit(1)

                    // Cloud provider icon
                    Image(systemName: file.provider.icon)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }

                Text(file.path)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .lineLimit(1)

                HStack(spacing: 8) {
                    // File size
                    Text(file.fileSizeFormatted)
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)

                    // Sync state
                    HStack(spacing: 3) {
                        Circle()
                            .fill(syncStateColor)
                            .frame(width: 6, height: 6)
                        Text(file.syncState.rawValue)
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }

                    // Blocking process
                    if let process = file.blockingProcess {
                        HStack(spacing: 3) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 9))
                                .foregroundColor(.orange)
                            Text("Blocked by \(process.displayName)")
                                .font(.system(size: 10))
                                .foregroundColor(.orange)
                        }
                    }
                }
            }

            Spacer()

            // Action buttons (shown on hover)
            if isHovered {
                HStack(spacing: 8) {
                    Button(action: onRevealInFinder) {
                        Label("Reveal", systemImage: "arrow.forward.circle.fill")
                            .font(.system(size: 11))
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(.accentColor)

                    if file.blockingProcess != nil {
                        Button(action: onQuitProcess) {
                            Label("Quit Process", systemImage: "xmark.circle.fill")
                                .font(.system(size: 11))
                        }
                        .buttonStyle(.plain)
                        .foregroundColor(.red)
                    }
                }
                .padding(.horizontal, 8)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(isHovered ? Color(nsColor: .controlBackgroundColor) : Color.clear)
        .cornerRadius(6)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
    }

    private var syncStateColor: Color {
        switch file.syncState {
        case .uploading, .downloading:
            return .blue
        case .pending:
            return .orange
        case .error:
            return .red
        case .unknown:
            return .gray
        }
    }
}

#Preview {
    FileRowView(
        file: StuckFile(
            path: "/Users/test/Documents/test.pdf",
            fileName: "test.pdf",
            size: 1024000,
            provider: .iCloud,
            blockingProcess: ProcessInfo(
                pid: 1234,
                name: "Preview.app",
                command: "/Applications/Preview.app"
            ),
            detectedAt: Date(),
            syncState: .uploading
        ),
        onRevealInFinder: {},
        onQuitProcess: {}
    )
    .frame(width: 700)
    .padding()
}
