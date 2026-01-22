# WhatIsStuck

<p align="center">
  <img src="icon.png" width="128" height="128" alt="WhatIsStuck App Icon">
</p>

<p align="center">
  <strong>Find out what's blocking your iCloud sync</strong>
</p>

<p align="center">
  A native macOS utility that identifies files stuck in cloud sync and shows which apps have them open.
</p>

---

## The Problem

Ever seen iCloud show **"Uploading 1 item"** that never completes? Clicking the info button doesn't tell you *which* file is stuck or *why*.

**WhatIsStuck** solves this by:
1. Querying the iCloud CloudDocs database to find pending uploads
2. Using `lsof` to identify which process has the file open
3. Letting you quit the blocking app or reveal the file in Finder

## Screenshots

| Scanning | Results |
|----------|---------|
| Shows progress while scanning cloud folders | Lists stuck files with blocking process |

## Features

- **Find Stuck Files** - Scans iCloud Drive, Desktop, Documents, and Downloads
- **See What's Blocking** - Shows which app has each file open
- **Quick Actions** - Reveal in Finder or quit blocking apps with one click
- **Smart Filtering** - Ignores system processes (fileproviderd, Spotlight, etc.)
- **Clean UI** - Native SwiftUI interface with guided onboarding

## Requirements

- macOS 13.0 (Ventura) or later
- Full Disk Access permission (guided setup on first launch)

## Installation

### Option 1: Download Release (Recommended)

Download the latest `.dmg` from [Releases](../../releases) and drag to Applications.

### Option 2: Build from Source

```bash
# Clone the repo
git clone https://github.com/maylard/WhatIsStuck.git
cd WhatIsStuck

# Install XcodeGen (if needed)
brew install xcodegen

# Generate Xcode project
xcodegen generate

# Open in Xcode
open WhatIsStuck.xcodeproj
```

Build with `Cmd+B` and run with `Cmd+R`.

## Usage

1. **Grant Permission** - On first launch, follow the guide to enable Full Disk Access
2. **Scan** - Click the scan button to find stuck files
3. **Take Action** - Click "Reveal" to show in Finder or "Quit App" to release the file

## How It Works

| Component | Purpose |
|-----------|---------|
| **ICloudService** | Queries `~/Library/Application Support/CloudDocs/session/db/client.db` for pending uploads |
| **LsofService** | Runs `lsof +D` on cloud-synced folders to find open files |
| **PermissionService** | Verifies Full Disk Access by testing database access |

### What Gets Scanned

- `~/Library/Mobile Documents/` - iCloud Drive
- `~/Desktop/` - If Desktop sync is enabled
- `~/Documents/` - If Documents sync is enabled
- `~/Downloads/` - If synced to iCloud

### Filtered Out

System processes that *manage* sync (not blockers):
- `fileproviderd`, `bird`, `cloudd`, `brctl`
- `mds`, `Spotlight`, `quicklookd`
- `Finder`, `com.apple.*` services

## Project Structure

```
WhatIsStuck/
├── App/
│   └── WhatIsStuckApp.swift       # App entry point
├── Models/
│   ├── CloudProvider.swift        # Cloud provider enum
│   ├── ProcessInfo.swift          # Process info model
│   └── StuckFile.swift            # Stuck file model
├── Services/
│   ├── ICloudService.swift        # iCloud database queries
│   ├── LsofService.swift          # Process detection
│   └── PermissionService.swift    # Permission management
├── ViewModels/
│   └── MainViewModel.swift        # App state & logic
├── Views/
│   ├── FileRowView.swift          # File row component
│   ├── MainView.swift             # Main window
│   └── OnboardingView.swift       # Setup flow
└── Resources/
    ├── Assets.xcassets/           # App icon
    ├── Info.plist
    └── WhatIsStuck.entitlements
```

## Why Not App Store?

App Store sandboxing prevents:
- Running `lsof` to find which process has files open
- Accessing the CloudDocs database
- The core features that make this app useful

Direct distribution with notarization allows full functionality while remaining secure.

## Building for Distribution

```bash
# Archive in Xcode: Product → Archive
# Then: Distribute App → Developer ID → Direct Distribution

# Create DMG (optional)
brew install create-dmg
create-dmg \
  --volname "WhatIsStuck" \
  --window-size 600 400 \
  --icon-size 100 \
  --icon "WhatIsStuck.app" 150 190 \
  --app-drop-link 450 190 \
  "WhatIsStuck.dmg" \
  "path/to/WhatIsStuck.app"
```

## Origin Story

This app was born when I noticed iCloud stuck at "Uploading 1 item" (69KB/73KB) but couldn't see which file. After digging through `brctl dump` and `lsof`, I discovered **Claude Code** was holding `settings.local.json` open! This inspired creating a GUI so anyone can solve this without terminal commands.

## Contributing

Contributions welcome! Please open an issue or PR.

## License

MIT License - See [LICENSE](LICENSE) for details.
