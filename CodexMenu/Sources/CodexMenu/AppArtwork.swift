import AppKit

/// Share the bundled app artwork across the menu-bar entry and settings header.
enum AppArtwork {
    static let icon: NSImage? = {
        guard let url = Bundle.main.url(forResource: "AppIcon", withExtension: "icns") else { return nil }
        return NSImage(contentsOf: url)
    }()

    private static let menuIcon: NSImage? = {
        guard let image = icon?.copy() as? NSImage else { return nil }
        image.size = NSSize(width: 20, height: 20)
        image.isTemplate = false
        return image
    }()

    static func controlIcon(hasReadError: Bool) -> NSImage? {
        if hasReadError {
            return NSImage(systemSymbolName: "exclamationmark.triangle", accessibilityDescription: nil)
        }
        // A source-only command-line run may not have an app bundle yet.
        return menuIcon ?? NSImage(systemSymbolName: "rectangle.3.group", accessibilityDescription: nil)
    }
}
