//
//  SpaceBackdropTests.swift
//
//  Home's backdrop: the text it carries keeps WCAG contrast, the horizon light
//  stays far below any signal, and the orbit trace stays inside its frame.
//

import CoreGraphics
import Foundation
import Testing
@testable import Glimmer

struct SpaceBackdropTests {

    /// WCAG relative luminance of an sRGB colour (its opacity is not part of it).
    private func luminance(_ color: SpaceRGB) -> Double {
        func linear(_ channel: Double) -> Double {
            channel <= 0.03928 ? channel / 12.92 : pow((channel + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(color.red) + 0.7152 * linear(color.green) + 0.0722 * linear(color.blue)
    }

    /// WCAG contrast ratio between two colours.
    private func contrast(_ a: SpaceRGB, _ b: SpaceRGB) -> Double {
        let la = luminance(a), lb = luminance(b)
        return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)
    }

    /// `top` drawn over `bottom` by its opacity, as an opaque colour.
    private func over(_ top: SpaceRGB, _ bottom: SpaceRGB) -> SpaceRGB {
        let a = top.opacity
        return SpaceRGB(top.red * a + bottom.red * (1 - a),
                        top.green * a + bottom.green * (1 - a),
                        top.blue * a + bottom.blue * (1 - a))
    }

    /// Every ground a label can sit on: the sky, and the sky under each horizon glow.
    private func grounds(_ palette: SpacePalette) -> [SpaceRGB] {
        let lowGold = over(palette.horizonGold, palette.skyBottom)
        return [palette.skyTop, palette.skyBottom, lowGold, over(palette.horizonBlue, lowGold)]
    }

    @Test func nightLabelsKeepWCAGContrast() {
        let label = SpaceRGB(1, 1, 1)
        let secondary = SpaceRGB(1, 1, 1, opacity: 0.6)
        for ground in grounds(.night) {
            #expect(contrast(label, ground) >= 4.5)
            #expect(contrast(over(secondary, ground), ground) >= 4.5)
        }
    }

    @Test func dawnLabelsKeepWCAGContrast() {
        let label = SpaceRGB(0, 0, 0)
        let secondary = SpaceRGB(0, 0, 0, opacity: 0.6)
        for ground in grounds(.dawn) {
            #expect(contrast(label, ground) >= 4.5)
            #expect(contrast(over(secondary, ground), ground) >= 4.5)
        }
    }

    /// The horizon is atmosphere: low opacity, and barely visible against the
    /// sky it sits on. The gold press ring and the blue live label are signals.
    @Test func horizonLightStaysFarBelowEverySignal() {
        let pressGoldNight = SpaceRGB(0.941, 0.541, 0.141)
        let pressGoldDawn = SpaceRGB(0.788, 0.439, 0.059)
        let liveBlue = SpaceRGB(0.227, 0.627, 1.0)
        for (palette, press) in [(SpacePalette.night, pressGoldNight), (SpacePalette.dawn, pressGoldDawn)] {
            #expect(palette.horizonGold.opacity <= 0.2)
            #expect(palette.horizonBlue.opacity <= 0.2)
            let lowGold = over(palette.horizonGold, palette.skyBottom)
            let lowBlue = over(palette.horizonBlue, palette.skyBottom)
            #expect(contrast(lowGold, palette.skyBottom) < 1.5)
            #expect(contrast(lowBlue, palette.skyBottom) < 1.5)
            #expect(contrast(press, palette.skyBottom) >= 3)
        }
        // The live blue reads on the night sky. On the dawn sky it does not
        // reach 3:1, as on the old system window: a founder decision, recorded
        // in DESIGN.md rather than hidden here.
        #expect(contrast(liveBlue, SpacePalette.night.skyBottom) >= 3)
    }

    /// The live flow is a live mark: the logo's blue at full strength, as the
    /// chip and the Running label show it. Only the field's horizon light is
    /// atmosphere, kept under its bar.
    @Test func liveFlowIsFullStrengthLogoBlue() {
        let liveBlue = SpaceRGB(0.227, 0.627, 1.0)
        for palette in [SpacePalette.night, SpacePalette.dawn] {
            #expect(palette.live.opacity == 1)
            #expect(abs(palette.live.red - liveBlue.red) < 0.001)
            #expect(abs(palette.live.green - liveBlue.green) < 0.001)
            #expect(abs(palette.live.blue - liveBlue.blue) < 0.001)
            #expect(palette.horizonBlue.opacity <= 0.2)
        }
    }
}
