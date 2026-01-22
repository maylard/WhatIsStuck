import Foundation
import SQLite3

actor ICloudService {
    private let dbPath: String
    private let fileManager = FileManager.default

    // System processes that manage iCloud/files - these are NOT blockers
    private let systemProcesses = [
        "fileproviderd",    // File Provider daemon
        "FPCKService",      // File Provider Content Kit Service
        "bird",             // iCloud sync daemon
        "cloudd",           // iCloud daemon
        "brctl",            // iCloud control tool
        "fseventsd",        // File system events daemon
        "mds",              // Metadata server (Spotlight)
        "mds_stores",       // Metadata stores
        "mdworker",         // Spotlight metadata workers
        "Spotlight",        // Spotlight indexing
        "suggestd",         // Suggestions daemon
        "quicklookd",       // QuickLook daemon
        "Finder",           // Finder (normal file browsing)
        "com.apple"         // Any Apple system service
    ]

    // System files that should be ignored
    private let ignoredFiles = [
        ".DS_Store",        // macOS folder metadata
        ".localized",       // Localization file
        ".Spotlight-V100",  // Spotlight index
        ".fseventsd"        // File system events
    ]

    enum ICloudError: Error {
        case databaseNotFound
        case databaseLocked
        case queryFailed(String)
        case permissionDenied
        case brctlFailed(String)
    }

    init() {
        let home = fileManager.homeDirectoryForCurrentUser.path
        self.dbPath = "\(home)/Library/Application Support/CloudDocs/session/db/client.db"
    }

    // MARK: - Public Interface

    /// Find files that are pending sync in iCloud
    func findPendingFiles() async throws -> [StuckFile] {
        do {
            return try queryCloudDocsDatabase()
        } catch {
            print("Database query failed: \(error)")
            return []
        }
    }

    /// Find USER processes (not system) blocking files in cloud folders
    func findBlockingProcesses() async throws -> [String: ProcessInfo] {
        let home = fileManager.homeDirectoryForCurrentUser.path

        // iCloud syncs multiple locations:
        // 1. ~/Library/Mobile Documents/ - Main iCloud Drive (includes app folders like Pages, Numbers, etc.)
        // 2. ~/Desktop/ - if Desktop & Documents sync is enabled
        // 3. ~/Documents/ - if Desktop & Documents sync is enabled
        // 4. ~/Downloads/ - if synced to iCloud
        let cloudPaths = [
            "\(home)/Library/Mobile Documents",
            "\(home)/Desktop",
            "\(home)/Documents",
            "\(home)/Downloads"
        ]

        var allBlockingProcesses: [String: ProcessInfo] = [:]

        for cloudPath in cloudPaths {
            guard fileManager.fileExists(atPath: cloudPath) else {
                continue
            }

            // Run lsof on each cloud-synced directory
            // The +D flag recursively scans all subdirectories
            if let output = try? await runLsof(on: cloudPath) {
                let processes = parseAndFilterLsof(output)
                allBlockingProcesses.merge(processes) { existing, _ in existing }
            }
        }

        return allBlockingProcesses
    }

    // MARK: - Private: Database Queries

    private func queryCloudDocsDatabase() throws -> [StuckFile] {
        guard fileManager.fileExists(atPath: dbPath) else {
            throw ICloudError.databaseNotFound
        }

        var db: OpaquePointer?
        var stuckFiles: [StuckFile] = []

        let flags = SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX
        let result = sqlite3_open_v2(dbPath, &db, flags, nil)

        guard result == SQLITE_OK else {
            sqlite3_close(db)
            if result == SQLITE_BUSY || result == SQLITE_LOCKED {
                throw ICloudError.databaseLocked
            }
            throw ICloudError.queryFailed("Failed to open database")
        }

        defer { sqlite3_close(db) }

        // Query for pending uploads
        let query = """
        SELECT
            ci.item_filename,
            cu.transfer_size,
            cu.throttle_state
        FROM client_uploads cu
        INNER JOIN client_items ci ON cu.throttle_id = ci.rowid
        ORDER BY cu.transfer_size DESC
        LIMIT 100
        """

        var statement: OpaquePointer?
        if sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK {
            while sqlite3_step(statement) == SQLITE_ROW {
                if let file = extractFile(statement, isUpload: true) {
                    stuckFiles.append(file)
                }
            }
            sqlite3_finalize(statement)
        }

        return stuckFiles
    }

    private func extractFile(_ statement: OpaquePointer?, isUpload: Bool) -> StuckFile? {
        guard let statement = statement else { return nil }

        var fileName = "Unknown"
        if let ptr = sqlite3_column_text(statement, 0) {
            fileName = String(cString: ptr)
        }

        let size = sqlite3_column_int64(statement, 1)
        let throttleState = sqlite3_column_int(statement, 2)

        let home = fileManager.homeDirectoryForCurrentUser.path
        let path = "\(home)/Library/Mobile Documents/com~apple~CloudDocs/\(fileName)"

        return StuckFile(
            path: path,
            fileName: fileName,
            size: size,
            provider: .iCloud,
            blockingProcess: nil, // Will be enriched later
            detectedAt: Date(),
            syncState: isUpload ? (throttleState == 1 ? .uploading : .pending) : .downloading
        )
    }

    // MARK: - Private: lsof for finding blocking processes

    private func runLsof(on directory: String) async throws -> String {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
        task.arguments = ["-F", "pcn", "+c", "0", "+D", directory]

        let outputPipe = Pipe()
        task.standardOutput = outputPipe
        task.standardError = Pipe()

        try task.run()

        // Timeout after 30 seconds
        let timeoutTask = Task {
            try await Task.sleep(nanoseconds: 30_000_000_000)
            if task.isRunning { task.terminate() }
        }

        task.waitUntilExit()
        timeoutTask.cancel()

        let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8) ?? ""
    }

    /// Parse lsof output and FILTER OUT system processes and system files
    private func parseAndFilterLsof(_ output: String) -> [String: ProcessInfo] {
        var result: [String: ProcessInfo] = [:]
        let lines = output.components(separatedBy: .newlines)

        var currentPID: Int32?
        var currentCommand: String?

        for line in lines {
            guard !line.isEmpty else { continue }

            let firstChar = line.first
            let value = String(line.dropFirst())

            switch firstChar {
            case "p":
                currentPID = Int32(value)
            case "c":
                currentCommand = value
            case "n":
                guard let pid = currentPID,
                      let command = currentCommand,
                      value.hasPrefix("/") else {
                    continue
                }

                // FILTER OUT system processes - they are NOT blockers
                if isSystemProcess(command) {
                    continue
                }

                // FILTER OUT system files
                let fileName = URL(fileURLWithPath: value).lastPathComponent
                if isSystemFile(fileName) {
                    continue
                }

                // Skip directories (we want files)
                var isDir: ObjCBool = false
                if fileManager.fileExists(atPath: value, isDirectory: &isDir), isDir.boolValue {
                    continue
                }

                let processInfo = ProcessInfo(pid: pid, name: command, command: command)
                if result[value] == nil {
                    result[value] = processInfo
                }
            default:
                continue
            }
        }

        return result
    }

    private func isSystemProcess(_ name: String) -> Bool {
        let lowered = name.lowercased()
        return systemProcesses.contains { lowered.contains($0.lowercased()) }
    }

    private func isSystemFile(_ fileName: String) -> Bool {
        return ignoredFiles.contains { fileName == $0 || fileName.hasPrefix($0) }
    }
}
