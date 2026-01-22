import Foundation
import AppKit
import Combine

@MainActor
class MainViewModel: ObservableObject {

    // MARK: - Published Properties

    @Published var stuckFiles: [StuckFile] = []
    @Published var isScanning: Bool = false
    @Published var lastScanDate: Date?
    @Published var errorMessage: String?
    @Published var hasFullDiskAccess: Bool = false

    // MARK: - Services

    private let lsofService: LsofService
    private let iCloudService: ICloudService
    private let permissionService: PermissionService

    // MARK: - Private Properties

    private var cancellables = Set<AnyCancellable>()

    // MARK: - Initialization

    init(
        lsofService: LsofService = LsofService(),
        iCloudService: ICloudService = ICloudService(),
        permissionService: PermissionService? = nil
    ) {
        self.lsofService = lsofService
        self.iCloudService = iCloudService
        self.permissionService = permissionService ?? PermissionService()

        // Observe permission changes
        self.permissionService.$hasFullDiskAccess
            .assign(to: \.hasFullDiskAccess, on: self)
            .store(in: &cancellables)
    }

    // MARK: - Public Methods

    /// Performs a full scan to find stuck files
    func scan() async {
        // Don't allow concurrent scans
        guard !isScanning else { return }

        isScanning = true
        errorMessage = nil

        do {
            // Step 1: Find stuck files from iCloud
            let cloudFiles = try await iCloudService.findStuckFiles()

            // Step 2: Get all open files from lsof in cloud directories
            let openFilesMap = try await lsofService.findOpenFiles()

            // Step 3: Enrich iCloud files with lsof process information
            let enrichedFiles = enrichFilesWithProcessInfo(
                cloudFiles: cloudFiles,
                openFilesMap: openFilesMap
            )

            // Step 4: Update UI
            stuckFiles = enrichedFiles
            lastScanDate = Date()

            // Clear error if scan succeeded
            if !stuckFiles.isEmpty {
                errorMessage = nil
            } else {
                errorMessage = "No stuck files found. Your iCloud sync is working smoothly!"
            }

        } catch let error as LsofService.LsofError {
            handleScanError(error)
        } catch let error as ICloudService.ICloudError {
            handleScanError(error)
        } catch {
            errorMessage = "Scan failed: \(error.localizedDescription)"
        }

        isScanning = false
    }

