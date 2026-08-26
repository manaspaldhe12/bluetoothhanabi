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

    var onReceiveMessage: ((NetworkMessage, MCPeerID) -> Void)?
    var onPeerConnected: ((MCPeerID) -> Void)?
    var onPeerDisconnected: ((MCPeerID) -> Void)?
    /// Consulted only while hosting, to cap the lobby at `LobbyState.maxPlayers`.
    var shouldAcceptInvitation: (() -> Bool)?

    private var advertiser: MCNearbyServiceAdvertiser?
    private var browser: MCNearbyServiceBrowser?

    init(displayName: String) {
        myPeerId = MCPeerID(displayName: displayName)
        session = MCSession(peer: myPeerId, securityIdentity: nil, encryptionPreference: .required)
        super.init()
        session.delegate = self
    }

    func startHosting() {
        let advertiser = MCNearbyServiceAdvertiser(peer: myPeerId, discoveryInfo: nil, serviceType: Self.serviceType)
        advertiser.delegate = self
        advertiser.startAdvertisingPeer()
        self.advertiser = advertiser
    }

    func stopHosting() {
        advertiser?.stopAdvertisingPeer()
        advertiser = nil
    }

    func startBrowsing() {
        let browser = MCNearbyServiceBrowser(peer: myPeerId, serviceType: Self.serviceType)
        browser.delegate = self
        browser.startBrowsingForPeers()
        self.browser = browser
        availableHosts = []
    }

    func stopBrowsing() {
        browser?.stopBrowsingForPeers()
        browser = nil
        availableHosts = []
    }

    func invite(_ peer: MCPeerID) {
        browser?.invitePeer(peer, to: session, withContext: nil, timeout: 20)
    }

    func send(_ message: NetworkMessage, to peers: [MCPeerID]? = nil) {
        let targets = peers ?? session.connectedPeers
        guard !targets.isEmpty else { return }
        do {
            let data = try message.encoded()
            try session.send(data, toPeers: targets, with: .reliable)
        } catch {
            print("MultipeerManager send error: \(error)")
        }
    }

    func disconnect() {
        stopHosting()
        stopBrowsing()
        session.disconnect()
    }
}

extension MultipeerManager: MCSessionDelegate {
    func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
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
        guard let message = try? NetworkMessage.decode(data) else { return }
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
        invitationHandler(accept, accept ? session : nil)
    }
}

extension MultipeerManager: MCNearbyServiceBrowserDelegate {
    func browser(_ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID, withDiscoveryInfo info: [String: String]?) {
        DispatchQueue.main.async {
            if !self.availableHosts.contains(peerID) {
                self.availableHosts.append(peerID)
            }
        }
    }

    func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
        DispatchQueue.main.async {
            self.availableHosts.removeAll { $0 == peerID }
        }
    }
}
