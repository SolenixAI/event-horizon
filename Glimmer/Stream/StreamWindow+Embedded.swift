//
//  StreamWindow+Embedded.swift
//
//  Citadel: the stream inside the app's own window. The input view (which
//  wraps the display view) sits on top of Home in the main window's content
//  view. Home is the PC on the desk: the same live surface, shrunk onto the
//  desk's screen frame and hands-off (clicks fall through to Home, keys and
//  the pointer are the Mac's). Opening the PC grows it to fill the window;
//  ⌘W shrinks it back while the PC keeps running.
//
//  The main window is never ordered out or closed from here: it is the
//  user's window. Window mode underneath: no presentation options, no cover,
//  no level, and the pointer follows the window pointer model (hover grab for
//  a game, free on the Desktop).
//

import AppKit
import QuartzCore

extension StreamWindow {

    /// Where Home draws the PC's screen, in the main window's SwiftUI global
    /// space (top-left origin). Written by the desk view, read here.
    static var deskFrame: CGRect = .zero {
        didSet {
            guard deskFrame != oldValue else { return }
            NotificationCenter.default.post(name: deskFrameDidChange, object: nil)
        }
    }

    static let deskFrameDidChange = Notification.Name("CitadelDeskFrameDidChange")

    /// Home is showing with a live PC on the desk. The user chose Home, so a
    /// ⌘Tab back into Citadel lands there, not in the stream.
    static var homeShowing = false

    /// The desk frame in the content view's own coordinates, or nil while Home
    /// has not laid it out.
    func deskRect(in host: NSView) -> NSRect? {
        let rect = Self.deskFrame
        guard rect.width > 1, rect.height > 1 else { return nil }
        return host.isFlipped ? rect : NSRect(x: rect.minX, y: host.bounds.height - rect.maxY,
                                              width: rect.width, height: rect.height)
    }

    /// Clicks fall through while the picture is invisible or on the desk.
    func updateEmbeddedPassThrough() {
        embeddedSurface?.passesMouseThrough = awaitingFirstFrameFadeIn || embeddedAtHome
    }

