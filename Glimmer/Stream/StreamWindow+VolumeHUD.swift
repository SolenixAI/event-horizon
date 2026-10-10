//
//  StreamWindow+VolumeHUD.swift
//
//  Shows the stream volume readout over the stream window while the window is on screen.
//

import Foundation

extension StreamWindow {
    /// Shows the readout for a volume key or a control. Nothing shows while the window is hidden.
    func showVolumeHUD(_ volume: StreamVolume) {
        guard window.isVisible else { return }
        let hud = volumeHUD ?? StreamVolumeHUD(parent: window)
        volumeHUD = hud
        hud.show(volume)
    }

    /// Removes the readout at once. Called when the window closes.
    func dismissVolumeHUD() {
        volumeHUD?.dismiss()
    }
}
