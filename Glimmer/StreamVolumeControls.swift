//
//  StreamVolumeControls.swift
//
//  The stream's own level: a slider row with a mute button, in Home's popover and the menu bar.
//

import SwiftUI

/// Home's speaker control in the status row: a glass circle that opens the level.
struct StreamVolumeButton: View {
    @Environment(AppModel.self) private var model
    @State private var isOpen = false

    var body: some View {
        Button { isOpen.toggle() } label: {
            Image(systemName: model.streamVolume.symbol)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 22, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Stream volume")
        .accessibilityLabel("Stream volume")
        .accessibilityValue(model.streamVolume.spokenLevel)
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: model.streamVolume.stepUp()
            case .decrement: model.streamVolume.stepDown()
            @unknown default: break
            }
        }
        .popover(isPresented: $isOpen, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Stream volume")
                    .font(.headline)
                    .accessibilityHidden(true)
                StreamVolumeSlider()
            }
            .padding(14)
            .frame(width: 260)
        }
    }
}

/// The stream's level: a mute button and a slider. The same row in Home's popover and the menu bar.
struct StreamVolumeSlider: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(spacing: 10) {
            Button { model.streamVolume.toggleMute() } label: {
                Image(systemName: model.streamVolume.symbol)
                    .frame(width: 18)
            }
            .buttonStyle(.borderless)
            .help(model.streamVolume.isMuted ? "Unmute the stream" : "Mute the stream")
            .accessibilityLabel(model.streamVolume.isMuted ? "Unmute stream" : "Mute stream")
            Slider(value: levelBinding, in: 0...1, step: StreamVolume.step)
                .accessibilityLabel("Level")
                .accessibilityValue(model.streamVolume.spokenLevel)
        }
    }

    private var levelBinding: Binding<Double> {
        Binding(get: { model.streamVolume.level },
                set: { model.streamVolume.setLevel($0) })
    }
}

private extension StreamVolume {
    /// The speaker glyph for the level, and a slashed one while muted or silent.
    var symbol: String {
        if gain == 0 { return "speaker.slash" }
        switch gain {
        case ..<0.34: return "speaker.wave.1"
        case ..<0.67: return "speaker.wave.2"
        default: return "speaker.wave.3"
        }
    }

    /// What VoiceOver says for the level: a percentage, or "Muted".
    var spokenLevel: String {
        if isMuted { return "Muted" }
        return "\(Int((level * 100).rounded())) percent"
    }
}
