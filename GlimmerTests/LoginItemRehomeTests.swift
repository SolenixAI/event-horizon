//
//  LoginItemRehomeTests.swift
//
//  The one-time re-registration of the login helper after it moved from
//  "Glimmer Login Helper.app" to "Event Horizon Login Helper.app". The decision
//  is pure; the SMAppService calls it drives are not testable hostless.
//

import Testing
@testable import Glimmer

struct LoginItemRehomeTests {

    @Test func aRegisteredHelperFromTheOldNameIsRegisteredAgainOnce() {
        #expect(LoginItemManager.rehomeAction(done: false, helperRegistered: true) == .reregister)
    }

    @Test func withoutAHelperTheMigrationIsOnlyRecorded() {
        #expect(LoginItemManager.rehomeAction(done: false, helperRegistered: false) == .recordOnly)
    }

    @Test func aFinishedMigrationNeverRunsAgain() {
        #expect(LoginItemManager.rehomeAction(done: true, helperRegistered: true) == .none)
        #expect(LoginItemManager.rehomeAction(done: true, helperRegistered: false) == .none)
    }
}
