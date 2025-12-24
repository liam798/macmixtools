# SSHTools

A modern, native macOS tool for SSH, SFTP, Redis, and MySQL management.

## Build Requirements

- macOS 13.0 or later
- Swift 5.9 or later
- Xcode 15 or later

## Development Build

To build and run the project during development:

```bash
# Clone the repository
git clone <repository-url>
cd SSHTools

# Build the project
swift build

# Run the application
swift run SSHTools
```

## Production Build (.app bundle)

You can use the provided automated script to build the `.app` bundle:

```bash
./build_app.sh
```

The resulting app will be located in the `build/` directory.

### Manual Build Steps (Internal Logic of the script)

### 1. Build for Release
```bash
swift build -c release --arch arm64 --arch x86_64
```

### 2. Prepare App Bundle Structure
```bash
# Create the bundle directory
mkdir -p build/SSHTools.app/Contents/MacOS
mkdir -p build/SSHTools.app/Contents/Resources
```

### 3. Copy Executable and Assets
```bash
# Copy the compiled binary
cp .build/apple/Products/Release/SSHTools build/SSHTools.app/Contents/MacOS/

# Copy the App Icon
cp Sources/SSHTools/AppIcon.icns build/SSHTools.app/Contents/Resources/
```

### 4. Create Info.plist
Create a file at `build/SSHTools.app/Contents/Info.plist` with the following content:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>SSHTools</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleIdentifier</key>
    <string>com.sshtools.macos</string>
    <key>CFBundleName</key>
    <string>SSHTools</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0.0</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
```

### 5. Codesign (Optional but recommended)
```bash
codesign --force --deep --sign - build/SSHTools.app
```

## Project Structure

- `Sources/SSHTools`: Main source code.
- `Sources/SSHTools/TerminalView.swift`: SSH terminal implementation.
- `Sources/SSHTools/SFTPView.swift`: SFTP file browser.
- `Sources/SSHTools/RedisView.swift`: Redis management UI.
- `Sources/SSHTools/MySQLView.swift`: MySQL query runner and UI.
