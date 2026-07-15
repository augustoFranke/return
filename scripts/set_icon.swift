#!/usr/bin/env swift
import AppKit

let arguments = CommandLine.arguments
guard arguments.count == 5, arguments[1] == "--icon", arguments[3] == "--target" else {
    fputs("Usage: set_icon.swift --icon <path.icns> --target <path>\n", stderr)
    exit(1)
}

let iconPath = arguments[2]
let targetPath = arguments[4]

guard FileManager.default.fileExists(atPath: iconPath),
      FileManager.default.fileExists(atPath: targetPath),
      let icon = NSImage(contentsOfFile: iconPath) else {
    fputs("Failed to load icon or target path\n", stderr)
    exit(1)
}

let success = NSWorkspace.shared.setIcon(icon, forFile: targetPath, options: [])
if success {
    print("Set icon on \(targetPath)")
} else {
    fputs("Failed to set icon on \(targetPath)\n", stderr)
    exit(1)
}