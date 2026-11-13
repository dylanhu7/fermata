import AppKit
import CoreGraphics

/// Tells whether the user is choosing a device in macOS's own UI, so a default change can be
/// taken as theirs instead of something to undo.
enum SystemSoundPicker {
    static func isOpen() -> Bool {
        if NSWorkspace.shared.frontmostApplication?.bundleIdentifier == "com.apple.systempreferences" {
            return true
        }
        guard let controlCenter = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.controlcenter").first,
              let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[CFString: Any]]
        else { return false }
        // Control Center's menu bar icons live in the status window layer; an open module
        // (such as Sound) sits above it. Owner and layer need no screen recording permission.
        let statusLayer = Int(CGWindowLevelForKey(.statusWindow))
        return windows.contains { window in
            window[kCGWindowOwnerPID] as? pid_t == controlCenter.processIdentifier
                && (window[kCGWindowLayer] as? Int).map { $0 != statusLayer && $0 != 0 } == true
        }
    }
}
