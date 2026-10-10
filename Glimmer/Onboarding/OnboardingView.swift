//
//  OnboardingView.swift
//
//  The first-launch pass. The whole window is space: the stage fills it edge to
//  edge, and the words float over it in the lower left, large and quiet. Only
//  the parts a person works with (finding and pairing the PC, the permission
//  cards) sit on Liquid Glass. Each permission is explained before macOS asks.
//

import AppKit
import SwiftUI

struct OnboardingView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var flow: OnboardingFlow
    /// The optional permissions as macOS reports them now, for the stage's satellites.
    @State private var railStates: [OnboardingItem: OnboardingItemState] = [:]
    /// The words wait for the first light before they rise.
    @State private var wordsShown = false
    /// Ends the pass and marks it done. The window then shows Home.
    let finish: () -> Void

    init(start: OnboardingFlow = OnboardingFlow(), finish: @escaping () -> Void) {
        _flow = State(initialValue: start)
        self.finish = finish
    }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            OnboardingStage(step: flow.step, facts: sceneFacts, pcName: pcName)
            scrim
            if wordsShown {
                words
                    .padding(.leading, 64)
                    .padding(.bottom, 56)
                    .padding(.trailing, 32)
                    .transition(.blurReplace)
            }
        }
        .frame(minWidth: 860, minHeight: 620)
        .background(Color.black)
        .environment(\.colorScheme, .dark)
        .animation(reduceMotion ? nil : .smooth(duration: 0.7), value: flow.step)
        .task {
            await readRail()
            try? await Task.sleep(for: .milliseconds(reduceMotion ? 0 : 2000))
            withAnimation(reduceMotion ? nil : .smooth(duration: 1.2)) { wordsShown = true }
        }
        .onReceive(returned) { _ in Task { await readRail() } }
    }

    /// The rail's own reads come back on every return to the app, so the satellites do too.
    private let returned = NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)

    /// Darkens space under the words just enough to read them, and no further.
    private var scrim: some View {
        LinearGradient(stops: [.init(color: .black.opacity(0.62), location: 0),
                               .init(color: .black.opacity(0.0), location: 0.62)],
                       startPoint: .bottomLeading, endPoint: .topTrailing)
            .allowsHitTesting(false)
            .ignoresSafeArea()
            .accessibilityHidden(true)
    }

    private var words: some View {
        VStack(alignment: .leading, spacing: 22) {
            progress
            VStack(alignment: .leading, spacing: 12) {
                Text(title)
                    .font(.system(size: 46, weight: .semibold))
                    .tracking(-0.9)
                    .foregroundStyle(.white)
                    .fixedSize(horizontal: false, vertical: true)
                if let lede {
                    Text(lede)
                        .font(.system(size: 17))
                        .lineSpacing(3)
                        .foregroundStyle(.white.opacity(0.74))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .id(flow.step)
            .transition(.blurReplace)
            panel
            footer
        }
        .frame(maxWidth: 500, alignment: .leading)
    }

    private var pcName: String { model.selectedHost?.displayName ?? "Your PC" }

    private var sceneFacts: OnboardingSceneFacts {
        // One star per PC, however many saved entries point at it.
        OnboardingSceneFacts(foundPCs: Set(model.hosts.map(\.displayName)).count,
                             paired: flow.pcPaired, permissions: railStates)
    }

    private func readRail() async {
        railStates = await OnboardingRail.read(LiveOnboardingSource())
    }

    private var title: String {
        switch flow.step {
        case .welcome: "Your PC, inside your Mac."
        case .findPC: "Find your PC"
        case .pair: "Pair your PC"
        case .controls: "Finishing touches"
        case .ready: "\(pcName) is ready."
        }
    }

    private var lede: String? {
        switch flow.step {
        case .welcome:
            "Your gaming PC's desktop and games, streamed into one Mac window. Your cursor and shortcuts stay yours."
        case .findPC, .pair:
            nil
        case .controls:
            "Each one is optional and explained before macOS asks. You can change them later in Settings."
        case .ready:
            "Open its desktop or a game. Everything you set up is saved."
        }
    }

    private var progress: some View {
        HStack(spacing: 6) {
            ForEach(OnboardingStep.allCases, id: \.self) { step in
                Capsule()
                    .fill(step.rawValue <= flow.step.rawValue ? Color.white.opacity(0.85) : Color.white.opacity(0.18))
                    .frame(width: step == flow.step ? 30 : 16, height: 3)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Step \(flow.step.rawValue + 1) of \(OnboardingStep.allCases.count)")
    }

    /// The working parts, on glass over the scene. Welcome and Ready have none.
    @ViewBuilder private var panel: some View {
        switch flow.step {
        case .welcome, .ready:
            EmptyView()
        case .findPC, .pair:
            // One view for both screens, so the pairing state survives the step change.
            PairSheet(embedded: pairing)
                .padding(18)
                .glassEffect(.regular, in: .rect(cornerRadius: 24))
        case .controls:
            ScrollView {
                PermissionRail(skippable: true)
            }
            .frame(maxHeight: 320)
            .padding(18)
            .glassEffect(.regular, in: .rect(cornerRadius: 24))
        }
    }

    private var pairing: EmbeddedPairing {
        EmbeddedPairing(
            chose: { flow.choosePC() },
            paired: { flow.pairingSucceeded() },
            back: { flow.back() },
            next: { flow.continueTapped() })
    }

    @ViewBuilder private var footer: some View {
        switch flow.step {
        case .welcome:
            Button("Get started") { flow.continueTapped() }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(StreamButtonStyle())
                .controlSize(.large)
        case .findPC, .pair:
            EmptyView()
        case .controls:
            // Each card has its own Continue for macOS's prompt; this one ends setup.
            Button("Finish") { flow.continueTapped() }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(StreamButtonStyle())
                .controlSize(.large)
        case .ready:
            HStack(spacing: 12) {
                Button(model.heroActionLabel) {
                    model.streamHeroApp()
                    finish()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(StreamButtonStyle())
                .controlSize(.large)
                Button("Go to Home", action: finish)
                    .keyboardShortcut(.cancelAction)
                    .buttonStyle(.glass)
                    .controlSize(.large)
            }
        }
    }
}
