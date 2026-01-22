import Foundation
import SQLite3

actor ICloudService {
    private let dbPath: String
    private let fileManager = FileManager.default

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

    func findStuckFiles() async throws -> [StuckFile] {
        var stuckFiles: [StuckFile] = []

        // Try querying the SQLite database first
        do {
            stuckFiles = try await queryCloudDocsDatabase()
        } catch {
            print("Database query failed: \(error). Falling back to brctl...")
            // Fallback to brctl if database query fails
            stuckFiles = try await queryBrctl()
        }

        return stuckFiles
    }

    // MARK: - SQLite Database Queries

    private func queryCloudDocsDatabase() async throws -> [StuckFile] {
        // Check if database exists and is accessible
        guard fileManager.fileExists(atPath: dbPath) else {
            throw ICloudError.databaseNotFound
        }

        guard fileManager.isReadableFile(atPath: dbPath) else {
            throw ICloudError.permissionDenied
        }

        var db: OpaquePointer?
        var stuckFiles: [StuckFile] = []

        // Open database with read-only flag to avoid locking issues
        let flags = SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX
        let result = sqlite3_open_v2(dbPath, &db, flags, nil)

        guard result == SQLITE_OK else {
            let errorMessage = String(cString: sqlite3_errmsg(db))
            sqlite3_close(db)

            if result == SQLITE_BUSY || result == SQLITE_LOCKED {
                throw ICloudError.databaseLocked
            }
            throw ICloudError.queryFailed("Failed to open database: \(errorMessage)")
        }

        defer {
            sqlite3_close(db)
        }

        // Query to find pending uploads
        // Join client_uploads with client_items to get file information
        let query = """
        SELECT
            ci.item_filename,
            cu.transfer_size,
            cu.throttle_state,
            ci.item_localname,
            ci.item_doc_id,
            ci.item_type
        FROM client_uploads cu
        INNER JOIN client_items ci ON cu.throttle_id = ci.rowid
        WHERE cu.throttle_state IS NOT NULL
        ORDER BY cu.transfer_size DESC
        """

        var statement: OpaquePointer?

        guard sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK else {
            let errorMessage = String(cString: sqlite3_errmsg(db))
            throw ICloudError.queryFailed("Failed to prepare statement: \(errorMessage)")
        }

        defer {
            sqlite3_finalize(statement)
        }

        // Execute query and collect results
        while sqlite3_step(statement) == SQLITE_ROW {
            if let file = extractStuckFileFromRow(statement) {
                stuckFiles.append(file)
            }
        }

        // Also check for items in error state
        let errorFiles = try await queryErrorFiles(db: db)
        stuckFiles.append(contentsOf: errorFiles)

        return stuckFiles
    }

    private func extractStuckFileFromRow(_ statement: OpaquePointer?) -> StuckFile? {
        guard let statement = statement else { return nil }

        // Extract filename
        var fileName = "Unknown"
        if let filenamePtr = sqlite3_column_text(statement, 0) {
            fileName = String(cString: filenamePtr)
        }

        // Extract transfer size
        let transferSize = sqlite3_column_int64(statement, 1)

        // Extract throttle state
        var throttleState: Int32 = 0
        if sqlite3_column_type(statement, 2) != SQLITE_NULL {
            throttleState = sqlite3_column_int(statement, 2)
        }

        // Extract local name (path component)
        var localName: String?
        if let localNamePtr = sqlite3_column_text(statement, 3) {
            localName = String(cString: localNamePtr)
        }

        // Construct full path
        let path = constructFilePath(fileName: fileName, localName: localName)

        // Determine sync state based on throttle_state
        let syncState = determineSyncState(throttleState: throttleState)

        // Try to find blocking process (bird daemon is the iCloud sync daemon)
        let blockingProcess = findBlockingProcess(filePath: path)

        return StuckFile(
            path: path,
            fileName: fileName,
            size: transferSize,
            provider: .iCloud,
            blockingProcess: blockingProcess,
            detectedAt: Date(),
            syncState: syncState
        )
    }

    private func queryErrorFiles(db: OpaquePointer?) async throws -> [StuckFile] {
        var errorFiles: [StuckFile] = []

        // Query for items with errors or stuck in various states
        let errorQuery = """
        SELECT
            item_filename,
            item_size,
            item_state,
            item_localname
        FROM client_items
        WHERE item_state IN (1, 2, 3)
        AND (item_upload_error IS NOT NULL OR item_download_error IS NOT NULL)
        LIMIT 100
        """

        var statement: OpaquePointer?

        guard sqlite3_prepare_v2(db, errorQuery, -1, &statement, nil) == SQLITE_OK else {
            return errorFiles
        }

        defer {
            sqlite3_finalize(statement)
        }

        while sqlite3_step(statement) == SQLITE_ROW {
            var fileName = "Unknown"
            if let filenamePtr = sqlite3_column_text(statement, 0) {
                fileName = String(cString: filenamePtr)
            }

            let size = sqlite3_column_int64(statement, 1)

            var localName: String?
            if let localNamePtr = sqlite3_column_text(statement, 3) {
                localName = String(cString: localNamePtr)
            }

            let path = constructFilePath(fileName: fileName, localName: localName)
            let blockingProcess = findBlockingProcess(filePath: path)

            let stuckFile = StuckFile(
                path: path,
                fileName: fileName,
                size: size,
                provider: .iCloud,
                blockingProcess: blockingProcess,
                detectedAt: Date(),
                syncState: .error
            )

            errorFiles.append(stuckFile)
        }

        return errorFiles
    }

    // MARK: - Path Construction

    private func constructFilePath(fileName: String, localName: String?) -> String {
        let home = fileManager.homeDirectoryForCurrentUser.path

        // Try to construct the full path
        if let localName = localName, !localName.isEmpty {
            // localName might contain path components
            let iCloudPath = "\(home)/Library/Mobile Documents"
            return "\(iCloudPath)/\(localName)"
        }

        // Fallback: search common iCloud directories
        let iCloudPaths = [
            "\(home)/Library/Mobile Documents/com~apple~CloudDocs",
            "\(home)/Library/Mobile Documents"
        ]

        for basePath in iCloudPaths {
            if let foundPath = findFileInDirectory(basePath: basePath, fileName: fileName) {
                return foundPath
            }
        }

        // If we can't find it, return a best-guess path
        return "\(iCloudPaths[0])/\(fileName)"
    }

    private func findFileInDirectory(basePath: String, fileName: String) -> String? {
        let enumerator = fileManager.enumerator(atPath: basePath)

        while let element = enumerator?.nextObject() as? String {
            if element.hasSuffix(fileName) || element.contains(fileName) {
                return "\(basePath)/\(element)"
            }
        }

        return nil
    }

    // MARK: - Sync State Determination

    private func determineSyncState(throttleState: Int32) -> StuckFile.SyncState {
        // Based on CloudDocs throttle states:
        // 0 or NULL: unknown/pending
        // 1: active upload
        // 2: throttled/paused
        // 3: error state
        switch throttleState {
        case 0:
            return .pending
        case 1:
            return .uploading
        case 2:
            return .pending
        case 3:
            return .error
        default:
            return .unknown
        }
    }

    // MARK: - Process Detection

    private func findBlockingProcess(filePath: String) -> ProcessInfo? {
        // Try to find if bird (iCloud sync daemon) is accessing this file
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
        task.arguments = ["-Fp", filePath]

        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = Pipe()

        do {
            try task.run()
            task.waitUntilExit()

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            guard let output = String(data: data, encoding: .utf8) else {
                return nil
            }

            // Parse lsof output to extract PID
            let lines = output.components(separatedBy: .newlines)
            for line in lines {
                if line.hasPrefix("p") {
                    let pidString = line.dropFirst()
                    if let pid = Int32(pidString) {
                        return getProcessInfo(pid: pid)
                    }
                }
            }
        } catch {
            // lsof failed, return default bird process
            return ProcessInfo(
                pid: -1,
                name: "bird",
                command: "iCloud Sync Daemon"
            )
        }

        return nil
    }

    private func getProcessInfo(pid: Int32) -> ProcessInfo {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/ps")
        task.arguments = ["-p", "\(pid)", "-o", "comm="]

        let pipe = Pipe()
        task.standardOutput = pipe

        do {
            try task.run()
            task.waitUntilExit()

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let name = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
               !name.isEmpty {
                return ProcessInfo(pid: pid, name: name, command: name)
            }
        } catch {
            // Fallback
        }

        return ProcessInfo(pid: pid, name: "Unknown Process", command: "")
    }

    // MARK: - brctl Fallback

    private func queryBrctl() async throws -> [StuckFile] {
        var stuckFiles: [StuckFile] = []

        // First, get overall sync status
        let syncStatus = try await runBrctlStatus()

        // If there are issues, try to get diagnostic info
        if syncStatus.contains("stuck") || syncStatus.contains("error") || syncStatus.contains("waiting") {
            stuckFiles = try await getBrctlDiagnostics()
        }

        return stuckFiles
    }

    private func runBrctlStatus() async throws -> String {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/brctl")
        task.arguments = ["status"]

        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = Pipe()

        do {
            try task.run()
            task.waitUntilExit()

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            guard let output = String(data: data, encoding: .utf8) else {
                throw ICloudError.brctlFailed("Failed to decode brctl output")
            }

            return output
        } catch {
            throw ICloudError.brctlFailed("brctl command failed: \(error.localizedDescription)")
        }
    }

    private func getBrctlDiagnostics() async throws -> [StuckFile] {
        var stuckFiles: [StuckFile] = []

        // Try to get diagnostic info with brctl diagnose
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/brctl")
        task.arguments = ["diagnose", "-t", "-d"]

        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = Pipe()

        do {
            try task.run()
            task.waitUntilExit()

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            guard let output = String(data: data, encoding: .utf8) else {
                return stuckFiles
            }

            // Parse brctl diagnose output for stuck files
            stuckFiles = parseBrctlDiagnostics(output)
        } catch {
            // brctl diagnose might not be available, that's okay
        }

        return stuckFiles
    }

    private func parseBrctlDiagnostics(_ output: String) -> [StuckFile] {
        var stuckFiles: [StuckFile] = []
        let lines = output.components(separatedBy: .newlines)

        for line in lines {
            // Look for lines indicating upload/download issues
            if line.contains("upload") || line.contains("download") || line.contains("pending") {
                // Try to extract file information
                // This is a best-effort parse as brctl output format may vary
                if let file = extractFileFromBrctlLine(line) {
                    stuckFiles.append(file)
                }
            }
        }

        return stuckFiles
    }

    private func extractFileFromBrctlLine(_ line: String) -> StuckFile? {
        // This is a simplified parser - brctl output format may vary
        // Looking for patterns like: "/path/to/file.txt: uploading (12345 bytes)"

        let components = line.components(separatedBy: ":")
        guard components.count >= 2 else { return nil }

        let path = components[0].trimmingCharacters(in: .whitespaces)
        guard fileManager.fileExists(atPath: path) else { return nil }

        let fileName = URL(fileURLWithPath: path).lastPathComponent

        // Try to get file size
        var size: Int64 = 0
        do {
            let attributes = try fileManager.attributesOfItem(atPath: path)
            size = (attributes[.size] as? NSNumber)?.int64Value ?? 0
        } catch {
            // Ignore error, use 0 size
        }

        // Determine sync state from line content
        let syncState: StuckFile.SyncState
        let lowerLine = line.lowercased()
        if lowerLine.contains("upload") {
            syncState = .uploading
        } else if lowerLine.contains("download") {
            syncState = .downloading
        } else if lowerLine.contains("error") {
            syncState = .error
        } else if lowerLine.contains("pending") {
            syncState = .pending
        } else {
            syncState = .unknown
        }

        return StuckFile(
            path: path,
            fileName: fileName,
            size: size,
            provider: .iCloud,
            blockingProcess: ProcessInfo(pid: -1, name: "bird", command: "iCloud Sync"),
            detectedAt: Date(),
            syncState: syncState
        )
    }

    // MARK: - Utility Methods

    func getSyncStatus() async throws -> String {
        // Get high-level sync status
        return try await runBrctlStatus()
    }

    func isICloudSyncEnabled() async -> Bool {
        // Check if iCloud Drive is enabled
        let ubiquityURL = fileManager.url(forUbiquityContainerIdentifier: nil)
        return ubiquityURL != nil
    }
}
