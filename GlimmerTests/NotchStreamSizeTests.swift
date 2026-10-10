//
//  NotchStreamSizeTests.swift
//
//  Covers AppModel.streamPixelSize(...): the default stream asks for the
//  panel's native grid with the camera-notch band cut off the top. The bug it
//  guards against: a notched Mac asked for the full 2560×1664 panel, so the PC
//  sent a picture taller than the screen below the notch and it showed a black
//  bar, and in a full-screen Space it stopped short of both edges.
//

import Testing
@testable import Glimmer

struct NotchStreamSizeTests {

    @Test func notchBandComesOffTheTopOfANotchedPanel() {
        // A 2560×1664 panel with a 32 pt notch at 2x: the 64 px band is cut,
        // leaving the 2560×1600 screen that sits below the notch.
        let size = AppModel.streamPixelSize(
            nativeWidth: 2560, nativeHeight: 1664, notchInsetPoints: 32, scale: 2)
        #expect(size.width == 2560)
        #expect(size.height == 1600)
    }

    @Test func aTallerNotchedPanelLosesItsWholeNotchBand() {
        // A 3024×1964 panel with a 37 pt notch at 2x: 74 px come off the top.
        let size = AppModel.streamPixelSize(
            nativeWidth: 3024, nativeHeight: 1964, notchInsetPoints: 37, scale: 2)
        #expect(size.width == 3024)
        #expect(size.height == 1890)
    }

    @Test func aPanelWithoutANotchKeepsItsNativeGrid() {
        // An external display reports no safe-area inset, so nothing changes.
        let size = AppModel.streamPixelSize(
            nativeWidth: 2560, nativeHeight: 1440, notchInsetPoints: 0, scale: 2)
        #expect(size.width == 2560)
        #expect(size.height == 1440)
    }
}
