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


// MARK: - Shell & AppleScript Helpers

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


// MARK: - CotEditor Defaults

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


/// Writes multiple CotEditor defaults values at once.
///
/// - Parameter defaults: A dictionary of key-value pairs with type flags (e.g. `["key": ("-bool", "true")]`).
func setCotEditorDefaults(_ defaults: [(key: String, type: String, value: String)]) throws {

    for d in defaults {
        try shell("/usr/bin/defaults", arguments: ["write", bundleID, d.key, d.type, d.value])
    }
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


/// Sets the toolbar visibility for a given toolbar configuration.
///
/// - Parameters:
///   - toolbar: The toolbar configuration name (e.g. "Document", "DirectoryDocument").
///   - visible: Whether the toolbar should be visible.
func setCotEditorToolbarVisible(_ toolbar: String, visible: Bool) throws {

    try shell("/usr/bin/defaults", arguments: ["write", bundleID,
        "NSToolbar Configuration \(toolbar)", "-dict-add", "TB Is Shown", "-bool", visible ? "true" : "false"])
}


/// Flushes CotEditor defaults by reading back a key.
func flushCotEditorDefaults() throws {

    _ = try shell("/usr/bin/defaults", arguments: ["read", bundleID, "defaultTheme"])
    wait(0.3)
}


// MARK: - CotEditor Launch & Quit

/// Launches CotEditor, closes other windows, opens the specified file(s), and hides other applications.
///
/// - Parameters:
///   - files: The file paths to open. Pass an empty array to launch without files.
///   - setupDocument: An optional AppleScript block to run inside `tell front document` after opening.
func launchCotEditor(files: [String] = [], setupDocument: String? = nil) throws {

    // Launch CotEditor (with the first file if any).
    if let first = files.first {
        try shell("/usr/bin/open", arguments: ["-a", "CotEditor", first])
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

    // Close all windows and re-open files in order.
    var openScript = ""
    for file in files {
        openScript += """
                open POSIX file "\(file)"

        """
    }
    if let setupDocument {
        openScript += """
                tell front document
                    \(setupDocument)
                end tell
        """
    }
    try runAppleScript("""
        tell application "CotEditor"
            close every window without saving
            \(openScript)
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


/// Quits CotEditor and waits for the process to fully exit.
func quitCotEditor() throws {

    try runAppleScript("""
        tell application "CotEditor" to quit
        """)

    try runAppleScript("""
        tell application "System Events"
            repeat 30 times
                if not (exists process "CotEditor") then exit repeat
                delay 0.2
            end repeat
        end tell
        """)
}


// MARK: - Screen & Window Layout

/// Screen layout information for the built-in display in screen coordinates (top-left origin).
struct ScreenInfo {

    var originX: Int
    var originY: Int
    var width: Int
    var menuBarHeight: Int
    var availableHeight: Int
}


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


/// Generates an AppleScript snippet that resizes and positions a window with macOS-style vertical centering (top:bottom = 1:2).
///
/// - Parameters:
///   - window: The window specifier (e.g. "window 1", "window 2").
///   - width: The desired window width.
///   - height: The desired window height.
///   - x: The x position relative to the display origin, or `nil` to center horizontally.
///   - screen: The screen layout information.
/// - Returns: An AppleScript snippet to resize and position the window.
func windowLayoutScript(window: String = "window 1", width: Int, height: Int, x: Int? = nil, screen: ScreenInfo) -> String {

    let xExpr: String
    if let x {
        xExpr = "\(screen.originX + x)"
    } else {
        xExpr = "\(screen.originX) + (\(screen.width) - actualWidth) / 2"
    }

    return """
                    set size of \(window) to {\(width), \(height)}
                    set actualSize to size of \(window)
                    set actualWidth to item 1 of actualSize
                    set actualHeight to item 2 of actualSize
                    set position of \(window) to {\(xExpr), \(screen.originY) + \(screen.menuBarHeight) + (\(screen.availableHeight) - actualHeight) / 3}
    """
}


// MARK: - Screenshot Capture & Post-processing

/// Captures the virtual screen area (1440x900) of the built-in display to the specified path.
///
/// - Parameter path: The output file path.
func captureScreen(to path: String) throws {

    let bounds = builtInScreenBounds()
    let rect = "\(Int(bounds.origin.x)),\(Int(bounds.origin.y)),\(virtualScreenWidth),\(virtualScreenHeight)"
    try shell("/usr/sbin/screencapture", arguments: ["-x", "-R", rect, path])
}


/// Hides the system status items in the menu bar by overwriting the top-right area
/// with a clean strip sampled from the screenshot's own menu bar.
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

    // Crop a 1px-wide strip from the left edge of the menu bar (no window shadows there).
    let stripRect = CGRect(x: 0, y: 0, width: 1, height: overlayH)
    guard let strip = screenshotCG.cropping(to: stripRect) else {
        print("    Warning: Could not crop menu bar strip")
        return
    }

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

    guard let resultCG = ctx.makeImage() else { return }
    let resultRep = NSBitmapImageRep(cgImage: resultCG)
    guard let pngData = resultRep.representation(using: .png, properties: [:]) else { return }
    try pngData.write(to: screenshotURL)
}


/// Takes a screenshot, overlays the menu bar, and saves it to the specified path.
///
/// - Parameter outputPath: The destination file path.
func takeScreenshot(to outputPath: String) throws {

    let tempFile = NSTemporaryDirectory() + "screenshot_temp.png"
    try captureScreen(to: tempFile)
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

        \(windowLayoutScript(width: 700, height: 780, screen: screen))
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
    try setCotEditorDefaults([
        (key: "defaultTheme", type: "-string", value: "Resinifictrix"),
        (key: "highlightCurrentLine", type: "-bool", value: "false"),
        (key: "showStatusArea", type: "-bool", value: "false"),
        (key: "selectedInspectorPaneIndex", type: "-int", value: "1"),
    ])
    try setCotEditorFont(name: "Klee", size: 13)
    try flushCotEditorDefaults()

    try launchCotEditor(files: [demoFile], setupDocument: "set range of selection to {100, 0}")

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

        \(windowLayoutScript(width: 1000, height: 700, screen: screen))
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

    try setCotEditorLanguage(language.localeCode)
    try setCotEditorDefaults([
        (key: "defaultTheme", type: "-string", value: "Anura"),
        (key: "showStatusArea", type: "-bool", value: "true"),
        (key: "findUsesRegularExpression", type: "-bool", value: "true"),
    ])
    try setCotEditorFont(name: "Menlo", size: 13)
    try setCotEditorToolbarVisible("Document", visible: true)

    // Set Find panel width.
    let bounds = builtInScreenBounds()
    try shell("/usr/bin/defaults", arguments: ["write", bundleID, "NSWindow Frame Find Panel",
        "0 0 540 227 \(Int(bounds.origin.x)) \(Int(bounds.origin.y)) \(Int(bounds.width)) \(Int(bounds.height))"])

    // Set the find pasteboard.
    let findPasteboard = NSPasteboard(name: .find)
    findPasteboard.clearContents()
    findPasteboard.setString(#"stroke-width="(\d+)""#, forType: .string)

    try flushCotEditorDefaults()
    try launchCotEditor(files: [demoFile])

    let screen = builtInScreenInfo()

    // Close inspector and position the document window.
    try runAppleScript("""
        tell application "System Events"
            tell process "CotEditor"
                set frontmost to true
                delay 0.3

                -- Close inspector (opened by previous VerticalOrientation capture)
                keystroke "i" using command down
                delay 0.3

        \(windowLayoutScript(width: 700, height: 780, x: 280, screen: screen))
                delay 0.3
            end tell
        end tell
        """)

    // Open Find & Replace, position it, and find all.
    try runAppleScript("""
        tell application "System Events"
            tell process "CotEditor"
                keystroke "f" using command down
                delay 0.8

                set position of window 1 to {\(screen.originX + 780), \(screen.originY + 400)}
                delay 0.3

                key code 124
                delay 0.3

                keystroke "F" using {command down, shift down}
                delay 1
            end tell
        end tell
        """)

    try takeScreenshot(to: outputPath)
    try quitCotEditor()

    print("  ✓ Saved: \(outputPath)")
}


/// Captures the Dark mode screenshot with two overlapping document windows.
///
/// - Parameters:
///   - language: The language for which to capture.
///   - demoFileFront: The path to the front (editor.svg) demo file.
///   - demoFileBack: The path to the back (svg.svg) demo file.
///   - outputPath: The path to save the screenshot.
func captureDark(language: Language, demoFileFront: String, demoFileBack: String, outputPath: String) throws {

    print("  Capturing Dark...")

    try setCotEditorLanguage(language.localeCode)
    try setCotEditorDefaults([
        (key: "defaultTheme", type: "-string", value: "Anura (Dark)"),
        (key: "appearance", type: "-int", value: "2"),
        (key: "windowAlpha", type: "-float", value: "0.9"),
        (key: "showStatusArea", type: "-bool", value: "true"),
    ])
    try setCotEditorFont(name: "Menlo", size: 13)
    try setCotEditorToolbarVisible("Document", visible: true)
    try flushCotEditorDefaults()

    // Open back window first, then front window (front = last opened = window 1).
    try launchCotEditor(files: [demoFileBack, demoFileFront])

    let screen = builtInScreenInfo()

    try runAppleScript("""
        tell application "System Events"
            tell process "CotEditor"
                set frontmost to true
                delay 0.3

        \(windowLayoutScript(window: "window 1", width: 700, height: 780, x: 280, screen: screen))
                delay 0.3

        \(windowLayoutScript(window: "window 2", width: 700, height: 780, x: 490, screen: screen))
                -- Shift the back window down by 40px
                set backPos to position of window 2
                set position of window 2 to {item 1 of backPos, (item 2 of backPos) + 40}
                delay 0.3
            end tell
        end tell
        """)

    try takeScreenshot(to: outputPath)
    try quitCotEditor()

    print("  ✓ Saved: \(outputPath)")
}


/// Captures the Features screenshot showing the project directory with sidebar and inspector.
///
/// - Parameters:
///   - language: The language for which to capture.
///   - projectDir: The path to the CotEditor project directory.
///   - outputPath: The path to save the screenshot.
func captureFeatures(language: Language, projectDir: String, outputPath: String) throws {

    print("  Capturing Features...")

    try setCotEditorLanguage(language.localeCode)
    try setCotEditorDefaults([
        (key: "defaultTheme", type: "-string", value: "Anura"),
        (key: "appearance", type: "-int", value: "0"),
        (key: "showStatusArea", type: "-bool", value: "true"),
        (key: "selectedInspectorPaneIndex", type: "-int", value: "0"),
    ])
    try setCotEditorFont(name: "Menlo", size: 13)
    try setCotEditorToolbarVisible("Document", visible: true)
    try setCotEditorToolbarVisible("DirectoryDocument", visible: true)
    try flushCotEditorDefaults()

    try launchCotEditor(files: [projectDir])

    let screen = builtInScreenInfo()

    // Resize and select README.md from the sidebar.
    try runAppleScript("""
        tell application "System Events"
            tell process "CotEditor"
                set frontmost to true
                delay 0.3

        \(windowLayoutScript(width: 1060, height: 780, screen: screen))
                delay 0.3

                -- Focus the sidebar (Ctrl+Cmd+S) and type-select README.md
                keystroke "s" using {control down, command down}
                delay 0.3
                keystroke "R"
                delay 0.5
            end tell
        end tell
        """)

    // Select character at position 630 (length 1).
    try runAppleScript("""
        tell application "CotEditor"
            tell front document
                set range of selection to {630, 1}
            end tell
        end tell
        """)
    wait(0.3)

    // Re-open sidebar, focus editor, then show inspector.
    try runAppleScript("""
        tell application "System Events"
            tell process "CotEditor"
                keystroke "s" using {control down, command down}
                delay 0.3

                keystroke "`" using control down
                delay 0.3

                keystroke "i" using {command down, option down}
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

func cleanup() {

    print("")
    print("Cleaning up...")

    do { try quitCotEditor() } catch {}

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

signal(SIGINT) { _ in
    cleanup()
    exit(1)
}

let demoFileVertical = screenshotsDir + "/_demo files/銀河鉄道の夜.md"
let demoFileEditor = screenshotsDir + "/_demo files/editor.svg"
let demoFileSvg = screenshotsDir + "/_demo files/svg.svg"
let projectDir = screenshotsDir + "/../../CotEditor"

do {
    print("Saving CotEditor defaults...")
    defaultsBackupPath = try saveCotEditorDefaults()

    print("Hiding desktop files...")
    tempDesktopDir = try hideDesktopFiles()

    print("Setting desktop background...")
    try setAllDesktopBackgrounds(path: backgroundPath)

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
        try captureDark(language: language, demoFileFront: demoFileEditor, demoFileBack: demoFileSvg, outputPath: outputDir + "/Dark@2x.png")
        try captureFeatures(language: language, projectDir: projectDir, outputPath: outputDir + "/Features@2x.png")
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
