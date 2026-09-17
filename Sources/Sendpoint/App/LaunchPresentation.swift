import AppKit

/// What a process start or reopen should put on screen.
enum LaunchPresentation: Equatable {
    case setup
    case settings
    case none

    /// Posted by a second copy so the running instance can show a window.
    static let userOpenedNotification = Notification.Name("app.sendpoint.userOpened")

    static func decide(hasCompletedSetup: Bool, kind: Kind) -> LaunchPresentation {
        if !hasCompletedSetup { return .setup }
        switch kind {
        case .login: return .none
        case .userOpen: return .settings
        }
    }

    /// `exit` follows immediately; without `deliverImmediately` the post is lost.
    static func notifyRunningInstance(bundleIdentifier: String) {
        DistributedNotificationCenter.default().postNotificationName(
            userOpenedNotification,
            object: bundleIdentifier,
            userInfo: nil,
            deliverImmediately: true
        )
    }

    enum Kind: Equatable {
        case login
        case userOpen

        static let openApplicationEventID: AEEventID = 0x6F617070 // 'oapp'
        static let propDataKeyword: AEKeyword = 0x70726474 // 'prdt'
        static let launchedAsLoginItem: OSType = 0x6C676974 // 'lgit'

        static func from(eventID: AEEventID?, loginItemProperty: OSType?) -> Kind {
            if eventID == openApplicationEventID, loginItemProperty == launchedAsLoginItem {
                return .login
            }
            return .userOpen
        }

        /// Only valid during `applicationDidFinishLaunching`.
        static func fromCurrentAppleEvent(
            _ event: NSAppleEventDescriptor? = NSAppleEventManager.shared().currentAppleEvent
        ) -> Kind {
            from(
                eventID: event?.eventID,
                loginItemProperty: event?.paramDescriptor(forKeyword: propDataKeyword)?.enumCodeValue
            )
        }
    }
}
