# WhatIsStuck

A native macOS utility that helps you identify which files are blocking cloud sync (iCloud, OneDrive, etc.) and which processes have them open.

## The Problem This Solves

Ever seen iCloud show "Uploading 1 item" but it never completes? And clicking the info button doesn't tell you WHICH file is stuck?

This app solves that by:
1. Querying the iCloud CloudDocs database to find stuck files
2. Using `lsof` to identify which process has the file open
3. Letting you quit the blocking process or reveal the file in Finder

**Real example:** During development, we discovered Claude Code itself was blocking an iCloud upload by holding `settings.local.json` open!

## Features

- **Find Stuck Files**: Scans iCloud Drive to find files that are stuck uploading or downloading
- **See What's Blocking**: Uses `lsof` to identify which process has a file open
- **Quick Actions**: Reveal files in Finder or quit blocking processes
- **User Friendly**: Clean SwiftUI interface with helpful onboarding

## Requirements

- macOS 13.0 (Ventura) or later
- Xcode 15.0 or later
- Apple Developer account (for code signing and notarization)

## Setup

### Option 1: Using XcodeGen (Recommended)

1. Install XcodeGen:
   ```bash
   brew install xcodegen
   ```

2. Generate the Xcode project:
   ```bash
   cd WhatIsStuck
   xcodegen generate
   ```

3. Open `WhatIsStuck.xcodeproj` in Xcode

### Option 2: Manual Setup in Xcode

1. Open Xcode and create a new project:
   - Choose "macOS" → "App"
   - Product Name: `WhatIsStuck`
   - Interface: `SwiftUI`
   - Language: `Swift`
   - Uncheck "Use Core Data"
   - Uncheck "Include Tests" (or add later)

2. Delete the auto-generated files (ContentView.swift, WhatIsStuckApp.swift)

3. Drag the `WhatIsStuck` folder into your project navigator

4. Configure build settings:
   - Deployment Target: macOS 13.0
   - Enable Hardened Runtime: Yes
   - App Sandbox: No (required for lsof/brctl access)

5. Add the entitlements file to your project

## Building

1. Open the project in Xcode
2. Select your development team in Signing & Capabilities
3. Build with `Cmd+B`
4. Run with `Cmd+R`

## Distribution

### Notarization (Required for Direct Distribution)

1. Create an Archive: `Product` → `Archive`
2. In the Organizer, click `Distribute App`
3. Choose `Developer ID` → `Direct Distribution`
4. Xcode will automatically notarize the app
5. Export the notarized app

### Creating a DMG

```bash
# Install create-dmg
brew install create-dmg

# Create DMG
create-dmg \
  --volname "WhatIsStuck" \
  --window-pos 200 120 \
  --window-size 600 400 \
  --icon-size 100 \
  --icon "WhatIsStuck.app" 150 190 \
  --app-drop-link 450 190 \
  "WhatIsStuck.dmg" \
  "/path/to/WhatIsStuck.app"
```

## How It Works

1. **Permission Request**: The app requires Full Disk Access to read the iCloud database and run `lsof`
2. **Scan**: Queries the CloudDocs SQLite database for pending uploads and uses `lsof` to find open files
3. **Match**: Correlates stuck files with the processes that have them open
4. **Action**: Users can reveal files in Finder or quit blocking processes

## Technical Details

- **ICloudService**: Reads `~/Library/Application Support/CloudDocs/session/db/client.db`
- **LsofService**: Runs `/usr/sbin/lsof -F pcn` to find open files
- **PermissionService**: Checks Full Disk Access by testing protected directory access

## Project Structure

```
WhatIsStuck/
├── App/
│   └── WhatIsStuckApp.swift       # App entry point
├── Models/
│   ├── CloudProvider.swift        # Enum for cloud providers
│   ├── ProcessInfo.swift          # Process information model
│   └── StuckFile.swift            # Stuck file model
├── Services/
│   ├── ICloudService.swift        # iCloud sync status detection
│   ├── LsofService.swift          # Process detection via lsof
│   └── PermissionService.swift    # Full Disk Access management
├── ViewModels/
│   └── MainViewModel.swift        # Main app logic
├── Views/
│   ├── FileRowView.swift          # Single file row component
│   ├── MainView.swift             # Main window view
│   └── OnboardingView.swift       # Permission setup flow
└── Resources/
    ├── Info.plist                 # App configuration
    └── WhatIsStuck.entitlements   # App entitlements
```

## License

MIT License - Feel free to use, modify, and distribute.

## Contributing

Contributions welcome! Please open an issue or PR.
