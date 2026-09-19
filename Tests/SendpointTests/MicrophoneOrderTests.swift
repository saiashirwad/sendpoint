import XCTest
@testable import Sendpoint

final class MicrophoneOrderTests: XCTestCase {
    private let builtIn = AudioInputDevice(
        id: 41, uid: "BuiltInMicrophoneDevice", name: "MacBook Pro Microphone", transport: .builtIn
    )
    private let usb = AudioInputDevice(id: 77, uid: "AppleUSBAudioEngine:Yeti", name: "Yeti", transport: .other)
    private let phone = AudioInputDevice(id: 80, uid: "iPhone", name: "iPhone Microphone", transport: .other)
    private let airPods = AudioInputDevice(id: 93, uid: "AA-BB:input", name: "AirPods Pro", transport: .bluetooth)

    private func order(_ devices: [AudioInputDevice], systemDefault: AudioInputDevice? = nil) -> MicrophoneOrder {
        var order = MicrophoneOrder()
        order.absorb(devices, systemDefault: systemDefault)
        return order
    }

    func testFirstSeedPutsTheSystemDefaultFirstAndBluetoothLast() {
        let seeded = order([airPods, phone, usb, builtIn], systemDefault: usb)
        XCTAssertEqual(seeded.entries.map(\.uid), [usb.uid, builtIn.uid, phone.uid, airPods.uid])

        let bluetoothDefault = order([airPods, usb, builtIn], systemDefault: airPods)
        XCTAssertEqual(bluetoothDefault.entries.map(\.uid), [builtIn.uid, usb.uid, airPods.uid],
            "a Bluetooth system default still starts last")
    }

    func testNewMicrophonesJoinAtTheBottomAndKnownOnesKeepTheirRank() {
        var ranked = order([usb, builtIn], systemDefault: usb)
        ranked.absorb([airPods, phone, builtIn], systemDefault: phone)
        XCTAssertEqual(ranked.entries.map(\.uid), [usb.uid, builtIn.uid, phone.uid, airPods.uid])

        let renamed = AudioInputDevice(id: 77, uid: usb.uid, name: "Desk mic", transport: .other)
        ranked.absorb([renamed], systemDefault: nil)
        XCTAssertEqual(ranked.entries.first?.name, "Desk mic")

        let settled = ranked
        ranked.absorb([renamed, builtIn], systemDefault: airPods)
        XCTAssertEqual(ranked, settled, "absorbing known microphones changes nothing")
    }

    func testTheFirstEnabledConnectedMicrophoneIsUsed() {
        var ranked = order([usb, builtIn, airPods], systemDefault: usb)
        XCTAssertEqual(ranked.active(among: [airPods, builtIn, usb], systemDefault: airPods), usb)
        XCTAssertEqual(ranked.active(among: [airPods, builtIn], systemDefault: airPods), builtIn,
            "an unplugged microphone is passed over without losing its rank")

        ranked.setEnabled(false, uid: airPods.uid)
        XCTAssertNil(ranked.active(among: [airPods], systemDefault: airPods),
            "a switched-off microphone is never a fallback")

        ranked.move(uid: builtIn.uid, toIndex: 0)
        XCTAssertEqual(ranked.active(among: [airPods, builtIn, usb], systemDefault: usb), builtIn)
    }

    func testUnknownMicrophonesRankBelowKnownOnesBeforeTheyAreSaved() {
        let ranked = order([builtIn], systemDefault: builtIn)
        XCTAssertEqual(ranked.active(among: [airPods, builtIn], systemDefault: airPods), builtIn)
        XCTAssertEqual(ranked.active(among: [airPods, usb], systemDefault: airPods), usb)
        XCTAssertEqual(MicrophoneOrder().active(among: [airPods, builtIn, usb], systemDefault: usb), usb)
    }

