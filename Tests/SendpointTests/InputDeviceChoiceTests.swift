import XCTest
@testable import Sendpoint

final class InputDeviceChoiceTests: XCTestCase {
    private let builtIn = AudioInputDevice(id: 41, uid: "BuiltInMicrophoneDevice", name: "MacBook Pro Microphone")
    private let usb = AudioInputDevice(id: 77, uid: "AppleUSBAudioEngine:Yeti", name: "Yeti")

    func testOnlyAConnectedPreferenceOverridesTheSystemDefault() {
        XCTAssertNil(InputDeviceChoice.resolve(preferredUID: nil, available: [builtIn, usb]))
        XCTAssertEqual(InputDeviceChoice.resolve(preferredUID: usb.uid, available: [builtIn, usb]), usb)
        XCTAssertNil(InputDeviceChoice.resolve(preferredUID: usb.uid, available: [builtIn]),
            "an unplugged preference falls back to the system default")
    }
}
