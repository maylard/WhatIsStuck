import Foundation

enum CloudProvider: String, CaseIterable, Identifiable {
    case iCloud = "iCloud"
    case oneDrive = "OneDrive"
    case googleDrive = "Google Drive"
    case dropbox = "Dropbox"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .iCloud: return "icloud"
        case .oneDrive: return "cloud"
        case .googleDrive: return "externaldrive"
        case .dropbox: return "shippingbox"
        }
    }

    // Common paths for each provider
    var syncPaths: [String] {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        switch self {
        case .iCloud:
            return [
                "\(home)/Library/Mobile Documents",
                "\(home)/Library/CloudStorage/iCloud Drive"
            ]
        case .oneDrive:
            return [
                "\(home)/Library/CloudStorage/OneDrive-Personal",
                "\(home)/OneDrive"
            ]
        case .googleDrive:
            return ["\(home)/Library/CloudStorage/GoogleDrive"]
        case .dropbox:
            return ["\(home)/Dropbox", "\(home)/Library/CloudStorage/Dropbox"]
        }
    }
}
