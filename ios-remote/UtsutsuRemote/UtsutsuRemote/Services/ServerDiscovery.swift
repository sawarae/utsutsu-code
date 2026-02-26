import Foundation
import Combine

/// Discovers relay servers on the local network via Bonjour/mDNS.
@MainActor
final class ServerDiscovery: NSObject, ObservableObject, NetServiceBrowserDelegate, NetServiceDelegate {
    @Published var discoveredServers: [DiscoveredServer] = []
    @Published var isSearching = false

    private var browser: NetServiceBrowser?
    private var resolvingServices: [NetService] = []

    struct DiscoveredServer: Identifiable, Equatable {
        let id = UUID()
        let name: String
        let host: String
        let port: Int
    }

    func startDiscovery() {
        stopDiscovery()
        discoveredServers = []
        browser = NetServiceBrowser()
        browser?.delegate = self
        browser?.searchForServices(ofType: "_utsutsu-relay._tcp.", inDomain: "local.")
        isSearching = true
    }

    func stopDiscovery() {
        browser?.stop()
        browser = nil
        resolvingServices.removeAll()
        isSearching = false
    }

    // MARK: - NetServiceBrowserDelegate

    nonisolated func netServiceBrowser(_ browser: NetServiceBrowser, didFind service: NetService, moreComing: Bool) {
        Task { @MainActor in
            service.delegate = self
            resolvingServices.append(service)
            service.resolve(withTimeout: 5.0)
        }
    }

    nonisolated func netServiceBrowser(_ browser: NetServiceBrowser, didRemove service: NetService, moreComing: Bool) {
        Task { @MainActor in
            discoveredServers.removeAll { $0.name == service.name }
        }
    }

    nonisolated func netServiceBrowserDidStopSearch(_ browser: NetServiceBrowser) {
        Task { @MainActor in
            isSearching = false
        }
    }

    // MARK: - NetServiceDelegate

    nonisolated func netServiceDidResolveAddress(_ sender: NetService) {
        Task { @MainActor in
            guard let hostname = sender.hostName else { return }
            let server = DiscoveredServer(
                name: sender.name,
                host: hostname,
                port: sender.port
            )
            if !discoveredServers.contains(where: { $0.host == server.host && $0.port == server.port }) {
                discoveredServers.append(server)
            }
        }
    }
}
