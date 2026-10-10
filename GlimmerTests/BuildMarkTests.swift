//
//  BuildMarkTests.swift
//
//  Only the shipped app goes unmarked; every other build reads "Test build".
//

import Testing
@testable import Glimmer

struct BuildMarkTests {
    @Test func theShippedAppCarriesNoMark() {
        #expect(BuildMark.label(bundleIdentifier: "dev.solenix.eventhorizon") == nil)
    }

    @Test func anyOtherBuildIsMarkedAsATestBuild() {
        #expect(BuildMark.label(bundleIdentifier: "dev.solenix.eventhorizon.updatetest") == "Test build")
        #expect(BuildMark.label(bundleIdentifier: "dev.solenix.glimmer") == "Test build")
    }
}
