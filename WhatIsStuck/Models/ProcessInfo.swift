import Foundation

struct ProcessInfo: Identifiable, Hashable {
    let id = UUID()
    let pid: Int32
    let name: String
    let command: String

    var displayName: String {
        // Clean up the process name for display
        if name.hasSuffix(".app") {
            return String(name.dropLast(4))
        }
        return name
    }
}