    /// The embedded bring-up: the window grows to the stream, the surface sits
    /// on the desk, invisible, until the first frame.
    func showEmbedded() {
        displayView.alphaValue = 0.0
        embeddedAtHome = false
        awaitingFirstFrameFadeIn = true
        embeddedSurface?.setTransparentCursorEnabled(false)
        fitWindowToStream(animate: true)
        placeSurfaceOnDesk(rounded: true)
        installWindowedLifecycleObservers()
        deskFrameObserver = NotificationCenter.default.addObserver(
            forName: Self.deskFrameDidChange, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, !self.didClose, self.embeddedAtHome || self.awaitingFirstFrameFadeIn else { return }
                self.placeSurfaceOnDesk(rounded: true)
            }
        }
        DispatchQueue.main.async { [weak self] in
            guard let self, !self.didClose else { return }
            self.onDidBecomeReadyForInput?()
        }
        log.info("Stream shown inside the main window")
    }

    /// The first frame is up: the PC lights up on the desk, then grows to
    /// fill the window.
    func fadeInEmbedded() {
        log.info("First frame - the PC lights up on the desk")
        let view = displayView
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            view.alphaValue = 1.0
            expandSurface(animate: false)
            return
        }
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.2
            ctx.allowsImplicitAnimation = true
            view.animator().alphaValue = 1.0
        }, completionHandler: {
            MainActor.assumeIsolated { [weak self] in
                guard let self, !self.didClose, !self.embeddedAtHome else { return }
                self.expandSurface(animate: true)
            }
        })
    }

    /// Home: the PC shrinks back onto the desk and keeps running live; the
    /// pointer and keys are the Mac's again.
    public func enterHome() {
        guard isEmbedded, !didClose, !embeddedAtHome else { return }
        embeddedAtHome = true
        Self.homeShowing = true
        updateEmbeddedPassThrough()
        setCursorHidden(false)
        embeddedSurface?.setTransparentCursorEnabled(false)
        hideCaptureHint()
        releaseStreamAspect()
        placeSurfaceOnDesk(rounded: true, animate: true)
        onHomeChanged?(true)
        log.info("Home shown - the PC keeps running on the desk")
    }

    /// Back to the PC from Home: it grows to fill the window again.
    public func leaveHome() {
        guard isEmbedded, !didClose, embeddedAtHome else { return }
        embeddedAtHome = false
        Self.homeShowing = false
        updateEmbeddedPassThrough()
        fitWindowToStream(animate: true)
        expandSurface(animate: true)
        reengageForeground()
        onHomeChanged?(false)
        log.info("Back to the PC from Home")
    }

    /// The surface on the desk's screen frame (or the whole window when Home
    /// has no desk laid out).
    func placeSurfaceOnDesk(rounded: Bool, animate: Bool = false) {
        guard let surface = embeddedSurface, let host = surface.superview else { return }
        surface.autoresizingMask = []
        let target = deskRect(in: host) ?? host.bounds
        log.info("Surface on the desk: \(target.debugDescription, privacy: .public) in \(host.bounds.debugDescription, privacy: .public) flipped=\(host.isFlipped, privacy: .public)")
        setSurfaceCorner(rounded ? 12 : 0)
        move(surface, to: target, animate: animate)
    }

    /// The surface fills the window and follows its size.
    func expandSurface(animate: Bool) {
        guard let surface = embeddedSurface, let host = surface.superview else { return }
        log.info("Surface grows to fill the window (animate=\(animate, privacy: .public))")
        let finish: @MainActor () -> Void = { [weak self] in
            self?.log.info("Surface fills the window: \(host.bounds.debugDescription, privacy: .public)")
            surface.frame = host.bounds
            surface.autoresizingMask = [.width, .height]
            self?.setSurfaceCorner(0)
        }
        guard animate, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { finish(); return }
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.42
            ctx.allowsImplicitAnimation = true
            ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 0.9, 0.25, 1)
            surface.animator().frame = host.bounds
        }, completionHandler: {
            MainActor.assumeIsolated { finish() }
        })
    }

    private func move(_ surface: NSView, to target: NSRect, animate: Bool) {
        guard animate, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else {
            surface.frame = target
            return
        }
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.38
            ctx.allowsImplicitAnimation = true
            ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 0.9, 0.25, 1)
            surface.animator().frame = target
        }
    }

    private func setSurfaceCorner(_ radius: CGFloat) {
        displayLayer.cornerRadius = radius
        displayLayer.masksToBounds = radius > 0
    }

    /// Embedded close: fade the picture out, drop the last frame, and take
    /// the surface out of the main window. Home is already underneath.
    func closeEmbedded() {
        Self.homeShowing = false
        if let token = deskFrameObserver {
            NotificationCenter.default.removeObserver(token)
            deskFrameObserver = nil
        }
        let view = displayView
        let finish: @MainActor () -> Void = { [weak self] in
            guard let self else { return }
            self.displayLayer.sampleBufferRenderer.flush(removingDisplayedImage: true) { }
            self.embeddedSurface?.removeFromSuperview()
            self.embeddedSurface = nil
            self.releaseStreamAspect()
            view.alphaValue = 1.0
        }
        if window.firstResponder === embeddedSurface { window.makeFirstResponder(nil) }
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            finish()
            return
        }
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.25
            ctx.allowsImplicitAnimation = true
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            view.animator().alphaValue = 0.0
        }, completionHandler: {
            MainActor.assumeIsolated { finish() }
        })
    }

    /// The window grows to the stream (pixel-mapped, fit to the screen, never
    /// smaller than it already is) and locks to its aspect, so the PC fills
    /// the window edge to edge. A full-screen Space keeps its frame.
    func fitWindowToStream(animate: Bool) {
        guard !window.styleMask.contains(.fullScreen), streamPixelSize.width > 0,
              let screen = window.screen ?? NSScreen.main else { return }
        let aspect = streamPixelSize
        let probe = NSRect(x: 0, y: 0, width: 100, height: 100)
        let titleBar = window.frameRect(forContentRect: probe).height - probe.height
        let available = CGSize(width: screen.visibleFrame.width,
                               height: max(screen.visibleFrame.height - titleBar, 0))
        let mapped = StreamWindowGeometry.pixelMappedContentSize(
            pixelWidth: Int(aspect.width), pixelHeight: Int(aspect.height),
            backingScaleFactor: screen.backingScaleFactor)
        let current = window.contentRect(forFrameRect: window.frame).size
        let wanted = CGSize(width: max(mapped.width, current.width), height: max(mapped.height, current.height))
        let content = StreamWindowGeometry.conformed(
            StreamWindowGeometry.fitted(wanted, within: available), toAspect: aspect, within: available)
        var frame = window.frameRect(forContentRect: NSRect(origin: .zero, size: content))
        frame.origin = NSPoint(x: window.frame.midX - frame.width / 2, y: window.frame.midY - frame.height / 2)
        frame = window.constrainFrameRect(frame, to: screen)
        let animated = animate && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        window.setFrame(frame, display: true, animate: animated)
        window.contentAspectRatio = aspect
    }

    /// Home is free to be any size again.
    func releaseStreamAspect() {
        window.resizeIncrements = NSSize(width: 1, height: 1)
    }
}
