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
    private func luminance(_ c: SpaceRGB) -> Double {
        func linear(_ v: Double) -> Double { v <= 0.03928 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4) }
        return 0.2126 * linear(c.red) + 0.7152 * linear(c.green) + 0.0722 * linear(c.blue)
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
    private func grounds(_ p: SpacePalette) -> [SpaceRGB] {
        let lowGold = over(p.horizonGold, p.skyBottom)
        return [p.skyTop, p.skyBottom, lowGold, over(p.horizonBlue, lowGold)]
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

    /// The bodies are neutral light: no signal colour, so none reads as live.
    @Test func bodiesAreNeutral() {
        for palette in [SpacePalette.night, SpacePalette.dawn] {
            let b = palette.body
            let spread = max(b.red, b.green, b.blue) - min(b.red, b.green, b.blue)
            #expect(spread <= 0.2)
        }
    }

    @Test func traceStaysInsideItsFrame() {
        let frame = CGRect(x: 10, y: 20, width: 300, height: 133)
        for step in 0..<400 {
            let p = FigureEightTrace.point(at: CGFloat(step) / 400, in: frame)
            #expect(p.x >= frame.minX - 0.001 && p.x <= frame.maxX + 0.001)
            #expect(p.y >= frame.minY - 0.001 && p.y <= frame.maxY + 0.001)
        }
    }

    @Test func traceIsAClosedLoop() {
        let frame = CGRect(x: 0, y: 0, width: 1, height: 1)
        let start = FigureEightTrace.point(at: 0, in: frame)
        let end = FigureEightTrace.point(at: 1, in: frame)
        #expect(abs(start.x - end.x) < 0.001 && abs(start.y - end.y) < 0.001)
        #expect(FigureEightTrace.arc.first == 0 && FigureEightTrace.arc.last == 1)
        #expect(zip(FigureEightTrace.arc, FigureEightTrace.arc.dropFirst()).allSatisfy { $0 <= $1 })
    }
}
