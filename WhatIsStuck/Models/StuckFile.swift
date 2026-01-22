import Foundation

struct StuckFile: Identifiable, Hashable {
    let id = UUID()
    let path: String
    let fileName: String
    let size: Int64
    let provider: CloudProvider
    let blockingProcess: ProcessInfo?
    let detectedAt: Date
    let syncState: SyncState

    var fileSizeFormatted: String {
        ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }

    var url: URL {
        URL(fileURLWithPath: path)
    }

    enum SyncState: String {
        case uploading = "Uploading"
        case downloading = "Downloading"
        case pending = "Pending"
        case error = "Error"
        case unknown = "Unknown"
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(path)
    }

    static func == (lhs: StuckFile, rhs: StuckFile) -> Bool {
        lhs.path == rhs.path
    }
}