    func testMovesClampAndIgnoreUnknownMicrophones() {
        var ranked = order([usb, builtIn, airPods], systemDefault: usb)
        ranked.move(uid: usb.uid, toIndex: 9)
        XCTAssertEqual(ranked.entries.map(\.uid), [builtIn.uid, airPods.uid, usb.uid])
        ranked.move(uid: airPods.uid, toIndex: -4)
        XCTAssertEqual(ranked.entries.map(\.uid), [airPods.uid, builtIn.uid, usb.uid])

        ranked.forget(uid: usb.uid)
        XCTAssertEqual(ranked.entries.map(\.uid), [airPods.uid, builtIn.uid])
        ranked.absorb([usb], systemDefault: usb)
        XCTAssertEqual(ranked.entries.last?.uid, usb.uid, "a forgotten microphone comes back as a new one")

        let settled = ranked
        ranked.move(uid: "missing", toIndex: 0)
        ranked.setEnabled(false, uid: "missing")
        XCTAssertEqual(ranked, settled)
    }

    func testListMarksTheLiveRowAndExplainsWhenNothingCanRecord() {
        var ranked = order([usb, builtIn, airPods], systemDefault: usb)
        ranked.setEnabled(false, uid: airPods.uid)

        let away = MicrophoneListFacts(order: ranked, devices: [builtIn, airPods], systemDefault: airPods)
        XCTAssertEqual(away.rows.map(\.name), ["Yeti", "MacBook Pro Microphone"])
        XCTAssertEqual(away.rows.map(\.status), ["Not connected", "In use"])
        XCTAssertEqual(away.tucked.map(\.name), ["AirPods Pro"])
        XCTAssertEqual(MicrophoneListFacts.tuckedLabel(count: away.tucked.count), "1 switched off")
        XCTAssertNil(away.footnote)

        let stranded = MicrophoneListFacts(order: ranked, devices: [airPods], systemDefault: airPods)
        XCTAssertFalse(stranded.rows.contains(where: \.isActive))
        XCTAssertEqual(stranded.footnote, MicrophoneListFacts.nothingUsable)

        let fresh = MicrophoneListFacts(order: MicrophoneOrder(), devices: [airPods, builtIn], systemDefault: airPods)
        XCTAssertEqual(fresh.rows.map(\.name), ["MacBook Pro Microphone", "AirPods Pro"],
            "microphones show up before the order is saved")
    }

    func testSwitchedOffMicrophonesSinkBelowTheRankedOnes() {
        var ranked = order([usb, builtIn, phone, airPods], systemDefault: usb)
        ranked.setEnabled(false, uid: builtIn.uid)
        ranked.setEnabled(false, uid: builtIn.uid)
        XCTAssertEqual(ranked.entries.map(\.uid), [usb.uid, phone.uid, airPods.uid, builtIn.uid])

        ranked.move(uid: usb.uid, toIndex: 9)
        XCTAssertEqual(ranked.entries.map(\.uid), [phone.uid, airPods.uid, usb.uid, builtIn.uid],
            "a drag never lands among the switched-off microphones")
        ranked.move(uid: builtIn.uid, toIndex: 0)
        XCTAssertEqual(ranked.entries.last?.uid, builtIn.uid, "a switched-off microphone has no rank to change")

        let yeti = AudioInputDevice(id: 5, uid: "new", name: "New", transport: .other)
        ranked.absorb([yeti], systemDefault: nil)
        XCTAssertEqual(ranked.entries.map(\.uid), [phone.uid, airPods.uid, usb.uid, "new", builtIn.uid])

        ranked.setEnabled(true, uid: builtIn.uid)
        XCTAssertEqual(ranked.entries.map(\.uid), [phone.uid, airPods.uid, usb.uid, "new", builtIn.uid])
        XCTAssertTrue(ranked.entries.allSatisfy(\.isEnabled))
    }

    func testDropIndexFollowsTheDragAndStaysInBounds() {
        func drop(_ origin: Int, _ translation: CGFloat) -> Int {
            MicrophoneListFacts.dropIndex(from: origin, translation: translation, rowHeight: 44, count: 4)
        }
        XCTAssertEqual(drop(1, 10), 1)
        XCTAssertEqual(drop(1, 30), 2)
        XCTAssertEqual(drop(1, -30), 0)
        XCTAssertEqual(drop(0, 900), 3)
        XCTAssertEqual(drop(3, -900), 0)
    }
}
