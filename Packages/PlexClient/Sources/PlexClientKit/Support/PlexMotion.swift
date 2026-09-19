import SwiftUI

public enum PlexMotion {
    public static var surfaceTransition: AnyTransition { .opacity }

    public static func surfaceAnimation(reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : .easeOut(duration: 0.2)
    }

    public static func contentReplacementAnimation(reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : .easeOut(duration: 0.16)
    }
}
