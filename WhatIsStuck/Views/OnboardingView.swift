import SwiftUI

struct OnboardingView: View {
    @ObservedObject var permissionService: PermissionService
    @State private var currentStep: OnboardingStep = .welcome
    @State private var isCheckingPermissions = false

    enum OnboardingStep: Int, CaseIterable {
        case welcome = 0
        case permissions = 1
        case complete = 2

        var title: String {
            switch self {
            case .welcome:
                return "Welcome to WhatIsStuck"
            case .permissions:
                return "Grant Full Disk Access"
            case .complete:
                return "You're All Set!"
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Progress indicators
            progressIndicators

            Divider()
                .padding(.vertical, 20)

            // Content
            Group {
                switch currentStep {
                case .welcome:
                    welcomeStep
                case .permissions:
                    permissionsStep
                case .complete:
                    completeStep
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .animation(.easeInOut, value: currentStep)

            Divider()
                .padding(.vertical, 20)

            // Navigation buttons
            navigationButtons
        }
        .padding(40)
        .frame(width: 700, height: 600)
    }

    private var progressIndicators: some View {
        HStack(spacing: 12) {
            ForEach(OnboardingStep.allCases, id: \.self) { step in
                HStack(spacing: 8) {
                    Circle()
                        .fill(stepColor(step))
                        .frame(width: 12, height: 12)
                        .overlay(
                            Circle()
                                .stroke(stepBorderColor(step), lineWidth: 2)
                        )

                    if step != .complete {
                        Rectangle()
                            .fill(step.rawValue < currentStep.rawValue ? Color.accentColor : Color.gray.opacity(0.3))
                            .frame(width: 60, height: 2)
                    }
                }
            }
        }
    }

    private func stepColor(_ step: OnboardingStep) -> Color {
        if step.rawValue < currentStep.rawValue {
            return .accentColor
        } else if step == currentStep {
            return .accentColor.opacity(0.5)
        } else {
            return .gray.opacity(0.2)
        }
    }

    private func stepBorderColor(_ step: OnboardingStep) -> Color {
        if step.rawValue <= currentStep.rawValue {
            return .accentColor
        } else {
            return .gray.opacity(0.3)
        }
    }

    private var welcomeStep: some View {
        VStack(spacing: 24) {
            Image(systemName: "cloud.fill")
                .font(.system(size: 80))
                .foregroundColor(.accentColor)

            VStack(spacing: 12) {
                Text("Welcome to WhatIsStuck")
                    .font(.title)
                    .fontWeight(.bold)

                Text("Never wonder why your files aren't syncing again")
                    .font(.title3)
                    .foregroundColor(.secondary)
            }

            VStack(alignment: .leading, spacing: 16) {
                FeatureRow(
                    icon: "magnifyingglass",
                    title: "Find Stuck Files",
                    description: "Quickly identify which files are having sync issues"
                )

                FeatureRow(
                    icon: "info.circle",
                    title: "See What's Blocking",
                    description: "Know exactly which process is preventing your files from syncing"
                )

                FeatureRow(
                    icon: "wrench.and.screwdriver",
                    title: "Fix Issues Fast",
                    description: "Take action to resolve sync problems with one click"
                )
            }
            .padding(.top, 20)
        }
    }

    private var permissionsStep: some View {
        VStack(spacing: 24) {
            Image(systemName: permissionService.hasFullDiskAccess ? "checkmark.shield.fill" : "lock.shield.fill")
                .font(.system(size: 80))
                .foregroundColor(permissionService.hasFullDiskAccess ? .green : .orange)

            VStack(spacing: 12) {
                Text("Full Disk Access Required")
                    .font(.title)
                    .fontWeight(.bold)

                Text("WhatIsStuck needs permission to read iCloud sync data")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }

            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Image(systemName: "1.circle.fill")
                            .foregroundColor(.accentColor)
                        Text("Click \"Open System Settings\" below")
                            .font(.body)
                    }

                    HStack(spacing: 8) {
                        Image(systemName: "2.circle.fill")
                            .foregroundColor(.accentColor)
                        Text("Find WhatIsStuck in the list")
                            .font(.body)
                    }

                    HStack(spacing: 8) {
                        Image(systemName: "3.circle.fill")
                            .foregroundColor(.accentColor)
                        Text("Toggle the switch to enable access")
                            .font(.body)
                    }

                    HStack(spacing: 8) {
                        Image(systemName: "4.circle.fill")
                            .foregroundColor(.accentColor)
                        Text("Click \"Check Permission\" to verify")
                            .font(.body)
                    }
                }
                .padding()
                .background(Color(.controlBackgroundColor))
                .cornerRadius(8)

                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Image(systemName: "info.circle.fill")
                            .foregroundColor(.blue)
                        Text("Why is this needed?")
                            .font(.headline)
                    }

                    Text("Your iCloud sync status is stored in protected system files. WhatIsStuck needs to read these files to show you which files are stuck and help you fix them. We never modify or share your data.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding()
                .background(Color.blue.opacity(0.1))
                .cornerRadius(8)
            }
            .padding(.top, 20)

            // Permission Status Indicator
            HStack(spacing: 12) {
                Image(systemName: permissionService.hasFullDiskAccess ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .font(.title3)
                    .foregroundColor(permissionService.hasFullDiskAccess ? .green : .orange)

                VStack(alignment: .leading, spacing: 2) {
                    Text(permissionService.hasFullDiskAccess ? "Permission Granted" : "Permission Required")
                        .font(.headline)
                        .foregroundColor(permissionService.hasFullDiskAccess ? .green : .primary)

                    Text(permissionService.hasFullDiskAccess
                        ? "Full Disk Access is enabled. Click Continue below."
                        : "Grant permission, then click Check Permission")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                if isCheckingPermissions {
                    ProgressView()
                        .scaleEffect(0.8)
                }
            }
            .padding(12)
            .background(permissionService.hasFullDiskAccess ? Color.green.opacity(0.1) : Color.orange.opacity(0.1))
            .cornerRadius(8)

            HStack(spacing: 16) {
                Button(action: {
                    permissionService.openSystemPreferences()
                }) {
                    HStack {
                        Image(systemName: "gearshape.fill")
                        Text("Open System Settings")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)

                Button(action: {
                    checkPermission()
                }) {
                    HStack {
                        Image(systemName: "arrow.clockwise")
                        Text("Check Permission")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(isCheckingPermissions)
            }
        }
    }

    private var completeStep: some View {
        VStack(spacing: 24) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 80))
                .foregroundColor(.green)

            VStack(spacing: 12) {
                Text("You're All Set!")
                    .font(.title)
                    .fontWeight(.bold)

                Text("WhatIsStuck is ready to help you find and fix stuck files")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }

            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    Image(systemName: "lightbulb.fill")
                        .foregroundColor(.yellow)
                        .font(.title2)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Tip: Run scans regularly")
                            .font(.headline)

                        Text("Check periodically if you notice files taking longer than usual to sync")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .padding()
                .background(Color.yellow.opacity(0.1))
                .cornerRadius(8)
            }
            .padding(.top, 20)
        }
    }

