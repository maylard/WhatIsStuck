import Foundation

/// Actor-based service for running lsof to find which processes have files open
actor LsofService {

    // MARK: - Error Types

    enum LsofError: Error, LocalizedError {
        case lsofNotFound
        case executionFailed(String)
        case parseError(String)
        case noOutput

        var errorDescription: String? {
            switch self {
            case .lsofNotFound:
                return "lsof command not found at /usr/sbin/lsof"
            case .executionFailed(let message):
                return "Failed to execute lsof: \(message)"
            case .parseError(let message):
                return "Failed to parse lsof output: \(message)"
            case .noOutput:
                return "No output received from lsof"
            }
        }
    }

    // MARK: - Public Methods

    /// Finds all open files in the specified cloud provider sync directories
    /// - Parameter providers: Cloud providers to check (defaults to all)
    /// - Returns: Dictionary mapping file paths to the ProcessInfo that has them open
    func findOpenFiles(for providers: [CloudProvider] = CloudProvider.allCases) async throws -> [String: ProcessInfo] {
        // Collect all sync paths from the specified providers
        let syncPaths = providers.flatMap { $0.syncPaths }

        guard !syncPaths.isEmpty else {
            return [:]
        }

        // Run lsof to get all open files
        let lsofOutput = try await runLsof()

        // Parse the output
        let allOpenFiles = try parseLsofOutput(lsofOutput)

        // Filter to only include files in cloud sync directories
        return filterBySyncPaths(allOpenFiles, syncPaths: syncPaths)
    }

    /// Finds which process (if any) has a specific file open
    /// - Parameter filePath: The absolute path to the file
    /// - Returns: ProcessInfo if the file is open, nil otherwise
    func findProcessUsingFile(_ filePath: String) async throws -> ProcessInfo? {
        let lsofOutput = try await runLsof(for: filePath)
        let openFiles = try parseLsofOutput(lsofOutput)
        return openFiles[filePath]
    }

    // MARK: - Private Methods

    /// Runs lsof with parseable output format
    private func runLsof(for specificPath: String? = nil) async throws -> String {
        let lsofPath = "/usr/sbin/lsof"

        // Verify lsof exists
        guard FileManager.default.fileExists(atPath: lsofPath) else {
            throw LsofError.lsofNotFound
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: lsofPath)

        // -F pcn: Field output format
        //   p = PID
        //   c = command name
        //   n = file name/path
        // +c 0: Don't truncate command names
        var arguments = ["-F", "pcn", "+c", "0"]

        // If checking a specific path, add it
        if let path = specificPath {
            arguments.append(path)
        }

        process.arguments = arguments

        // Set up pipes for stdout and stderr
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        do {
            try process.run()
            process.waitUntilExit()

            // Read output
            let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
            let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()

            // lsof returns exit code 1 when no files are found, which is not an error for us
            if process.terminationStatus != 0 && process.terminationStatus != 1 {
                let errorMessage = String(data: errorData, encoding: .utf8) ?? "Unknown error"
                throw LsofError.executionFailed(errorMessage)
            }

            guard let output = String(data: outputData, encoding: .utf8) else {
                throw LsofError.noOutput
            }

            return output

        } catch let error as LsofError {
            throw error
        } catch {
            throw LsofError.executionFailed(error.localizedDescription)
        }
    }

    /// Parses lsof field output format
    /// Format: Lines starting with p=PID, c=command, n=name
    private func parseLsofOutput(_ output: String) throws -> [String: ProcessInfo] {
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
                // Process ID
                currentPID = Int32(value)

            case "c":
                // Command name
                currentCommand = value

            case "n":
                // File name/path
                guard let pid = currentPID,
                      let command = currentCommand,
                      !value.isEmpty else {
                    continue
                }

                // Only include regular files (skip pipes, sockets, etc.)
                // Regular files typically start with /
                guard value.hasPrefix("/") else {
                    continue
                }

                // Skip special files and system locations
                if isSystemOrSpecialFile(value) {
                    continue
                }

                // Create ProcessInfo
                let processInfo = ProcessInfo(
                    pid: pid,
                    name: command,
                    command: command
                )

                // Store the mapping (keep first process if multiple have the same file open)
                if result[value] == nil {
                    result[value] = processInfo
                }

            default:
                // Ignore other field types
                continue
            }
        }

        return result
    }

    /// Filters the open files dictionary to only include files in sync paths
    private func filterBySyncPaths(_ openFiles: [String: ProcessInfo], syncPaths: [String]) -> [String: ProcessInfo] {
        return openFiles.filter { filePath, _ in
            syncPaths.contains { syncPath in
                filePath.hasPrefix(syncPath)
            }
        }
    }

    /// Checks if a file path is a system or special file that should be ignored
    private func isSystemOrSpecialFile(_ path: String) -> Bool {
        // Skip device files
        if path.hasPrefix("/dev/") {
            return true
        }

        // Skip system directories
        let systemPrefixes = [
            "/System/",
            "/private/var/",
            "/var/",
            "/tmp/",
            "/usr/",
            "/bin/",
            "/sbin/"
        ]

        for prefix in systemPrefixes {
            if path.hasPrefix(prefix) {
                return true
            }
        }

        // Skip pipes and sockets (they don't start with / anyway, but double-check)
        if path.contains("pipe:") || path.contains("socket:") {
            return true
        }

        return false
    }
}
