import AppKit
import Darwin
import Foundation

let args = Array(CommandLine.arguments.dropFirst())
guard args.count == 5, let parentPID = Int32(args[3]), parentPID > 0 else {
    exit(64)
}

let newApp = URL(fileURLWithPath: args[1], isDirectory: true).standardizedFileURL
let currentApp = URL(fileURLWithPath: args[2], isDirectory: true).standardizedFileURL
let cleanupDirectory = URL(fileURLWithPath: args[4], isDirectory: true).standardizedFileURL
let temporaryDirectory = FileManager.default.temporaryDirectory.standardizedFileURL
let helperURL = URL(fileURLWithPath: CommandLine.arguments[0]).standardizedFileURL

guard cleanupDirectory.path.hasPrefix(temporaryDirectory.path + "/"),
      helperURL.path.hasPrefix(temporaryDirectory.path + "/") else {
    exit(64)
}

defer { try? FileManager.default.removeItem(at: cleanupDirectory) }

while kill(parentPID, 0) == 0 || errno == EPERM {
    Thread.sleep(forTimeInterval: 0.2)
}

do {
    let fileManager = FileManager.default
    let backupName = ".\(currentApp.lastPathComponent).update-backup"
    _ = try fileManager.replaceItemAt(currentApp, withItemAt: newApp, backupItemName: backupName, options: [])
    try? fileManager.removeItem(at: currentApp.deletingLastPathComponent().appendingPathComponent(backupName))
    NSWorkspace.shared.open(currentApp)
    exit(0)
} catch {
    exit(1)
}
