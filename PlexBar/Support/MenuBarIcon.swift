import AppKit

@MainActor
enum MenuBarIcon {
    static let image: NSImage = {
        guard let image = Bundle.main.image(forResource: "MenuBarIcon") else {
            preconditionFailure("The menu-bar icon is missing from the application bundle")
        }

        image.isTemplate = true
        return image
    }()
}
