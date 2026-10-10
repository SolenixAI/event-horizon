//
//  OnboardingView.swift
//
//  The first-launch pass in the main window: five screens, one journey. Each
//  permission is explained before macOS asks for it.
//

import SwiftUI

struct OnboardingView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var flow: OnboardingFlow
    /// Ends the pass and marks it done. The window then shows Home.
    let finish: () -> Void

    init(start: OnboardingFlow = OnboardingFlow(), finish: @escaping () -> Void) {
        _flow = State(initialValue: start)
        self.finish = finish
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            progress
            Text(title)
                .font(.title2.bold())
                .contentTransition(.opacity)
            content
            footer
        }
        .padding(28)
        .frame(width: 520, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
        .animation(reduceMotion ? nil : .snappy(duration: 0.2), value: flow.step)
    }

    private var pcName: String { model.selectedHost?.displayName ?? "Your PC" }

    private var title: String {
        switch flow.step {
        case .welcome: "Welcome to Event Horizon"
        case .findPC: "Find your PC"
        case .pair: "Pair your PC"
        case .controls: "Set up controls and alerts"
        case .ready: "\(pcName) is ready."
        }
    }

    private var progress: some View {
        HStack(spacing: 6) {
            ForEach(OnboardingStep.allCases, id: \.self) { step in
                Capsule()
                    .fill(step.rawValue <= flow.step.rawValue ? Color.primary.opacity(0.7) : Color.primary.opacity(0.15))
                    .frame(width: 22, height: 4)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Step \(flow.step.rawValue + 1) of \(OnboardingStep.allCases.count)")
    }

    @ViewBuilder private var content: some View {
        switch flow.step {
        case .welcome:
            Text("Event Horizon shows your gaming PC in one Mac window, so you can stream its desktop or a game.")
                .font(.body)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        case .findPC, .pair:
            // One view for both screens, so the pairing state survives the step change.
            PairSheet(embedded: pairing)
        case .controls:
            ScrollView {
                PermissionRail(skippable: true)
            }
            .frame(maxHeight: 460)
        case .ready:
            Text("Stream the Desktop or a game.")
                .font(.body)
                .foregroundStyle(.secondary)
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
            HStack {
                Spacer()
                Button("Continue") { flow.continueTapped() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(StreamButtonStyle())
            }
        case .findPC, .pair:
            EmptyView()
        case .controls:
            HStack {
                Spacer()
                Button("Continue") { flow.continueTapped() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(StreamButtonStyle())
            }
        case .ready:
            HStack {
                Button("Done", action: finish)
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button(model.heroActionLabel) {
                    model.streamHeroApp()
                    finish()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(StreamButtonStyle())
            }
        }
    }
}
