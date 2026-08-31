import Foundation
import MultipeerConnectivity
import HanabiKit

/// Thin wrapper around MultipeerConnectivity. The app only ever forms a star topology: one
/// peer advertises as the host and every other peer browses for it and connects directly to
/// the host (peers never connect to each other). All game logic is relayed through the host,
/// so that's all this needs to support — it scales from 2 up to 5 players without any extra
/// networking work.
final class MultipeerManager: NSObject, ObservableObject {
    static let serviceType = "hanabi-game"

    let myPeerId: MCPeerID
    let session: MCSession

    @Published private(set) var connectedPeers: [MCPeerID] = []
    @Published private(set) var availableHosts: [MCPeerID] = []
    /// A running, timestamped log of every networking event, visible in-app via DebugLogView —
    /// so diagnosing a "can't find peer" issue doesn't require a Mac + Console.app.
    @Published private(set) var log: [String] = []

    var onReceiveMessage: ((NetworkMessage, MCPeerID) -> Void)?
    var onPeerConnected: ((MCPeerID) -> Void)?
    var onPeerDisconnected: ((MCPeerID) -> Void)?
    /// Consulted only while hosting, to cap the lobby at `LobbyState.maxPlayers`.
    var shouldAcceptInvitation: (() -> Bool)?
    /// Fires when advertising/browsing fails to even start — most commonly a denied Local
    /// Network permission. Without this, that failure is silent and the UI just hangs on
    /// "Searching…" forever with no clue why.
    var onFailedToStartAdvertising: ((Error) -> Void)?
    var onFailedToStartBrowsing: ((Error) -> Void)?

    private var advertiser: MCNearbyServiceAdvertiser?
    private var browser: MCNearbyServiceBrowser?

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter
    }()

    private func logEvent(_ message: String) {
        let line = "\(Self.timeFormatter.string(from: Date())) \(message)"
        print("[MultipeerManager] \(line)")
        if Thread.isMainThread {
            appendLog(line)
        } else {
            DispatchQueue.main.async { self.appendLog(line) }
        }
    }

    private func appendLog(_ line: String) {
        log.append(line)
        if log.count > 300 {
            log.removeFirst(log.count - 300)
        }
    }

    init(displayName: String) {
        myPeerId = MCPeerID(displayName: displayName)
        session = MCSession(peer: myPeerId, securityIdentity: nil, encryptionPreference: .required)
        super.init()
        session.delegate = self
        logEvent("Initialized. Peer ID = \(displayName)")
    }

    func startHosting() {
        logEvent("startHosting() — creating advertiser for service \"\(Self.serviceType)\"")
        let advertiser = MCNearbyServiceAdvertiser(peer: myPeerId, discoveryInfo: nil, serviceType: Self.serviceType)
        advertiser.delegate = self
        advertiser.startAdvertisingPeer()
        self.advertiser = advertiser
        logEvent("startAdvertisingPeer() called")
    }

    func stopHosting() {
        guard advertiser != nil else { return }
        logEvent("stopHosting()")
        advertiser?.stopAdvertisingPeer()
        advertiser = nil
    }

    func startBrowsing() {
        logEvent("startBrowsing() — creating browser for service \"\(Self.serviceType)\"")
        let browser = MCNearbyServiceBrowser(peer: myPeerId, serviceType: Self.serviceType)
        browser.delegate = self
        browser.startBrowsingForPeers()
        self.browser = browser
        availableHosts = []
        logEvent("startBrowsingForPeers() called")
    }

    func stopBrowsing() {
        guard browser != nil else { return }
        logEvent("stopBrowsing()")
        browser?.stopBrowsingForPeers()
        browser = nil
        availableHosts = []
    }

    func invite(_ peer: MCPeerID) {
        logEvent("Inviting \(peer.displayName)…")
        browser?.invitePeer(peer, to: session, withContext: nil, timeout: 20)
    }

    func send(_ message: NetworkMessage, to peers: [MCPeerID]? = nil) {
        let targets = peers ?? session.connectedPeers
        guard !targets.isEmpty else {
            logEvent("send(\(String(describing: message))) skipped — no target peers")
            return
        }
        do {
            let data = try message.encoded()
            try session.send(data, toPeers: targets, with: .reliable)
            logEvent("Sent \(String(describing: message)) to \(targets.map(\.displayName).joined(separator: ", "))")
        } catch {
            logEvent("FAILED to send \(String(describing: message)): \(error.localizedDescription)")
        }
    }

    func disconnect() {
        logEvent("disconnect()")
        stopHosting()
        stopBrowsing()
        session.disconnect()
    }
}

extension MultipeerManager: MCSessionDelegate {
    func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        logEvent("Session state for \(peerID.displayName): \(state.description)")
        DispatchQueue.main.async {
            self.connectedPeers = session.connectedPeers
            switch state {
            case .connected: self.onPeerConnected?(peerID)
            case .notConnected: self.onPeerDisconnected?(peerID)
            case .connecting: break
            @unknown default: break
            }
        }
    }

    func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        guard let message = try? NetworkMessage.decode(data) else {
            logEvent("Received \(data.count) bytes from \(peerID.displayName) but failed to decode")
            return
        }
        logEvent("Received \(String(describing: message)) from \(peerID.displayName)")
        DispatchQueue.main.async {
            self.onReceiveMessage?(message, peerID)
        }
    }

    func session(_ session: MCSession, didReceive stream: InputStream, withName streamName: String, fromPeer peerID: MCPeerID) {}
    func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, with progress: Progress) {}
    func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, at localURL: URL?, withError error: Error?) {}
}

extension MultipeerManager: MCNearbyServiceAdvertiserDelegate {
    func advertiser(
        _ advertiser: MCNearbyServiceAdvertiser,
        didReceiveInvitationFromPeer peerID: MCPeerID,
        withContext context: Data?,
        invitationHandler: @escaping (Bool, MCSession?) -> Void
    ) {
        let accept = shouldAcceptInvitation?() ?? true
        logEvent("Received invitation from \(peerID.displayName) — \(accept ? "accepting" : "rejecting (lobby full?)")")
        invitationHandler(accept, accept ? session : nil)
    }

    func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didNotStartAdvertisingPeer error: Error) {
        logEvent("FAILED to start advertising: \(error.localizedDescription)")
        DispatchQueue.main.async {
            self.onFailedToStartAdvertising?(error)
        }
    }
}

extension MultipeerManager: MCNearbyServiceBrowserDelegate {
    func browser(_ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID, withDiscoveryInfo info: [String: String]?) {
        logEvent("Found peer: \(peerID.displayName)")
        DispatchQueue.main.async {
            if !self.availableHosts.contains(peerID) {
                self.availableHosts.append(peerID)
            }
        }
    }

    func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
        logEvent("Lost peer: \(peerID.displayName)")
        DispatchQueue.main.async {
            self.availableHosts.removeAll { $0 == peerID }
        }
    }

    func browser(_ browser: MCNearbyServiceBrowser, didNotStartBrowsingForPeers error: Error) {
        logEvent("FAILED to start browsing: \(error.localizedDescription)")
        DispatchQueue.main.async {
            self.onFailedToStartBrowsing?(error)
        }
    }
}

extension MCSessionState {
    var description: String {
        switch self {
        case .notConnected: return "notConnected"
        case .connecting: return "connecting"
        case .connected: return "connected"
        @unknown default: return "unknown(\(rawValue))"
        }
    }
}