    private var navigationButtons: some View {
        HStack {
            if currentStep.rawValue > 0 && currentStep != .complete {
                Button("Back") {
                    withAnimation {
                        currentStep = OnboardingStep(rawValue: currentStep.rawValue - 1) ?? .welcome
                    }
                }
                .buttonStyle(.borderless)
            }

            Spacer()

            if currentStep == .welcome {
                Button("Get Started") {
                    withAnimation {
                        currentStep = .permissions
                    }
                }
                .buttonStyle(.borderedProminent)
            } else if currentStep == .permissions {
                if permissionService.hasFullDiskAccess {
                    Button("Continue") {
                        withAnimation {
                            currentStep = .complete
                        }
                    }
                    .buttonStyle(.borderedProminent)
                }
                // No "Skip" button - user must grant permission to use the app
            }
            // No button on complete step - permission check will auto-transition
        }
    }

    private func checkPermission() {
        isCheckingPermissions = true

        Task {
            // Wait a moment for the permission to be granted
            try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds

            await MainActor.run {
                permissionService.refreshPermissionStatus()

                if permissionService.hasFullDiskAccess {
                    withAnimation {
                        currentStep = .complete
                    }
                }

                isCheckingPermissions = false
            }
        }
    }
}

struct FeatureRow: View {
    let icon: String
    let title: String
    let description: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(.accentColor)
                .frame(width: 30)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)

                Text(description)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
        }
    }
}

#Preview {
    OnboardingView(permissionService: PermissionService())
}
