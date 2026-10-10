//
//  UpdatePolicyTests.swift
//
//  Covers the update rules Event Horizon owns: no update window over a live stream,
//  and no check the person starts mid-stream. Sparkle keeps the daily schedule.
//

#if canImport(Sparkle)
import Testing
@testable import Glimmer

struct UpdatePolicyTests {
    @Test func noUpdateWindowOpensOverALiveStream() {
        #expect(!UpdatePolicy.mayShowWindow(isStreaming: true))
        #expect(UpdatePolicy.mayShowWindow(isStreaming: false))
    }

    @Test func aCheckWaitsForTheStreamToEnd() {
        #expect(!UpdatePolicy.mayCheckNow(isStreaming: true))
        #expect(UpdatePolicy.mayCheckNow(isStreaming: false))
    }
}
#endif
