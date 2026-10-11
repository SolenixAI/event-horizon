//
//  AppModel+ApproveMac.swift
//
//  A Mac that already streams from a PC answers another Mac's pairing request,
//  so a PC with its monitor off can still be approved with the same code check.
//

import Foundation

extension AppModel {
    /// How often a trusted Mac asks its PCs whether another Mac is waiting.
    static let approvalPollInterval: Duration = .seconds(3)

    /// Asks every PC this Mac holds a companion token for, while the app runs.
    func startApprovalWatch() {
        guard approvalWatchTask == nil else { return }
        approvalWatchTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.checkWaitingMacs()
                try? await Task.sleep(for: Self.approvalPollInterval)
            }
        }
    }

    private func checkWaitingMacs() async {
        guard waitingApproval == nil else { return }
        for host in hosts {
            guard let token = CompanionTokens.token(forHost: host.id),
                  let address = host.manualAddress ?? host.localAddress else { continue }
            let companion = CompanionClient(address: address, pinned: CompanionTokens.fingerprint(forHost: host.id))
            if let first = await companion.waiting(token: token).first {
                waitingApproval = Self.approval(first, on: host)
                return
            }
        }
    }

    /// What the alert shows for a waiting Mac. Pure, so it is tested directly.
    nonisolated static func approval(_ waiting: CompanionClient.WaitingMac, on host: Host) -> WaitingApproval {
        WaitingApproval(hostID: host.id, pcName: host.displayName, macID: waiting.macID,
                        macName: waiting.macName, code: CompanionClient.spaced(waiting.code))
    }

    /// The person answered the alert.
    func answerWaitingMac(allow: Bool) {
        guard let pending = waitingApproval else { return }
        waitingApproval = nil
        guard let host = hosts.first(where: { $0.id == pending.hostID }),
              let token = CompanionTokens.token(forHost: host.id),
              let address = host.manualAddress ?? host.localAddress else { return }
        let companion = CompanionClient(address: address, pinned: CompanionTokens.fingerprint(forHost: host.id))
        Task { _ = await companion.decide(token: token, macID: pending.macID, allow: allow) }
    }
}

/// Another Mac waiting to pair with one of this Mac's PCs.
struct WaitingApproval: Equatable, Identifiable {
    let hostID: String
    let pcName: String
    let macID: String
    let macName: String
    let code: String
    var id: String { hostID + "/" + macID }
}
