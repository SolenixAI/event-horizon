//
//  StreamVolumeHUD.swift
//
//  The Mac's volume readout for the stream: a HUD-material bar in a child panel over
//  the picture. It never takes key or mouse input, so the stream's capture is untouched.
//

import AppKit
import SwiftUI

/// The glyph and sixteen segments: the Mac's own volume readout, in one line.
struct StreamVolumeHUDView: View {
    let volume: StreamVolume

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: volume.symbol)
                .font(.system(size: 15, weight: .medium))
                .frame(width: 20)
            HStack(spacing: 2) {
                ForEach(0..<StreamVolume.segmentCount, id: \.self) { index in
                    Capsule()
                        .fill(index < volume.litSegments ? Color.primary : Color.primary.opacity(0.22))
                        .frame(width: 5, height: 6)
                }
            }
        }
        .foregroundStyle(.primary)
        .padding(.horizontal, 20)
        .frame(width: 190, height: 40)
    }
}

/// A child panel that never becomes key and passes every mouse event through.
private final class HUDPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// Shows the readout over the stream window for a moment, then fades it out.
@MainActor
final class StreamVolumeHUD {
    private static let holdSeconds = 1.5
    private static let fadeSeconds = 0.25

    private let panel: HUDPanel
    private let host: NSHostingView<StreamVolumeHUDView>
    private weak var parent: NSWindow?
    private var hideTask: Task<Void, Never>?

    init(parent: NSWindow) {
        self.parent = parent
        panel = HUDPanel(contentRect: NSRect(x: 0, y: 0, width: 190, height: 40),
                         styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        panel.isReleasedWhenClosed = false
        panel.appearance = NSAppearance(named: .darkAqua)
        host = NSHostingView(rootView: StreamVolumeHUDView(volume: .full))
        let material = NSVisualEffectView(frame: NSRect(x: 0, y: 0, width: 190, height: 40))
        material.material = .hudWindow
        material.blendingMode = .behindWindow
        material.state = .active
        material.wantsLayer = true
        material.layer?.cornerRadius = 20
        host.frame = material.bounds
        host.autoresizingMask = [.width, .height]
        material.addSubview(host)
        panel.contentView = material
    }

    /// Shows the readout for `volume`, announces it, and fades it out after a moment.
    func show(_ volume: StreamVolume) {
        guard let parent else { return }
        hideTask?.cancel()
        host.rootView = StreamVolumeHUDView(volume: volume)
        let size = panel.frame.size
        panel.setFrameOrigin(NSPoint(x: parent.frame.midX - size.width / 2, y: parent.frame.maxY - size.height - 28))
        if !(parent.childWindows ?? []).contains(panel) { parent.addChildWindow(panel, ordered: .above) }
        panel.alphaValue = 1
        panel.orderFront(nil)
        NSAccessibility.post(element: panel, notification: .announcementRequested, userInfo: [
            .announcement: volume.announcement,
            .priority: NSAccessibilityPriorityLevel.high
        ])
        hideTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(Self.holdSeconds))
            guard !Task.isCancelled else { return }
            self?.fadeOut()
        }
    }

    /// Removes the readout at once, when the stream window goes away.
    func dismiss() {
        hideTask?.cancel()
        parent?.removeChildWindow(panel)
        panel.orderOut(nil)
    }

    private func fadeOut() {
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else {
            panel.orderOut(nil)
            return
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = Self.fadeSeconds
            panel.animator().alphaValue = 0
        }
        hideTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(Self.fadeSeconds))
            guard !Task.isCancelled else { return }
            self?.panel.orderOut(nil)
        }
    }
}
