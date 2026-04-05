#!/usr/bin/env swift

//
//  capture_screenshots.swift
//
//  Captures App Store screenshots for CotEditor across all localized languages.
//  Usage: swift capture_screenshots.swift [language ...]
//
//  Requires: macOS 26.4+
//

import AppKit


// MARK: - Configuration

/// A language for which to capture screenshots.
struct Language {

    var folderName: String
    var localeCode: String
}


/// All supported languages with their App Store folder names and locale codes.
let languages: [Language] = [
    Language(folderName: "Bulgarian", localeCode: "bg"),
    Language(folderName: "Chinese (Simplified)", localeCode: "zh-Hans"),
    Language(folderName: "Chinese (Traditional)", localeCode: "zh-Hant"),
    Language(folderName: "Czech", localeCode: "cs"),
    Language(folderName: "Dutch", localeCode: "nl"),
    Language(folderName: "English", localeCode: "en"),
    Language(folderName: "English (UK)", localeCode: "en-GB"),
    Language(folderName: "French", localeCode: "fr"),
    Language(folderName: "German", localeCode: "de"),
    Language(folderName: "Italian", localeCode: "it"),
    Language(folderName: "Japanese", localeCode: "ja"),
    Language(folderName: "Korean", localeCode: "ko"),
    Language(folderName: "Polish", localeCode: "pl"),
    Language(folderName: "Portuguese", localeCode: "pt"),
    Language(folderName: "Russian", localeCode: "ru"),
    Language(folderName: "Spanish", localeCode: "es"),
    Language(folderName: "Turkish", localeCode: "tr"),
]

/// The CotEditor bundle identifier.
let bundleID = "com.coteditor.CotEditor"

/// The virtual screen size for App Store screenshots (logical pixels).
/// Mac App Store requires 1440x900 (@2x = 2880x1800).
let virtualScreenWidth = 1440
let virtualScreenHeight = 900


// MARK: - Helper Functions

/// Runs a shell command and returns its trimmed standard output.
///
/// - Parameters:
///   - command: The command to execute.
///   - arguments: The arguments for the command.
/// - Returns: The trimmed standard output string.
@discardableResult
func shell(_ command: String, arguments: [String] = []) throws -> String {

    let process = Process()
    process.executableURL = URL(fileURLWithPath: command)
    process.arguments = arguments

    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = FileHandle.nullDevice

    try process.run()
    process.waitUntilExit()

    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
}


/// Runs an AppleScript string and returns the result.
///
/// - Parameter source: The AppleScript source code.
/// - Returns: The string result of the script execution.
@discardableResult
func runAppleScript(_ source: String) throws -> String {

    let script = NSAppleScript(source: source)!
    var error: NSDictionary?
    let result = script.executeAndReturnError(&error)

    if let error {
        throw NSError(domain: "AppleScript", code: -1,
                      userInfo: [NSLocalizedDescriptionKey: error[NSAppleScript.errorMessage] ?? "Unknown AppleScript error"])
    }

    return result.stringValue ?? ""
}


/// Waits for the specified duration.
///
/// - Parameter seconds: The number of seconds to wait.
func wait(_ seconds: Double) {

    Thread.sleep(forTimeInterval: seconds)
}


/// Sends a macOS notification via Notification Center.
///
/// - Parameters:
///   - title: The notification title.
///   - message: The notification message.
func sendNotification(title: String, message: String) {

    _ = try? shell("/usr/bin/osascript", arguments: ["-e",
        "display notification \"\(message)\" with title \"\(title)\""])
}


// MARK: - Desktop State Management

/// Sets the desktop background of all desktops to the specified image.
///
/// - Parameter path: The POSIX path to the background image.
func setAllDesktopBackgrounds(path: String) throws {

    try runAppleScript("""
        tell application "System Events"
            set picture of every desktop to "\(path)"
        end tell
        """)
    wait(1)
}


/// Moves files on the desktop to a temporary directory.
///
/// - Returns: The path to the temporary directory where files were moved.
func hideDesktopFiles() throws -> String {

    let tempDir = NSTemporaryDirectory() + "desktop_backup_\(ProcessInfo.processInfo.processIdentifier)/"
    let fileManager = FileManager.default
    let desktopURL = fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Desktop")

    try fileManager.createDirectory(atPath: tempDir, withIntermediateDirectories: true)

    let contents = try fileManager.contentsOfDirectory(atPath: desktopURL.path)
    for item in contents where item != ".DS_Store" && item != ".localized" {
        let source = desktopURL.appendingPathComponent(item).path
        let destination = tempDir + item
        try fileManager.moveItem(atPath: source, toPath: destination)
    }

    print("  Desktop files moved to: \(tempDir)")
    return tempDir
}


