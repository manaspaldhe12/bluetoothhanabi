import XCTest
import MultipeerConnectivity
import HanabiKit
@testable import BluetoothHanabi

/// These tests never call `startHosting()`/`startBrowsing()` — that would trigger real
/// MultipeerConnectivity network/permission activity, which is exactly what's unusable in a
/// CI runner (no Bluetooth hardware, no one to answer a Local Network permission prompt, and
/// no guarantee two runner processes can even see each other over Bonjour). Instead, each test
/// invokes the relevant `MCSessionDelegate` / `MCNearbyServiceAdvertiserDelegate` /
/// `MCNearbyServiceBrowserDelegate` method directly, simulating what MultipeerConnectivity
/// would call in response to a real network event, and asserts on how MultipeerManager reacts.
/// That's real regression coverage for the wiring — e.g. this suite would have caught the
/// missing didNotStartAdvertising/didNotStartBrowsingForPeers handlers found via manual testing
/// — even though it can't prove peer discovery works on real hardware.
final class MultipeerManagerTests: XCTestCase {
    private func makeManager(_ name: String = "Test") -> MultipeerManager {
        MultipeerManager(displayName: name)
    }

    /// Delegate methods hop to the main queue via `DispatchQueue.main.async`. Enqueueing a
    /// second block after triggering one guarantees (FIFO on a serial queue) that the first
    /// has already run by the time this one fires.
    private func flushMainQueue() {
        let exp = expectation(description: "flush")
        DispatchQueue.main.async { exp.fulfill() }
        wait(for: [exp], timeout: 2.0)
    }

    // MARK: - Browsing

    func testFoundPeerAddsToAvailableHosts() {
        let manager = makeManager()
        let browser = MCNearbyServiceBrowser(peer: manager.myPeerId, serviceType: MultipeerManager.serviceType)
        let peer = MCPeerID(displayName: "Host#0000")

        manager.browser(browser, foundPeer: peer, withDiscoveryInfo: nil)
        flushMainQueue()

        XCTAssertEqual(manager.availableHosts, [peer])
    }

    func testFoundPeerDoesNotDuplicate() {
        let manager = makeManager()
        let browser = MCNearbyServiceBrowser(peer: manager.myPeerId, serviceType: MultipeerManager.serviceType)
        let peer = MCPeerID(displayName: "Host#0000")

        manager.browser(browser, foundPeer: peer, withDiscoveryInfo: nil)
        manager.browser(browser, foundPeer: peer, withDiscoveryInfo: nil)
        flushMainQueue()

        XCTAssertEqual(manager.availableHosts.count, 1)
    }

    func testLostPeerRemovesFromAvailableHosts() {
        let manager = makeManager()
        let browser = MCNearbyServiceBrowser(peer: manager.myPeerId, serviceType: MultipeerManager.serviceType)
        let peer = MCPeerID(displayName: "Host#0000")
        manager.browser(browser, foundPeer: peer, withDiscoveryInfo: nil)
        flushMainQueue()
        XCTAssertEqual(manager.availableHosts.count, 1)

        manager.browser(browser, lostPeer: peer)
        flushMainQueue()

        XCTAssertTrue(manager.availableHosts.isEmpty)
    }

    func testDidNotStartBrowsingFiresCallback() {
        let manager = makeManager()
        let browser = MCNearbyServiceBrowser(peer: manager.myPeerId, serviceType: MultipeerManager.serviceType)
        var receivedError: Error?
        manager.onFailedToStartBrowsing = { receivedError = $0 }

        manager.browser(browser, didNotStartBrowsingForPeers: NSError(domain: "test", code: 1))
        flushMainQueue()

        XCTAssertNotNil(receivedError)
    }

    // MARK: - Advertising

