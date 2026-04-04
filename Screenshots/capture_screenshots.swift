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

/// The window size for screenshots (logical pixels).
let windowWidth = 700
let windowHeight = 780


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


/// Launches CotEditor, closes all its windows, and hides other applications.
func launchCotEditor() throws {

    try shell("/usr/bin/open", arguments: ["-a", "CotEditor"])

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

    // Close all CotEditor windows.
    try runAppleScript("""
        tell application "CotEditor"
            close every window without saving
        end tell
        """)

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


/// Captures a full-screen screenshot of the built-in display to the specified path.
///
/// - Parameter path: The output file path.
func captureScreen(to path: String) throws {

    let bounds = builtInScreenBounds()
    let rect = "\(Int(bounds.origin.x)),\(Int(bounds.origin.y)),\(Int(bounds.width)),\(Int(bounds.height))"
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


/// Returns the screen layout information for the built-in display.
///
/// - Returns: The screen information matching AppleScript's coordinate system.
func builtInScreenInfo() -> ScreenInfo {

    let screenBounds = builtInScreenBounds()
    let displayID = builtInDisplayID()

    let menuBarHeight: Int = {
        for screen in NSScreen.screens {
            if screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID == displayID {
                return Int(screen.frame.maxY - screen.visibleFrame.maxY)
            }
        }
        return 25
    }()

    return ScreenInfo(
        originX: Int(screenBounds.origin.x),
        originY: Int(screenBounds.origin.y),
        width: Int(screenBounds.width),
        menuBarHeight: menuBarHeight,
        availableHeight: Int(screenBounds.height) - menuBarHeight
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
                    -- Resize the window
                    set size of window 1 to {\(width), \(height)}

                    -- Center the window based on its actual size
                    set actualSize to size of window 1
                    set actualWidth to item 1 of actualSize
                    set actualHeight to item 2 of actualSize
                    set position of window 1 to {\(screen.originX) + (\(screen.width) - actualWidth) / 2, \(screen.originY) + \(screen.menuBarHeight) + (\(screen.availableHeight) - actualHeight) / 3}
    """
}


/// Takes a screenshot and saves it to the specified path.
///
/// - Parameter outputPath: The destination file path.
func takeScreenshot(to outputPath: String) throws {

    let tempFile = NSTemporaryDirectory() + "screenshot_temp.png"
    try captureScreen(to: tempFile)

    let fileManager = FileManager.default
    if fileManager.fileExists(atPath: outputPath) {
        try fileManager.removeItem(atPath: outputPath)
    }
    try fileManager.moveItem(atPath: tempFile, toPath: outputPath)
}


/// Captures the Settings (Appearance pane) screenshot.
///
/// - Parameters:
///   - language: The language for which to capture.
///   - outputPath: The path to save the screenshot.
func captureSettings(language: Language, outputPath: String) throws {

    print("  Capturing Settings for \(language.folderName)...")

    // Set language and launch CotEditor.
    try setCotEditorLanguage(language.localeCode)
    try launchCotEditor()

    let screen = builtInScreenInfo()

    // Open Settings window and select Appearance pane.
    try runAppleScript("""
        tell application "System Events"
            tell process "CotEditor"
                set frontmost to true
                delay 0.3

                -- Open Settings window
                keystroke "," using command down
                delay 0.5

                -- Wait for the Settings window toolbar
                repeat 30 times
                    if exists toolbar 1 of window 1 then exit repeat
                    delay 0.2
                end repeat

                -- Click the 2nd toolbar button (Appearance)
                click button 2 of toolbar 1 of window 1
                delay 0.3

        \(windowCenteringScript(width: windowWidth, height: windowHeight, screen: screen))
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

    print("  Capturing VerticalOrientation for \(language.folderName)...")

    // Set language and CotEditor preferences.
    try setCotEditorLanguage(language.localeCode)
    try shell("/usr/bin/defaults", arguments: ["write", bundleID, "defaultTheme", "-string", "Resinifictrix"])
    try shell("/usr/bin/defaults", arguments: ["write", bundleID, "highlightCurrentLine", "-bool", "false"])
    try shell("/usr/bin/defaults", arguments: ["write", bundleID, "showStatusArea", "-bool", "false"])
    try shell("/usr/bin/defaults", arguments: ["write", bundleID, "selectedInspectorPaneIndex", "-int", "1"])
    try setCotEditorFont(name: "Klee", size: 13)

    // Force cfprefsd to flush by reading back.
    _ = try shell("/usr/bin/defaults", arguments: ["read", bundleID, "defaultTheme"])
    wait(0.3)

    // Open the demo file with CotEditor.
    try shell("/usr/bin/open", arguments: ["-a", "CotEditor", demoFile])

    // Wait for CotEditor to be ready.
    try runAppleScript("""
        tell application "System Events"
            repeat 30 times
                if exists process "CotEditor" then exit repeat
                delay 0.2
            end repeat
        end tell
        """)
    wait(0.5)

    // Close all other windows and re-open just the demo file.
    try runAppleScript("""
        tell application "CotEditor"
            close every window without saving
            open POSIX file "\(demoFile)"
            tell front document
                set range of selection to {100, 0}
            end tell
        end tell
        """)
    wait(0.5)

    // Hide all other applications.
    try runAppleScript("""
        tell application "System Events"
            set visible of every process whose name is not "CotEditor" and name is not "Finder" to false
        end tell
        """)

    let screen = builtInScreenInfo()

    // Hide toolbar, show inspector, then resize and center.
    try runAppleScript("""
        tell application "System Events"
            tell process "CotEditor"
                set frontmost to true
                delay 0.3

                -- Hide toolbar (standard macOS shortcut: Cmd+Option+T)
                keystroke "t" using {command down, option down}
                delay 0.3

                -- Show inspector (Cmd+I) — toggle, so check state after
                keystroke "i" using command down
                delay 0.3
                -- If inspector didn't open (window width didn't change), it was already open
                -- and we just closed it. Toggle again.
                -- We detect by checking if window width grew beyond our target.

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

    print("  Capturing Editor for \(language.folderName)...")
    print("    [1/7] Setting defaults...")

    // Set language and CotEditor preferences.
    try setCotEditorLanguage(language.localeCode)
    try shell("/usr/bin/defaults", arguments: ["write", bundleID, "defaultTheme", "-string", "Anura"])
    try shell("/usr/bin/defaults", arguments: ["write", bundleID, "showStatusArea", "-bool", "true"])
    try shell("/usr/bin/defaults", arguments: ["write", bundleID, "findUsesRegularExpression", "-bool", "true"])
    try setCotEditorFont(name: "Menlo", size: 13)

    // Ensure toolbar is visible.
    try shell("/usr/bin/defaults", arguments: ["write", bundleID, "NSToolbar Configuration Document",
        "-dict-add", "TB Is Shown", "-bool", "true"])

    // Set Find panel width to 540 via NSWindow frame defaults.
    // Format: "x y width height screenX screenY screenWidth screenHeight"
    let bounds = builtInScreenBounds()
    try shell("/usr/bin/defaults", arguments: ["write", bundleID, "NSWindow Frame Find Panel",
        "0 0 540 227 \(Int(bounds.origin.x)) \(Int(bounds.origin.y)) \(Int(bounds.width)) \(Int(bounds.height))"])

    // Set the find pasteboard to the regex pattern.
    let findPasteboard = NSPasteboard(name: .find)
    findPasteboard.clearContents()
    findPasteboard.setString(#"stroke-width="(\d+)""#, forType: .string)

    // Force cfprefsd to flush by reading back.
    _ = try shell("/usr/bin/defaults", arguments: ["read", bundleID, "defaultTheme"])
    wait(0.3)

    print("    [2/7] Opening demo file...")
    try shell("/usr/bin/open", arguments: ["-a", "CotEditor", demoFile])

    // Wait for CotEditor to be ready.
    try runAppleScript("""
        tell application "System Events"
            repeat 30 times
                if exists process "CotEditor" then exit repeat
                delay 0.2
            end repeat
        end tell
        """)
    wait(0.5)

    print("    [3/7] Closing other windows...")
    try runAppleScript("""
        tell application "CotEditor"
            close every window without saving
            open POSIX file "\(demoFile)"
        end tell
        """)
    wait(0.5)

    print("    [4/7] Hiding other apps...")
    try runAppleScript("""
        tell application "System Events"
            set visible of every process whose name is not "CotEditor" and name is not "Finder" to false
        end tell
        """)

    let screen = builtInScreenInfo()

    print("    [5/7] Closing inspector and resizing document window...")
    try runAppleScript("""
        tell application "System Events"
            tell process "CotEditor"
                set frontmost to true
                delay 0.3

                -- Close inspector (opened by previous VerticalOrientation capture)
                keystroke "i" using command down
                delay 0.3

                -- Resize the document window
                set size of window 1 to {\(windowWidth), 800}

                -- Position: x = display left + 280, y = macOS-style centered
                set actualSize to size of window 1
                set actualHeight to item 2 of actualSize
                set position of window 1 to {\(screen.originX + 280), \(screen.originY) + \(screen.menuBarHeight) + (\(screen.availableHeight) - actualHeight) / 3}
                delay 0.3
            end tell
        end tell
        """)

    print("    [6a/7] Opening Find & Replace...")
    try runAppleScript("""
        tell application "System Events"
            tell process "CotEditor"
                keystroke "f" using command down
                delay 0.8
            end tell
        end tell
        """)

    print("    [6b/7] Positioning Find window...")
    try runAppleScript("""
        tell application "System Events"
            tell process "CotEditor"
                set position of window 1 to {\(screen.originX + 780), \(screen.originY + 400)}
                delay 0.3
            end tell
        end tell
        """)

    print("    [6c/7] Deselecting text field...")
    try runAppleScript("""
        tell application "System Events"
            tell process "CotEditor"
                key code 124
                delay 0.3
            end tell
        end tell
        """)

    print("    [6d/7] Find All...")
    try runAppleScript("""
        tell application "System Events"
            tell process "CotEditor"
                keystroke "F" using {command down, shift down}
                delay 1
            end tell
        end tell
        """)

    print("    [7/7] Taking screenshot...")
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
        // Also match by locale code.
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
        // At least reset the language override.
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