/// Restores files from the temporary directory back to the desktop.
///
/// - Parameter tempDir: The path to the temporary directory.
func restoreDesktopFiles(from tempDir: String) throws {

    let fileManager = FileManager.default
    let desktopPath = fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Desktop").path

    guard fileManager.fileExists(atPath: tempDir) else { return }

    let contents = try fileManager.contentsOfDirectory(atPath: tempDir)
    for item in contents {
        let source = tempDir + item
        let destination = desktopPath + "/" + item
        try fileManager.moveItem(atPath: source, toPath: destination)
    }

    try fileManager.removeItem(atPath: tempDir)
    print("  Desktop files restored.")
}


// MARK: - CotEditor Control

/// Exports all CotEditor defaults to a temporary plist file for later restoration.
///
/// - Returns: The path to the backup plist file.
func saveCotEditorDefaults() throws -> String {

    let path = NSTemporaryDirectory() + "coteditor_defaults_backup.plist"
    try shell("/usr/bin/defaults", arguments: ["export", bundleID, path])
    return path
}


/// Restores CotEditor defaults from a backup plist file.
///
/// - Parameter path: The path to the backup plist file.
func restoreCotEditorDefaults(from path: String) throws {

    try shell("/usr/bin/defaults", arguments: ["import", bundleID, path])
    try? FileManager.default.removeItem(atPath: path)
    print("  CotEditor defaults restored.")
}


/// Sets CotEditor's preferred language.
///
/// - Parameter localeCode: The locale code to set.
func setCotEditorLanguage(_ localeCode: String) throws {

    try shell("/usr/bin/defaults", arguments: ["write", bundleID, "AppleLanguages", "-array", localeCode])
}


/// Removes the CotEditor language override.
func resetCotEditorLanguage() throws {

    try shell("/usr/bin/defaults", arguments: ["delete", bundleID, "AppleLanguages"])
}


/// Writes a CotEditor defaults value.
///
/// - Parameters:
///   - key: The defaults key.
///   - type: The type flag (e.g. "-string", "-bool", "-int").
///   - value: The value to write.
func setCotEditorDefault(_ key: String, type: String, value: String) throws {

    try shell("/usr/bin/defaults", arguments: ["write", bundleID, key, type, value])
}


/// Sets CotEditor's font via `defaults write -data`.
///
/// - Parameters:
///   - name: The font name (PostScript name).
///   - size: The font size in points.
func setCotEditorFont(name: String, size: CGFloat) throws {

    guard let font = NSFont(name: name, size: size) else {
        throw NSError(domain: "Font", code: -1,
                      userInfo: [NSLocalizedDescriptionKey: "Font '\(name)' not found"])
    }
    let data = try NSKeyedArchiver.archivedData(
        withRootObject: font.fontDescriptor, requiringSecureCoding: true)
    let hex = data.map { String(format: "%02x", $0) }.joined()
    try shell("/usr/bin/defaults", arguments: ["write", bundleID, "font", "-data", hex])
}


/// Flushes CotEditor defaults by reading back a key.
func flushCotEditorDefaults() throws {

    _ = try shell("/usr/bin/defaults", arguments: ["read", bundleID, "defaultTheme"])
    wait(0.3)
}


/// Launches CotEditor with a demo file, closes other windows, and hides other applications.
///
/// - Parameters:
///   - demoFile: The path to the demo file to open, or `nil` to launch without a file.
///   - setupDocument: An optional AppleScript block to run inside `tell front document`.
func launchCotEditor(withFile demoFile: String? = nil, setupDocument: String? = nil) throws {

    if let demoFile {
        try shell("/usr/bin/open", arguments: ["-a", "CotEditor", demoFile])
    } else {
        try shell("/usr/bin/open", arguments: ["-a", "CotEditor"])
    }

    // Wait for the application to be fully ready.
    try runAppleScript("""
        tell application "System Events"
            repeat 30 times
                if exists process "CotEditor" then exit repeat
                delay 0.2
            end repeat
        end tell
        """)
    wait(0.5)

    // Close all windows and re-open the file if specified.
    var documentScript = ""
    if let demoFile {
        documentScript = """
                open POSIX file "\(demoFile)"
        """
        if let setupDocument {
            documentScript += """

                    tell front document
                        \(setupDocument)
                    end tell
            """
        }
    }
    try runAppleScript("""
        tell application "CotEditor"
            close every window without saving
            \(documentScript)
        end tell
        """)
    wait(0.5)

    // Hide all other applications.
    try runAppleScript("""
        tell application "System Events"
            set visible of every process whose name is not "CotEditor" and name is not "Finder" to false
        end tell
        """)
    wait(0.3)
}