    /// Opens Finder to reveal the specified file
    func revealInFinder(_ file: StuckFile) {
        let url = file.url

        // Check if file exists
        guard FileManager.default.fileExists(atPath: file.path) else {
            errorMessage = "File not found at: \(file.path)"
            return
        }

        // Reveal file in Finder
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    /// Attempts to quit the blocking process for a file
    func quitBlockingProcess(_ file: StuckFile) async {
        guard let process = file.blockingProcess else {
            errorMessage = "No blocking process found for this file"
            return
        }

        // Don't kill system processes
        guard process.pid > 0 else {
            errorMessage = "Cannot terminate system process: \(process.name)"
            return
        }

        // Special handling for bird (iCloud sync daemon)
        if process.name.contains("bird") || process.name.contains("cloudd") {
            errorMessage = "Cannot terminate iCloud sync daemon. Please restart iCloud Drive in System Settings instead."
            return
        }

        // Try to find the running application by PID
        let allApps = NSWorkspace.shared.runningApplications
        guard let runningApp = allApps.first(where: { $0.processIdentifier == process.pid }) else {
            errorMessage = "Process \(process.name) (PID: \(process.pid)) is not running"
            return
        }

        // Try graceful termination first
        let terminated = runningApp.terminate()

        if terminated {
            // Wait a moment and rescan
            try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
            await scan()
        } else {
            // Offer force quit option
            errorMessage = "Failed to quit \(process.displayName). Try force quitting from Activity Monitor."
        }
    }

    /// Force quits the blocking process (last resort)
    func forceQuitBlockingProcess(_ file: StuckFile) async {
        guard let process = file.blockingProcess else {
            errorMessage = "No blocking process found for this file"
            return
        }

        guard process.pid > 0 else {
            errorMessage = "Cannot terminate system process: \(process.name)"
            return
        }

        // Don't kill critical system processes
        if process.name.contains("bird") || process.name.contains("cloudd") {
            errorMessage = "Cannot force quit iCloud sync daemon"
            return
        }

        let allApps = NSWorkspace.shared.runningApplications
        guard let runningApp = allApps.first(where: { $0.processIdentifier == process.pid }) else {
            errorMessage = "Process not found"
            return
        }

        // Force terminate
        let terminated = runningApp.forceTerminate()

        if terminated {
            // Wait and rescan
            try? await Task.sleep(nanoseconds: 500_000_000)
            await scan()
        } else {
            errorMessage = "Failed to force quit \(process.displayName)"
        }
    }

    /// Checks and refreshes Full Disk Access permission status
    func checkPermissions() {
        permissionService.checkPermissions()
    }

    /// Opens System Settings to grant Full Disk Access
    func openSystemPreferences() {
        permissionService.openSystemPreferences()
    }

    /// Clears the current error message
    func clearError() {
        errorMessage = nil
    }

    /// Removes a file from the stuck files list (after manual resolution)
    func removeFile(_ file: StuckFile) {
        stuckFiles.removeAll { $0.id == file.id }
    }

    // MARK: - Private Methods

    /// Enriches cloud files with process information from lsof
    private func enrichFilesWithProcessInfo(
        cloudFiles: [StuckFile],
        openFilesMap: [String: ProcessInfo]
    ) -> [StuckFile] {
        return cloudFiles.map { file in
            // Check if lsof found a more specific process for this file
            if let lsofProcess = openFilesMap[file.path] {
                // Replace the blocking process with the more specific one from lsof
                return StuckFile(
                    path: file.path,
                    fileName: file.fileName,
                    size: file.size,
                    provider: file.provider,
                    blockingProcess: lsofProcess,
                    detectedAt: file.detectedAt,
                    syncState: file.syncState
                )
            }

            // If no lsof match, check for partial path matches
            // (handles cases where paths might be slightly different)
            for (openPath, process) in openFilesMap {
                if openPath.contains(file.fileName) || file.path.contains(openPath) {
                    return StuckFile(
                        path: file.path,
                        fileName: file.fileName,
                        size: file.size,
                        provider: file.provider,
                        blockingProcess: process,
                        detectedAt: file.detectedAt,
                        syncState: file.syncState
                    )
                }
            }

            // Return original file if no match found
            return file
        }
    }

    /// Handles specific error types from scanning
    private func handleScanError(_ error: Error) {
        switch error {
        case LsofService.LsofError.lsofNotFound:
            errorMessage = "lsof command not found. Please ensure you have command line tools installed."

        case LsofService.LsofError.executionFailed(let message):
            errorMessage = "Failed to scan for open files: \(message)"

        case ICloudService.ICloudError.databaseNotFound:
            errorMessage = "iCloud database not found. Is iCloud Drive enabled?"

        case ICloudService.ICloudError.permissionDenied:
            errorMessage = "Permission denied. Please grant Full Disk Access in System Settings."
            hasFullDiskAccess = false

        case ICloudService.ICloudError.databaseLocked:
            errorMessage = "iCloud database is locked. Please try again in a moment."

        case ICloudService.ICloudError.queryFailed(let message):
            errorMessage = "Database query failed: \(message)"

        case ICloudService.ICloudError.brctlFailed(let message):
            errorMessage = "iCloud status check failed: \(message)"

        default:
            errorMessage = "Scan error: \(error.localizedDescription)"
        }
    }

    // MARK: - Computed Properties

    /// Returns stuck files grouped by sync state
    var filesByState: [StuckFile.SyncState: [StuckFile]] {
        Dictionary(grouping: stuckFiles) { $0.syncState }
    }

    /// Returns count of files in each state
    var stateCount: [StuckFile.SyncState: Int] {
        filesByState.mapValues { $0.count }
    }

    /// Returns total size of stuck files
    var totalStuckSize: Int64 {
        stuckFiles.reduce(0) { $0 + $1.size }
    }

    /// Returns formatted total size
    var totalStuckSizeFormatted: String {
        ByteCountFormatter.string(fromByteCount: totalStuckSize, countStyle: .file)
    }

    /// Returns true if there are any stuck files
    var hasStuckFiles: Bool {
        !stuckFiles.isEmpty
    }

    /// Returns true if a scan has been performed
    var hasScanResults: Bool {
        lastScanDate != nil
    }

    /// Returns formatted last scan date
    var lastScanDateFormatted: String {
        guard let date = lastScanDate else { return "Never" }

        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

// MARK: - Preview Helper

extension MainViewModel {
    /// Creates a preview instance with mock data
    static var preview: MainViewModel {
        let viewModel = MainViewModel()

        // Mock stuck files for preview
        viewModel.stuckFiles = [
            StuckFile(
                path: "/Users/test/Library/Mobile Documents/com~apple~CloudDocs/Important.pdf",
                fileName: "Important.pdf",
                size: 2_500_000,
                provider: .iCloud,
                blockingProcess: ProcessInfo(pid: 12345, name: "Preview", command: "Preview.app"),
                detectedAt: Date(),
                syncState: .uploading
            ),
            StuckFile(
                path: "/Users/test/Library/Mobile Documents/com~apple~CloudDocs/Document.docx",
                fileName: "Document.docx",
                size: 1_200_000,
                provider: .iCloud,
                blockingProcess: ProcessInfo(pid: 54321, name: "Microsoft Word", command: "Microsoft Word.app"),
                detectedAt: Date().addingTimeInterval(-3600),
                syncState: .error
            ),
            StuckFile(
                path: "/Users/test/Library/Mobile Documents/com~apple~CloudDocs/Photo.jpg",
                fileName: "Photo.jpg",
                size: 5_000_000,
                provider: .iCloud,
                blockingProcess: nil,
                detectedAt: Date().addingTimeInterval(-7200),
                syncState: .pending
            )
        ]

        viewModel.lastScanDate = Date()
        viewModel.hasFullDiskAccess = true

        return viewModel
    }
}
