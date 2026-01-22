import Foundation

/// Actor-based service for running lsof to find which processes have files open
actor LsofService {

    // MARK: - Error Types

    enum LsofError: Error, LocalizedError {
        case lsofNotFound
        case executionFailed(String)
        case parseError(String)
        case timeout

        var errorDescription: String? {
            switch self {
            case .lsofNotFound:
                return "lsof command not found at /usr/sbin/lsof"
            case .executionFailed(let message):
                return "Failed to execute lsof: \(message)"
            case .parseError(let message):
                return "Failed to parse lsof output: \(message)"
            case .timeout:
                return "lsof timed out"
            }
        }
    }

    // MARK: - Public Methods

    /// Finds all open files in the cloud sync directories
    /// Returns a dictionary mapping file paths to the ProcessInfo that has them open
    func findOpenFiles() async throws -> [String: ProcessInfo] {
        let lsofPath = "/usr/sbin/lsof"

        guard FileManager.default.fileExists(atPath: lsofPath) else {
            throw LsofError.lsofNotFound
        }

        let home = FileManager.default.homeDirectoryForCurrentUser.path

        // Only scan cloud sync directories - much faster than scanning everything
        let cloudPaths = [
            "\(home)/Library/Mobile Documents"
        ]

        var allOpenFiles: [String: ProcessInfo] = [:]

        for cloudPath in cloudPaths {
            guard FileManager.default.fileExists(atPath: cloudPath) else {
                continue
            }

            // Run lsof with +D to recursively scan just this directory
            // Use timeout to prevent hanging
            if let openFiles = try? await runLsofOnDirectory(cloudPath) {
                allOpenFiles.merge(openFiles) { existing, _ in existing }
            }
        }

        return allOpenFiles
    }

    /// Finds which process has a specific file open
    func findProcessForFile(_ filePath: String) async -> ProcessInfo? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
        process.arguments = ["-F", "pcn", filePath]

        let outputPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = Pipe()

        do {
            try process.run()

            // Timeout after 5 seconds
            let timeoutTask = Task {
                try await Task.sleep(nanoseconds: 5_000_000_000)
                process.terminate()
            }

            process.waitUntilExit()
            timeoutTask.cancel()

            let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
            guard let output = String(data: outputData, encoding: .utf8) else {
                return nil
            }

            return parseFirstProcess(from: output)
        } catch {
            return nil
        }
    }

    // MARK: - Private Methods

    private func runLsofOnDirectory(_ dirPath: String) async throws -> [String: ProcessInfo] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
        // +D recursively scans directory, +c 0 doesn't truncate names
        process.arguments = ["-F", "pcn", "+c", "0", "+D", dirPath]

        let outputPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = Pipe()

        try process.run()

        // Create a task that will terminate the process after timeout
        let timeoutTask = Task {
            try await Task.sleep(nanoseconds: 30_000_000_000) // 30 second timeout
            if process.isRunning {
                process.terminate()
            }
        }

        process.waitUntilExit()
        timeoutTask.cancel()

        if process.terminationStatus != 0 && process.terminationStatus != 1 {
            // lsof returns 1 when no files found, which is OK
            throw LsofError.executionFailed("Exit code: \(process.terminationStatus)")
        }

        let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
        guard let output = String(data: outputData, encoding: .utf8) else {
            return [:]
        }

        return parseLsofOutput(output)
    }

    private func parseLsofOutput(_ output: String) -> [String: ProcessInfo] {
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
                      value.hasPrefix("/"),
                      !isSystemFile(value) else {
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

    private func parseFirstProcess(from output: String) -> ProcessInfo? {
        let lines = output.components(separatedBy: .newlines)
        var pid: Int32?
        var command: String?

        for line in lines {
            guard !line.isEmpty else { continue }
            if line.hasPrefix("p"), let p = Int32(String(line.dropFirst())) {
                pid = p
            } else if line.hasPrefix("c") {
                command = String(line.dropFirst())
            }
        }

        if let pid = pid, let command = command {
            return ProcessInfo(pid: pid, name: command, command: command)
        }
        return nil
    }

    private func isSystemFile(_ path: String) -> Bool {
        let systemPrefixes = ["/dev/", "/System/", "/private/var/", "/var/", "/tmp/", "/usr/", "/bin/", "/sbin/"]
        return systemPrefixes.contains { path.hasPrefix($0) }
    }
}
