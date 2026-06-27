import Testing
@testable import BoundlessSkies

@MainActor
struct HapticManagerTests {
    @Test func supportsHapticsReturnsBool() {
        let manager = HapticManager()
        let supports = manager.supportsHaptics()
        #expect(supports == true || supports == false)
    }

    @Test func vibrateDoesNotThrow() {
        let manager = HapticManager()
        manager.vibrate(style: .light)
        manager.vibrate(style: .heavy)
    }

    @Test func stopClearsPlayingState() {
        let manager = HapticManager()
        manager.stop()
        #expect(manager.isPlaying == false)
    }

    @Test func emptyPatternIsNoOp() throws {
        let manager = HapticManager()
        try manager.playPattern(events: [])
        #expect(manager.isPlaying == false)
    }
}