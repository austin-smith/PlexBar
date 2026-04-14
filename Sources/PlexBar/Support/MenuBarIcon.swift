import AppKit

@MainActor
enum MenuBarIcon {
    static let image: NSImage = {
        let image = NSImage(size: NSSize(width: 16, height: 16))

        for resourceName in ["MenuBarIcon.png", "MenuBarIcon@2x.png"] {
            guard let url = Bundle.module.url(forResource: resourceName, withExtension: nil),
                  let data = try? Data(contentsOf: url),
                  let representation = NSBitmapImageRep(data: data)
            else {
                continue
            }

            if resourceName.contains("@2x") {
                representation.size = NSSize(
                    width: CGFloat(representation.pixelsWide) / 2,
                    height: CGFloat(representation.pixelsHigh) / 2
                )
            } else {
                representation.size = NSSize(
                    width: CGFloat(representation.pixelsWide),
                    height: CGFloat(representation.pixelsHigh)
                )
            }

            image.addRepresentation(representation)
        }

        image.isTemplate = true
        return image
    }()
}
