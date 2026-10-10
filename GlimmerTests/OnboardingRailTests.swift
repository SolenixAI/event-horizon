import Testing
@testable import Glimmer

@MainActor
private struct FakeOSSource: OnboardingOSSource {
    var grant: NotificationGrant = .notAsked
    var inputAccess: InputAccess = .unknown
    var accessibilityTrusted = false
    var accessibilityAsked = false
    var dualSenseConnected = false
    var helper: HelperRegistration = .notRegistered
    var buildSigned = true
    var loginItem: HelperRegistration = .notRegistered

    func notificationGrant() async -> NotificationGrant { grant }
}

@MainActor
struct OnboardingRailTests {

    @Test func notificationsMapEachGrant() {
        #expect(OnboardingRail.notifications(.notAsked) == .waiting)
        #expect(OnboardingRail.notifications(.allowed) == .allowed)
        #expect(OnboardingRail.notifications(.denied) == .off)
    }

    @Test func controllerButtonsMapEachAccess() {
        #expect(OnboardingRail.controllerButtons(.unknown) == .waiting)
        #expect(OnboardingRail.controllerButtons(.granted) == .allowed)
        #expect(OnboardingRail.controllerButtons(.denied) == .off)
    }

    @Test func volumeKeysReadOffOnlyAfterTheCardAsked() {
        #expect(OnboardingRail.volumeKeys(trusted: true, asked: false) == .allowed)
        #expect(OnboardingRail.volumeKeys(trusted: false, asked: false) == .waiting)
        #expect(OnboardingRail.volumeKeys(trusted: false, asked: true) == .off)
    }

    @Test func wifiHelperNeedsASignedBuildAndMapsRegistration() {
        #expect(OnboardingRail.wifiHelper(.enabled, signed: false) == .notInThisBuild)
        #expect(OnboardingRail.wifiHelper(.enabled, signed: true) == .allowed)
        #expect(OnboardingRail.wifiHelper(.requiresApproval, signed: true) == .needsApproval)
        #expect(OnboardingRail.wifiHelper(.notRegistered, signed: true) == .off)
        #expect(OnboardingRail.wifiHelper(.unavailable, signed: true) == .off)
    }

    @Test func readsEachItemFromTheSourceOnEveryCall() async {
        var source = FakeOSSource(grant: .notAsked)
        let first = await OnboardingRail.read(source)
        #expect(first[.notifications] == .waiting)

        source.grant = .allowed
        let second = await OnboardingRail.read(source)
        #expect(second[.notifications] == .allowed)
    }

    @Test func controllerButtonsAppearOnlyWithADualSense() async {
        var source = FakeOSSource()
        #expect(await OnboardingRail.read(source)[.controllerButtons] == nil)

        source.dualSenseConnected = true
        source.inputAccess = .denied
        #expect(await OnboardingRail.read(source)[.controllerButtons] == .off)
    }

    @Test func everyItemHasAReadOnAFreshSource() async {
        let states = await OnboardingRail.read(FakeOSSource(helper: .enabled))
        #expect(states[.notifications] == .waiting)
        #expect(states[.volumeKeys] == .waiting)
        #expect(states[.wifiHelper] == .allowed)
        #expect(states[.controllerButtons] == nil)
        #expect(states[.openAtLogin] == .off)
        #expect(OnboardingItem.allCases.count == 5)
    }

    @Test func openAtLoginFollowsItsRegistration() {
        #expect(OnboardingRail.openAtLogin(.enabled) == .allowed)
        #expect(OnboardingRail.openAtLogin(.requiresApproval) == .needsApproval)
        #expect(OnboardingRail.openAtLogin(.notRegistered) == .off)
        #expect(OnboardingRail.openAtLogin(.unavailable) == .off)
    }

    @Test func labelsMatchTheFiveStates() {
        #expect(OnboardingItemState.allowed.label == "Allowed")
        #expect(OnboardingItemState.waiting.label == "Waiting")
        #expect(OnboardingItemState.off.label == "Off")
        #expect(OnboardingItemState.needsApproval.label == "Needs approval")
        #expect(OnboardingItemState.notInThisBuild.label == "Not in this build")
    }
}
