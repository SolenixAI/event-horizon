import Testing
@testable import Glimmer

struct OnboardingFlowTests {

    @Test func startsOnWelcomeAndContinuesToFind() {
        var flow = OnboardingFlow()
        #expect(flow.step == .welcome)
        flow.continueTapped()
        #expect(flow.step == .findPC)
    }

    @Test func findHoldsUntilAPCIsChosen() {
        var flow = OnboardingFlow()
        flow.continueTapped()
        flow.continueTapped()
        #expect(flow.step == .findPC)
    }

    @Test func choosingAPCMovesToPairWithoutPairingYet() {
        var flow = OnboardingFlow()
        flow.continueTapped()
        flow.choosePC()
        #expect(flow.step == .pair)
        #expect(flow.pcPaired == false)
    }

    @Test func pairHoldsUntilThePCPaired() {
        var flow = OnboardingFlow()
        flow.continueTapped()
        flow.choosePC()
        flow.continueTapped()
        #expect(flow.step == .pair)
        flow.pairingSucceeded()
        flow.continueTapped()
        #expect(flow.step == .controls)
    }

    @Test func controlsContinueToReadyAndReadyIsTerminal() {
        var flow = OnboardingFlow()
        flow.continueTapped()
        flow.choosePC()
        flow.pairingSucceeded()
        flow.continueTapped()
        flow.continueTapped()
        #expect(flow.step == .ready)
        flow.continueTapped()
        #expect(flow.step == .ready)
    }

    @Test func backFromPairReturnsToFindAndForgetsThePairing() {
        var flow = OnboardingFlow()
        flow.continueTapped()
        flow.choosePC()
        flow.pairingSucceeded()
        flow.back()
        #expect(flow.step == .findPC)
        #expect(flow.pcPaired == false)
        flow.back()
        #expect(flow.step == .welcome)
    }

    @Test func pairingSignalIgnoredOutsidePairScreen() {
        var flow = OnboardingFlow()
        flow.pairingSucceeded()
        #expect(flow.pcPaired == false)
    }

    @Test func gateShowsTheFlowOnlyForAFreshInstallOrWhenForced() {
        #expect(OnboardingGate.showsFlow(forced: false, completed: false, hasPCs: false))
        #expect(OnboardingGate.showsFlow(forced: false, completed: true, hasPCs: false) == false)
        #expect(OnboardingGate.showsFlow(forced: false, completed: false, hasPCs: true) == false)
        #expect(OnboardingGate.showsFlow(forced: true, completed: true, hasPCs: true))
    }

    @Test func existingPCsCountAsCompletedAfterLaunch() {
        #expect(OnboardingGate.completedAfterLaunch(completed: false, hasPCs: true))
        #expect(OnboardingGate.completedAfterLaunch(completed: false, hasPCs: false) == false)
        #expect(OnboardingGate.completedAfterLaunch(completed: true, hasPCs: false))
    }

    @Test func wifiOfferWaitsForTheFlowAndASignedBuild() {
        #expect(OnboardingGate.showsWiFiOffer(completed: true, promptWanted: true, buildSigned: true))
        #expect(OnboardingGate.showsWiFiOffer(completed: false, promptWanted: true, buildSigned: true) == false)
        #expect(OnboardingGate.showsWiFiOffer(completed: true, promptWanted: true, buildSigned: false) == false)
        #expect(OnboardingGate.showsWiFiOffer(completed: true, promptWanted: false, buildSigned: true) == false)
    }
}
