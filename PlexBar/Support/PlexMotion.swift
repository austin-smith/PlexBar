import SwiftUI

enum PlexMotion {
    static var surfaceTransition: AnyTransition { .opacity }

    static func surfaceAnimation(reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : .easeOut(duration: 0.2)
    }

    static func contentReplacementAnimation(reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : .easeOut(duration: 0.16)
    }
}
