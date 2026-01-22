import Foundation
import AppKit
import SQLite3

@MainActor
class PermissionService: ObservableObject {
    @Published var hasFullDiskAccess: Bool = false
    @Published var hasCheckedOnce: Bool = false

    init() {
        checkPermissions()
    }

    func checkPermissions() {
        hasCheckedOnce = true

        // Most reliable test: try to actually open the CloudDocs database we need
        let dbPath = "\(NSHomeDirectory())/Library/Application Support/CloudDocs/session/db/client.db"

        // First check if file exists
        guard FileManager.default.fileExists(atPath: dbPath) else {
            // CloudDocs database doesn't exist - iCloud might not be set up
            // Try alternative paths
            hasFullDiskAccess = checkAlternativePaths()
            return
        }

        // Try to actually open the database (this is what we need for the app)
        var db: OpaquePointer?
        let result = sqlite3_open_v2(dbPath, &db, SQLITE_OPEN_READONLY, nil)

        if result == SQLITE_OK {
            sqlite3_close(db)
            hasFullDiskAccess = true
            return
        }

        sqlite3_close(db)

        // If database open failed, try file read test
        hasFullDiskAccess = checkAlternativePaths()
    }

    private func checkAlternativePaths() -> Bool {
        // Test other protected paths
        let testPaths = [
            "\(NSHomeDirectory())/Library/Mail",
            "\(NSHomeDirectory())/Library/Safari/History.db"
        ]

        for path in testPaths {
            // Try to actually read the file, not just check if readable
            if let _ = try? Data(contentsOf: URL(fileURLWithPath: path), options: .mappedIfSafe) {
                return true
            }

            // Try directory listing for directories
            if let _ = try? FileManager.default.contentsOfDirectory(atPath: path) {
                return true
            }
        }

        return false
    }

    func openSystemPreferences() {
        // Open System Settings > Privacy & Security > Full Disk Access
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
            NSWorkspace.shared.open(url)
        }
    }

    func refreshPermissionStatus() {
        checkPermissions()
    }
}