    func testDidNotStartAdvertisingFiresCallback() {
        let manager = makeManager()
        let advertiser = MCNearbyServiceAdvertiser(peer: manager.myPeerId, discoveryInfo: nil, serviceType: MultipeerManager.serviceType)
        var receivedError: Error?
        manager.onFailedToStartAdvertising = { receivedError = $0 }

        manager.advertiser(advertiser, didNotStartAdvertisingPeer: NSError(domain: "test", code: 2))
        flushMainQueue()

        XCTAssertNotNil(receivedError)
    }

    func testAdvertiserAcceptsInvitationWhenAllowed() {
        let manager = makeManager()
        let advertiser = MCNearbyServiceAdvertiser(peer: manager.myPeerId, discoveryInfo: nil, serviceType: MultipeerManager.serviceType)
        manager.shouldAcceptInvitation = { true }
        let peer = MCPeerID(displayName: "Bob#0000")
        let exp = expectation(description: "handler")
        var acceptedFlag: Bool?
        var handedSession: MCSession?

        manager.advertiser(advertiser, didReceiveInvitationFromPeer: peer, withContext: nil) { accept, session in
            acceptedFlag = accept
            handedSession = session
            exp.fulfill()
        }
        wait(for: [exp], timeout: 2.0)

        XCTAssertEqual(acceptedFlag, true)
        XCTAssertNotNil(handedSession)
    }

    func testAdvertiserRejectsInvitationWhenNotAllowed() {
        let manager = makeManager()
        let advertiser = MCNearbyServiceAdvertiser(peer: manager.myPeerId, discoveryInfo: nil, serviceType: MultipeerManager.serviceType)
        manager.shouldAcceptInvitation = { false }
        let peer = MCPeerID(displayName: "Bob#0000")
        let exp = expectation(description: "handler")
        var acceptedFlag: Bool?
        var handedSession: MCSession?

        manager.advertiser(advertiser, didReceiveInvitationFromPeer: peer, withContext: nil) { accept, session in
            acceptedFlag = accept
            handedSession = session
            exp.fulfill()
        }
        wait(for: [exp], timeout: 2.0)

        XCTAssertEqual(acceptedFlag, false)
        XCTAssertNil(handedSession)
    }

    // MARK: - Session state

    func testSessionConnectedFiresOnPeerConnected() {
        let manager = makeManager()
        let peer = MCPeerID(displayName: "Bob#0000")
        var connectedPeer: MCPeerID?
        manager.onPeerConnected = { connectedPeer = $0 }

        manager.session(manager.session, peer: peer, didChange: .connected)
        flushMainQueue()

        XCTAssertEqual(connectedPeer, peer)
    }

    func testSessionNotConnectedFiresOnPeerDisconnected() {
        let manager = makeManager()
        let peer = MCPeerID(displayName: "Bob#0000")
        var disconnectedPeer: MCPeerID?
        manager.onPeerDisconnected = { disconnectedPeer = $0 }

        manager.session(manager.session, peer: peer, didChange: .notConnected)
        flushMainQueue()

        XCTAssertEqual(disconnectedPeer, peer)
    }

    // MARK: - Message decoding

    func testReceivingValidMessageFiresOnReceiveMessage() throws {
        let manager = makeManager()
        let peer = MCPeerID(displayName: "Bob#0000")
        var received: NetworkMessage?
        manager.onReceiveMessage = { message, _ in received = message }
        let data = try NetworkMessage.joinRequest(name: "Bob").encoded()

        manager.session(manager.session, didReceive: data, fromPeer: peer)
        flushMainQueue()

        if case .joinRequest(let name)? = received {
            XCTAssertEqual(name, "Bob")
        } else {
            XCTFail("expected a decoded joinRequest message, got \(String(describing: received))")
        }
    }

    func testReceivingGarbageDataIsIgnoredWithoutCrashing() {
        let manager = makeManager()
        let peer = MCPeerID(displayName: "Bob#0000")
        var receivedCount = 0
        manager.onReceiveMessage = { _, _ in receivedCount += 1 }

        manager.session(manager.session, didReceive: Data([0xFF, 0x00, 0x01]), fromPeer: peer)
        flushMainQueue()

        XCTAssertEqual(receivedCount, 0)
    }
}
