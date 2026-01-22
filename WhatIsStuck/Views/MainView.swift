import SwiftUI

struct MainView: View {
    @StateObject private var viewModel = MainViewModel()

    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            toolbarView
                .padding()
                .background(Color(nsColor: .controlBackgroundColor))

            Divider()

            // Content
            contentView
        }
        .frame(minWidth: 700, minHeight: 500)
    }

    // MARK: - Toolbar

    private var toolbarView: some View {
        HStack {
            // Title
            VStack(alignment: .leading, spacing: 2) {
                Text("WhatIsStuck")
                    .font(.system(size: 18, weight: .semibold))

                if let lastScan = viewModel.lastScanDate {
                    Text("Last scan: \(lastScan, formatter: dateFormatter)")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                } else {
                    Text("No scans yet")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            // Scan button
            Button(action: {
                if !viewModel.hasFullDiskAccess {
                    viewModel.openSystemPreferences()
                } else {
                    Task {
                        await viewModel.scan()
                    }
                }
            }) {
                HStack(spacing: 6) {
                    if viewModel.isScanning {
                        ProgressView()
                            .scaleEffect(0.7)
                            .frame(width: 14, height: 14)
                    } else {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 13, weight: .medium))
                    }
                    Text(viewModel.isScanning ? "Scanning..." : "Scan")
                        .font(.system(size: 13, weight: .medium))
                }
                .frame(minWidth: 100)
            }
            .buttonStyle(.borderedProminent)
            .disabled(viewModel.isScanning)
        }
    }

    // MARK: - Content

    @ViewBuilder
    private var contentView: some View {
        if !viewModel.hasFullDiskAccess {
            permissionView
        } else if viewModel.isScanning {
            scanningView
        } else if viewModel.lastScanDate == nil {
            // Never scanned yet
            emptyStateView
        } else if viewModel.openFiles.isEmpty {
            // Scanned but no blocking processes found
            if let error = viewModel.errorMessage {
                successView(message: error)
            } else {
                successView(message: "No blocking processes found. iCloud sync should be working normally.")
            }
        } else {
            // Found blocking processes
            resultsView
        }
    }

    // MARK: - Permission View

    private var permissionView: some View {
        VStack(spacing: 20) {
            Image(systemName: "lock.shield")
                .font(.system(size: 60))
                .foregroundColor(.accentColor)

            VStack(spacing: 8) {
                Text("Full Disk Access Required")
                    .font(.system(size: 18, weight: .semibold))

                Text("WhatIsStuck needs Full Disk Access to scan cloud storage folders and detect stuck files.")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 400)
            }

            Button(action: {
                viewModel.openSystemPreferences()
            }) {
                Text("Open System Settings")
                    .font(.system(size: 13, weight: .medium))
                    .frame(minWidth: 180)
            }
            .buttonStyle(.borderedProminent)

            Button(action: {
                viewModel.checkPermissions()
            }) {
                Text("I've Granted Access")
                    .font(.system(size: 11))
            }
            .buttonStyle(.borderless)
            .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Error View

    private func errorView(message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 50))
                .foregroundColor(.orange)

            VStack(spacing: 6) {
                Text("Error")
                    .font(.system(size: 16, weight: .semibold))

                Text(message)
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 400)
            }

            Button("Try Again") {
                Task {
                    await viewModel.scan()
                }
            }
            .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Empty State

    private var emptyStateView: some View {
        VStack(spacing: 20) {
            Image(systemName: "icloud")
                .font(.system(size: 60))
                .foregroundColor(.accentColor)

            VStack(spacing: 8) {
                Text("Ready to Scan")
                    .font(.system(size: 18, weight: .semibold))

                Text("Click scan to find files that might be blocking iCloud sync.")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 300)
            }

            Button("Scan Now") {
                Task {
                    await viewModel.scan()
                }
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Success View

    private func successView(message: String) -> some View {
        VStack(spacing: 20) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 60))
                .foregroundColor(.green)

            VStack(spacing: 8) {
                Text("All Clear!")
                    .font(.system(size: 18, weight: .semibold))

                Text(message)
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 400)
            }

            Button("Scan Again") {
                Task {
                    await viewModel.scan()
                }
            }
            .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Scanning View

    private var scanningView: some View {
        VStack(spacing: 20) {
            ProgressView()
                .scaleEffect(1.5)

            VStack(spacing: 8) {
                Text("Scanning...")
                    .font(.system(size: 18, weight: .semibold))

                Text(viewModel.scanStage.rawValue)
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
                    .animation(.easeInOut, value: viewModel.scanStage)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Results View

    private var resultsView: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                // Header explaining what we found
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                        Text("Found \(viewModel.openFiles.count) file(s) held open by apps")
                            .font(.system(size: 14, weight: .semibold))
                    }

                    Text("These files are open in other apps, which may prevent iCloud from syncing them. Close the app or the file to allow sync to complete.")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
                .padding(16)
                .background(Color.orange.opacity(0.1))
                .cornerRadius(8)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)

                // List of blocking files
                ForEach(Array(viewModel.openFiles.keys.sorted()), id: \.self) { path in
                    if let process = viewModel.openFiles[path] {
                        blockingFileRow(path: path, process: process)
                        Divider().padding(.leading, 64)
                    }
                }
            }
        }
    }

    private func sectionHeader(title: String, count: Int, icon: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .foregroundColor(.accentColor)
            Text(title)
                .font(.system(size: 13, weight: .semibold))
            Text("(\(count))")
                .font(.system(size: 12))
                .foregroundColor(.secondary)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private func blockingFileRow(path: String, process: ProcessInfo) -> some View {
        HStack(spacing: 12) {
            // File icon from system
            Image(nsImage: NSWorkspace.shared.icon(forFile: path))
                .resizable()
                .frame(width: 40, height: 40)

            VStack(alignment: .leading, spacing: 4) {
                Text(URL(fileURLWithPath: path).lastPathComponent)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)

                Text(path)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)

                HStack(spacing: 4) {
                    Image(systemName: "app.badge.fill")
                        .font(.system(size: 10))
                    Text("Open in: \(process.displayName)")
                        .font(.system(size: 11, weight: .medium))
                }
                .foregroundColor(.orange)
            }

            Spacer()

            // Action buttons
            HStack(spacing: 8) {
                Button(action: {
                    // Reveal file in Finder
                    let url = URL(fileURLWithPath: path)
                    if FileManager.default.fileExists(atPath: path) {
                        NSWorkspace.shared.activateFileViewerSelecting([url])
                    }
                }) {
                    Label("Reveal", systemImage: "folder")
                        .font(.system(size: 11))
                }
                .buttonStyle(.bordered)

                if process.pid > 0 {
                    Button(action: {
                        // Try to quit the app
                        quitProcess(process)
                    }) {
                        Label("Quit App", systemImage: "xmark.circle")
                            .font(.system(size: 11))
                    }
                    .buttonStyle(.bordered)
                    .tint(.orange)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private func quitProcess(_ process: ProcessInfo) {
        let apps = NSWorkspace.shared.runningApplications
        if let app = apps.first(where: { $0.processIdentifier == process.pid }) {
            let didQuit = app.terminate()
            if !didQuit {
                // Show alert that app couldn't be quit
                let alert = NSAlert()
                alert.messageText = "Couldn't Quit \(process.displayName)"
                alert.informativeText = "Try closing the file manually in the app, or use Force Quit from the Apple menu."
                alert.alertStyle = .warning
                alert.addButton(withTitle: "OK")
                alert.runModal()
            } else {
                // Rescan after quitting
                Task {
                    try? await Task.sleep(nanoseconds: 1_000_000_000)
                    await viewModel.scan()
                }
            }
        }
    }

    // MARK: - Helpers

    private var dateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter
    }
}

#Preview {
    MainView()
        .frame(width: 800, height: 600)
}
