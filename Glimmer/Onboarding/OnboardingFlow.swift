//
//  OnboardingFlow.swift
//
//  The first-launch pass as a value: which of its five screens is showing and
//  what the facts allow next. The views move it; nothing here touches the OS.
//

import Foundation

enum OnboardingStep: Int, CaseIterable, Sendable {
    case welcome, findPC, pair, controls, ready
}

struct OnboardingFlow: Equatable, Sendable {
    private(set) var step: OnboardingStep = .welcome
    /// The chosen PC paired, so the Pair screen may continue.
    private(set) var pcPaired = false

    /// Welcome to Find: no prompt yet, so it always moves on.
    mutating func continueFromWelcome() {
        guard step == .welcome else { return }
        step = .findPC
    }

    /// A PC was picked on Find, which starts pairing on Pair.
    mutating func choosePC() {
        guard step == .findPC else { return }
        step = .pair
    }

    /// The Pair screen reports the PC paired. It does not move the flow by itself.
    mutating func pairingSucceeded() {
        guard step == .pair else { return }
        pcPaired = true
    }

    /// Pair to Controls, once the PC paired. Controls to Ready is always open.
    mutating func continueTapped() {
        switch step {
        case .welcome: continueFromWelcome()
        case .pair where pcPaired: step = .controls
        case .controls: step = .ready
        default: break
        }
    }

    /// Find returns to Welcome. Pair returns to Find and forgets the PC.
    mutating func back() {
        switch step {
        case .findPC: step = .welcome
        case .pair:
            step = .findPC
            pcPaired = false
        default: break
        }
    }
}

/// When the first-launch pass shows, and when the Wi-Fi helper offer shows at launch.
enum OnboardingGate {
    static let completedKey = "onboardingCompleted"
    /// Launch argument `-forceOnboarding YES`: shows the pass for screenshots and never writes the completed flag.
    static let forceKey = "forceOnboarding"

    static func showsFlow(forced: Bool, completed: Bool, hasPCs: Bool) -> Bool {
        forced || (!completed && !hasPCs)
    }

    /// Macs with a PC already paired predate the pass, so they count as done.
    static func completedAfterLaunch(completed: Bool, hasPCs: Bool) -> Bool {
        completed || hasPCs
    }

    /// The Wi-Fi offer repeats each launch until it is on or declined for good, but
    /// only once the pass is done and only on a build the helper can run in.
    static func showsWiFiOffer(completed: Bool, promptWanted: Bool, buildSigned: Bool) -> Bool {
        completed && promptWanted && buildSigned
    }
}