/// Quits CotEditor.
func quitCotEditor() throws {

    try runAppleScript("""
        tell application "CotEditor" to quit
        """)

    // Wait until CotEditor has fully quit.
    try runAppleScript("""
        tell application "System Events"
            repeat 30 times
                if not (exists process "CotEditor") then exit repeat
                delay 0.2
            end repeat
        end tell
        """)
}


// MARK: - Screenshot Capture

/// Returns the display ID of the built-in (MacBook) screen.
///
/// - Returns: The display ID of the built-in screen, or the main display as fallback.
func builtInDisplayID() -> CGDirectDisplayID {

    let maxDisplays: UInt32 = 16
    var displays = [CGDirectDisplayID](repeating: 0, count: Int(maxDisplays))
    var displayCount: UInt32 = 0
    CGGetActiveDisplayList(maxDisplays, &displays, &displayCount)

    for i in 0..<Int(displayCount) {
        if CGDisplayIsBuiltin(displays[i]) != 0 {
            return displays[i]
        }
    }

    return CGMainDisplayID()
}


/// Returns the bounds of the built-in screen in screen coordinates (top-left origin).
///
/// - Returns: The screen bounds matching AppleScript's coordinate system.
func builtInScreenBounds() -> CGRect {

    CGDisplayBounds(builtInDisplayID())
}


/// Captures the virtual screen area (1440x900) of the built-in display to the specified path.
///
/// - Parameter path: The output file path.
func captureScreen(to path: String) throws {

    let bounds = builtInScreenBounds()
    let rect = "\(Int(bounds.origin.x)),\(Int(bounds.origin.y)),\(virtualScreenWidth),\(virtualScreenHeight)"
    try shell("/usr/sbin/screencapture", arguments: ["-x", "-R", rect, path])
}


/// Screen layout information for the built-in display in screen coordinates (top-left origin).
struct ScreenInfo {

    var originX: Int
    var originY: Int
    var width: Int
    var menuBarHeight: Int
    var availableHeight: Int
}


/// Returns the actual menu bar height of the built-in display.
///
/// - Returns: The menu bar height in logical pixels.
func builtInMenuBarHeight() -> Int {

    let displayID = builtInDisplayID()

    for screen in NSScreen.screens {
        if screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID == displayID {
            return Int(screen.frame.maxY - screen.visibleFrame.maxY)
        }
    }

    return 25
}


/// Returns the virtual screen layout information for the built-in display.
///
/// Window positioning and centering are calculated based on the virtual 1440x900 area,
/// while the origin and menu bar height come from the actual display.
///
/// - Returns: The screen information matching AppleScript's coordinate system.
func builtInScreenInfo() -> ScreenInfo {

    let screenBounds = builtInScreenBounds()
    let menuBarHeight = builtInMenuBarHeight()

    return ScreenInfo(
        originX: Int(screenBounds.origin.x),
        originY: Int(screenBounds.origin.y),
        width: virtualScreenWidth,
        menuBarHeight: menuBarHeight,
        availableHeight: virtualScreenHeight - menuBarHeight
    )
}


/// Generates an AppleScript snippet that resizes and centers window 1 with macOS-style centering (top:bottom = 1:2).
///
/// - Parameters:
///   - width: The desired window width.
///   - height: The desired window height.
///   - screen: The screen layout information.
/// - Returns: An AppleScript snippet to resize and center the window.
func windowCenteringScript(width: Int, height: Int, screen: ScreenInfo) -> String {

    """
                    set size of window 1 to {\(width), \(height)}
                    set actualSize to size of window 1
                    set actualWidth to item 1 of actualSize
                    set actualHeight to item 2 of actualSize
                    set position of window 1 to {\(screen.originX) + (\(screen.width) - actualWidth) / 2, \(screen.originY) + \(screen.menuBarHeight) + (\(screen.availableHeight) - actualHeight) / 3}
    """
}


