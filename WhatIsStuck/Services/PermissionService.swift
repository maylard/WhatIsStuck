import Foundation
import AppKit

@MainActor
class PermissionService: ObservableObject {
    @Published var hasFullDiskAccess: Bool = false

    init() {
        checkPermissions()
    }

    func checkPermissions() {
        // Test access to a protected directory that requires Full Disk Access
        let testPaths = [
            "\(NSHomeDirectory())/Library/Application Support/CloudDocs/session/db/client.db",
            "\(NSHomeDirectory())/Library/Mail",
            "/Library/Application Support/com.apple.TCC/TCC.db"
        ]

        for path in testPaths {
            if FileManager.default.isReadableFile(atPath: path) {
                hasFullDiskAccess = true
                return
            }
        }

        // Alternative: try to actually read from CloudDocs
        let cloudDocsPath = "\(NSHomeDirectory())/Library/Application Support/CloudDocs/"
        if FileManager.default.fileExists(atPath: cloudDocsPath) {
            do {
                _ = try FileManager.default.contentsOfDirectory(atPath: cloudDocsPath)
                hasFullDiskAccess = true
                return
            } catch {
                hasFullDiskAccess = false
            }
        }

        hasFullDiskAccess = false
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
