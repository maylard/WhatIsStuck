import SwiftUI

@main
struct WhatIsStuckApp: App {
    @StateObject private var permissionService = PermissionService()

    var body: some Scene {
        WindowGroup {
            contentView
                .frame(minWidth: 700, minHeight: 500)
                .onAppear {
                    configureWindow()
                }
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("About WhatIsStuck") {
                    showAboutWindow()
                }
            }

            CommandGroup(after: .appSettings) {
                Button("Check Permissions") {
                    permissionService.refreshPermissionStatus()
                }
                .keyboardShortcut("p", modifiers: [.command, .shift])
            }
        }
    }

    @ViewBuilder
    private var contentView: some View {
        if permissionService.hasFullDiskAccess {
            MainView()
                .transition(.opacity)
        } else {
            OnboardingView(permissionService: permissionService)
                .transition(.opacity)
        }
    }

    private func configureWindow() {
        // Configure the main window
        if let window = NSApplication.shared.windows.first {
            window.title = "WhatIsStuck"
            window.subtitle = "iCloud Sync Monitor"
            window.toolbarStyle = .unified
            window.titlebarAppearsTransparent = true

            // Set minimum and initial size - use 700 width to fit both onboarding and main views
            let initialSize = NSSize(width: 700, height: 600)
            window.minSize = NSSize(width: 700, height: 500)
            window.setContentSize(initialSize)

            // Center the window
            window.center()

            // Make window appear in front
            window.makeKeyAndOrderFront(nil)
        }
    }

    private func showAboutWindow() {
        let alert = NSAlert()
        alert.messageText = "WhatIsStuck"
        alert.informativeText = """
        Version 1.0.0

        Find and fix iCloud files that won't sync.

        © 2026 WhatIsStuck
        """
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}