/// Generates an AppleScript snippet that resizes window 1 and positions it at the specified x with macOS-style vertical centering.
///
/// - Parameters:
///   - width: The desired window width.
///   - height: The desired window height.
///   - x: The x position relative to the display origin.
///   - screen: The screen layout information.
/// - Returns: An AppleScript snippet to resize and position the window.
func windowPositioningScript(width: Int, height: Int, x: Int, screen: ScreenInfo) -> String {

    """
                    set size of window 1 to {\(width), \(height)}
                    set actualSize to size of window 1
                    set actualHeight to item 2 of actualSize
                    set position of window 1 to {\(screen.originX + x), \(screen.originY) + \(screen.menuBarHeight) + (\(screen.availableHeight) - actualHeight) / 3}
    """
}


/// Hides the system status items in the menu bar by overwriting the top-right area
/// with a clean strip sampled from the screenshot's own menu bar gap.
///
/// - Parameter screenshotPath: The path to the screenshot to modify.
func overlayMenuBar(screenshotPath: String) throws {

    let screenshotURL = URL(fileURLWithPath: screenshotPath)

    guard let screenshotData = try? Data(contentsOf: screenshotURL),
          let screenshotRep = NSBitmapImageRep(data: screenshotData),
          let screenshotCG = screenshotRep.cgImage else {
        print("    Warning: Could not load screenshot for menu bar overlay")
        return
    }

    let width = screenshotCG.width
    let height = screenshotCG.height
    let scale = width / virtualScreenWidth
    let overlayH = 40 * scale
    // Sample a 1px-wide column from the left edge of the menu bar,
    // where no window shadows reach.
    let sampleX = 0

    // Crop a 1px-wide strip from the menu bar area of the screenshot itself.
    let stripRect = CGRect(x: sampleX, y: 0, width: 1, height: overlayH)
    guard let strip = screenshotCG.cropping(to: stripRect) else {
        print("    Warning: Could not crop menu bar strip")
        return
    }

    // Create a CGContext and draw the screenshot.
    guard let ctx = CGContext(
        data: nil, width: width, height: height,
        bitsPerComponent: 8, bytesPerRow: width * 4,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else {
        print("    Warning: Could not create CGContext for overlay")
        return
    }
    ctx.draw(screenshotCG, in: CGRect(x: 0, y: 0, width: width, height: height))

    // Tile the strip over the rightmost 400 logical px of the menu bar.
    let tileY = height - overlayH
    let tileStartX = width - 400 * scale
    for x in tileStartX..<width {
        ctx.draw(strip, in: CGRect(x: x, y: tileY, width: 1, height: overlayH))
    }

    guard let resultCG = ctx.makeImage() else {
        print("    Warning: Could not create result image")
        return
    }
    let resultRep = NSBitmapImageRep(cgImage: resultCG)
    guard let pngData = resultRep.representation(using: .png, properties: [:]) else {
        print("    Warning: Could not encode PNG")
        return
    }
    try pngData.write(to: screenshotURL)
}


/// Takes a screenshot, overlays the menu bar, and saves it to the specified path.
///
/// - Parameter outputPath: The destination file path.
func takeScreenshot(to outputPath: String) throws {

    let tempFile = NSTemporaryDirectory() + "screenshot_temp.png"
    try captureScreen(to: tempFile)

    // Hide system status items in the menu bar.
    try overlayMenuBar(screenshotPath: tempFile)

    let fileManager = FileManager.default
    if fileManager.fileExists(atPath: outputPath) {
        try fileManager.removeItem(atPath: outputPath)
    }
    try fileManager.moveItem(atPath: tempFile, toPath: outputPath)
}


// MARK: - Capture Functions

/// Captures the Settings (Appearance pane) screenshot.
///
/// - Parameters:
///   - language: The language for which to capture.
///   - outputPath: The path to save the screenshot.
func captureSettings(language: Language, outputPath: String) throws {

    print("  Capturing Settings...")

    try setCotEditorLanguage(language.localeCode)
    try launchCotEditor()

    let screen = builtInScreenInfo()

    try runAppleScript("""
        tell application "System Events"
            tell process "CotEditor"
                set frontmost to true
                delay 0.3

                keystroke "," using command down
                delay 0.5

                repeat 30 times
                    if exists toolbar 1 of window 1 then exit repeat
                    delay 0.2
                end repeat

                click button 2 of toolbar 1 of window 1
                delay 0.3

        \(windowCenteringScript(width: 700, height: 780, screen: screen))
                delay 0.3
            end tell
        end tell
        """)

    try takeScreenshot(to: outputPath)
    try quitCotEditor()

    print("  ✓ Saved: \(outputPath)")
}


/// Captures the VerticalOrientation screenshot.
///
/// - Parameters:
///   - language: The language for which to capture.
///   - demoFile: The path to the demo file to open.
///   - outputPath: The path to save the screenshot.
func captureVerticalOrientation(language: Language, demoFile: String, outputPath: String) throws {

    print("  Capturing VerticalOrientation...")

    try setCotEditorLanguage(language.localeCode)
    try setCotEditorDefault("defaultTheme", type: "-string", value: "Resinifictrix")
    try setCotEditorDefault("highlightCurrentLine", type: "-bool", value: "false")
    try setCotEditorDefault("showStatusArea", type: "-bool", value: "false")
    try setCotEditorDefault("selectedInspectorPaneIndex", type: "-int", value: "1")
    try setCotEditorFont(name: "Klee", size: 13)
    try flushCotEditorDefaults()

    try launchCotEditor(withFile: demoFile, setupDocument: "set range of selection to {100, 0}")

    let screen = builtInScreenInfo()

    try runAppleScript("""
        tell application "System Events"
            tell process "CotEditor"
                set frontmost to true
                delay 0.3

                -- Hide toolbar
                keystroke "t" using {command down, option down}
                delay 0.3

                -- Show inspector
                keystroke "i" using command down
                delay 0.3

        \(windowCenteringScript(width: 1000, height: 700, screen: screen))
                delay 0.3
            end tell
        end tell
        """)

    try takeScreenshot(to: outputPath)
    try quitCotEditor()

    print("  ✓ Saved: \(outputPath)")
}


/// Captures the Editor screenshot.
///
/// - Parameters:
///   - language: The language for which to capture.
///   - demoFile: The path to the demo file to open.
///   - outputPath: The path to save the screenshot.
func captureEditor(language: Language, demoFile: String, outputPath: String) throws {

    print("  Capturing Editor...")

    // Set defaults.
    try setCotEditorLanguage(language.localeCode)
    try setCotEditorDefault("defaultTheme", type: "-string", value: "Anura")
    try setCotEditorDefault("showStatusArea", type: "-bool", value: "true")
    try setCotEditorDefault("findUsesRegularExpression", type: "-bool", value: "true")
    try setCotEditorFont(name: "Menlo", size: 13)

    // Ensure toolbar is visible.
    try shell("/usr/bin/defaults", arguments: ["write", bundleID, "NSToolbar Configuration Document",
        "-dict-add", "TB Is Shown", "-bool", "true"])

    // Set Find panel width.
    let bounds = builtInScreenBounds()
    try shell("/usr/bin/defaults", arguments: ["write", bundleID, "NSWindow Frame Find Panel",
        "0 0 540 227 \(Int(bounds.origin.x)) \(Int(bounds.origin.y)) \(Int(bounds.width)) \(Int(bounds.height))"])

    // Set the find pasteboard.
    let findPasteboard = NSPasteboard(name: .find)
    findPasteboard.clearContents()
    findPasteboard.setString(#"stroke-width="(\d+)""#, forType: .string)

    try flushCotEditorDefaults()

    // Launch and open the file.
    try launchCotEditor(withFile: demoFile)

    let screen = builtInScreenInfo()

    // Close inspector and resize the document window.
    try runAppleScript("""
        tell application "System Events"
            tell process "CotEditor"
                set frontmost to true
                delay 0.3

                -- Close inspector (opened by previous VerticalOrientation capture)
                keystroke "i" using command down
                delay 0.3

        \(windowPositioningScript(width: 700, height: 780, x: 280, screen: screen))
                delay 0.3
            end tell
        end tell
        """)

    // Open Find & Replace.
    try runAppleScript("""
        tell application "System Events"
            tell process "CotEditor"
                keystroke "f" using command down
                delay 0.8
            end tell
        end tell
        """)

    // Position the Find window.
    try runAppleScript("""
        tell application "System Events"
            tell process "CotEditor"
                set position of window 1 to {\(screen.originX + 780), \(screen.originY + 400)}
                delay 0.3

                -- Deselect the text field
                key code 124
                delay 0.3

                -- Find All
                keystroke "F" using {command down, shift down}
                delay 1
            end tell
        end tell
        """)

    try takeScreenshot(to: outputPath)
    try quitCotEditor()

    print("  ✓ Saved: \(outputPath)")
}


// MARK: - Main

let scriptDir = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent().path
let screenshotsDir: String
if scriptDir.isEmpty || scriptDir == "." {
    screenshotsDir = FileManager.default.currentDirectoryPath
} else {
    screenshotsDir = scriptDir
}
let backgroundPath = screenshotsDir + "/background@2x.png"

// Verify the background image exists.
guard FileManager.default.fileExists(atPath: backgroundPath) else {
    print("Error: Background image not found at \(backgroundPath)")
    print("Run this script from the Screenshots directory.")
    exit(1)
}

// Determine target languages from command-line arguments.
let targetLanguages: [Language]
let args = Array(CommandLine.arguments.dropFirst())
if args.isEmpty {
    targetLanguages = languages
} else {
    targetLanguages = args.compactMap { arg in
        if let lang = languages.first(where: { $0.folderName == arg }) {
            return lang
        }
        if let lang = languages.first(where: { $0.localeCode == arg }) {
            return lang
        }
        print("Warning: Unknown language '\(arg)'. Skipping.")
        return nil
    }
    guard !targetLanguages.isEmpty else {
        print("Error: No valid languages specified.")
        print("Available languages: \(languages.map(\.folderName).joined(separator: ", "))")
        exit(1)
    }
}

print("=== CotEditor App Store Screenshot Capture ===")
print("Screenshots directory: \(screenshotsDir)")
print("Target languages: \(targetLanguages.map(\.folderName).joined(separator: ", "))")
print("")

print("Preparing...")
var tempDesktopDir: String?
var defaultsBackupPath: String?

// Ensure cleanup runs on exit.
func cleanup() {

    print("")
    print("Cleaning up...")

    // Quit CotEditor if still running.
    do {
        try quitCotEditor()
    } catch {
        // CotEditor may not be running; ignore.
    }

    // Restore CotEditor defaults.
    if let defaultsBackupPath {
        do {
            try restoreCotEditorDefaults(from: defaultsBackupPath)
        } catch {
            print("  Warning: Could not restore CotEditor defaults: \(error.localizedDescription)")
            print("  Backup is at: \(defaultsBackupPath)")
        }
    } else {
        do {
            try resetCotEditorLanguage()
            print("  CotEditor language reset.")
        } catch {
            print("  Warning: Could not reset CotEditor language: \(error.localizedDescription)")
        }
    }

    // Restore desktop files.
    if let tempDesktopDir {
        do {
            try restoreDesktopFiles(from: tempDesktopDir)
        } catch {
            print("  Warning: Could not restore desktop files: \(error.localizedDescription)")
            print("  Files are in: \(tempDesktopDir)")
        }
    }

    print("  Note: Please restore your desktop background manually if needed.")
}

// Handle SIGINT (Ctrl+C).
signal(SIGINT) { _ in
    cleanup()
    exit(1)
}

let demoFileVertical = screenshotsDir + "/_demo files/銀河鉄道の夜.md"
let demoFileEditor = screenshotsDir + "/_demo files/editor.svg"

do {
    // Save CotEditor defaults before any modifications.
    print("Saving CotEditor defaults...")
    defaultsBackupPath = try saveCotEditorDefaults()

    // Hide desktop files.
    print("Hiding desktop files...")
    tempDesktopDir = try hideDesktopFiles()

    // Set the background.
    print("Setting desktop background...")
    try setAllDesktopBackgrounds(path: backgroundPath)

    // Capture screenshots for each language.
    print("")
    print("Starting capture for \(targetLanguages.count) language(s)...")
    print("")

    for (index, language) in targetLanguages.enumerated() {
        print("[\(index + 1)/\(targetLanguages.count)] \(language.folderName) (\(language.localeCode))")

        let outputDir = screenshotsDir + "/" + language.folderName
        guard FileManager.default.fileExists(atPath: outputDir) else {
            print("  Skipping: directory not found")
            continue
        }

        try captureSettings(language: language, outputPath: outputDir + "/Settings@2x.png")
        try captureVerticalOrientation(language: language, demoFile: demoFileVertical, outputPath: outputDir + "/VerticalOrientation@2x.png")
        try captureEditor(language: language, demoFile: demoFileEditor, outputPath: outputDir + "/Editor@2x.png")
    }

    print("")
    print("All screenshots captured successfully!")
    cleanup()
    sendNotification(title: "Screenshot Capture Complete",
                     message: "\(targetLanguages.count) language(s) captured successfully.")

} catch {
    print("")
    print("Error: \(error.localizedDescription)")
    cleanup()
    sendNotification(title: "Screenshot Capture Failed",
                     message: error.localizedDescription)
}
