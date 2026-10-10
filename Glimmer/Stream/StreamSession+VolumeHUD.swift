//
//  StreamSession+VolumeHUD.swift
//
//  Hops the volume readout to the main actor, where the stream window's AppKit lives.
//

import Foundation

extension StreamSession {
    /// Shows the readout for `volume` on the stream window, if it is on screen.
    func showVolumeHUD(_ volume: StreamVolume) async {
        let stream = window
        await MainActor.run { stream?.showVolumeHUD(volume) }
    }
}
