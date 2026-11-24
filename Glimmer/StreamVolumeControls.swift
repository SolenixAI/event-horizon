//
//  StreamVolumeControls.swift
//
//  The stream's own level: a slider row with a mute button, in Home's popover and the menu bar.
//

import SwiftUI

/// Home's speaker control in the status row: a glass circle that opens the level.
struct StreamVolumeButton: View {
    var host: Host?
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
                if let host {
                    pcAudioSection(for: host)
                }
            }
            .padding(14)
            .frame(width: 280)
            .task(id: isOpen) {
                if isOpen, let host {
                    await model.refreshAudioDevices(for: host)
                }
            }
        }
    }

    @ViewBuilder
    private func pcAudioSection(for host: Host) -> some View {
        let devices = model.audioDevices(for: host)
        if !devices.isEmpty {
            Divider()
                .padding(.vertical, 2)
            Text("PC Audio Output")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                ForEach(devices) { device in
                    pcAudioRow(device: device, host: host)
                }
            }
        }
    }

    private func pcAudioRow(device: HostAudioDevice, host: Host) -> some View {
        let isActive = device.id == model.activeAudioDevice(for: host)?.id
        return Button {
            Task { _ = await model.selectAudioDevice(host: host, deviceId: device.id) }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: device.isVirtual ? "laptopcomputer" : "speaker.wave.2")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .frame(width: 14)
                Text(device.name)
                    .font(.callout)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 4)
                if isActive {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.horizonBlue)
                }
            }
            .padding(.vertical, 4)
            .padding(.horizontal, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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
