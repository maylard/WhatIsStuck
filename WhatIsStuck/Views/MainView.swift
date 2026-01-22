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
        } else if let error = viewModel.errorMessage {
            errorView(message: error)
        } else if viewModel.stuckFiles.isEmpty && !viewModel.isScanning {
            emptyStateView
        } else {
            fileListView
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
            Image(systemName: "checkmark.circle")
                .font(.system(size: 60))
                .foregroundColor(.green)

            VStack(spacing: 8) {
                Text("No Stuck Files Found")
                    .font(.system(size: 18, weight: .semibold))

                Text("All your cloud storage files are syncing properly.")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
            }

            if viewModel.lastScanDate == nil {
                Button("Run Your First Scan") {
                    Task {
                        await viewModel.scan()
                    }
                }
                .buttonStyle(.bordered)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - File List

    private var fileListView: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                if viewModel.isScanning {
                    HStack(spacing: 12) {
                        ProgressView()
                            .scaleEffect(0.8)
                        Text("Scanning for stuck files...")
                            .font(.system(size: 13))
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 40)
                }

                ForEach(viewModel.stuckFiles) { file in
                    VStack(spacing: 0) {
                        FileRowView(
                            file: file,
                            onRevealInFinder: {
                                viewModel.revealInFinder(file)
                            },
                            onQuitProcess: {
                                Task {
                                    await viewModel.quitBlockingProcess(file)
                                }
                            }
                        )

                        Divider()
                            .padding(.leading, 64)
                    }
                }
            }
            .padding(.vertical, 8)
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
