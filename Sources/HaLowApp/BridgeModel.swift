import AppKit
import Foundation
import Darwin
import SystemConfiguration
import HaLowCore

struct Adapter: Identifiable, Hashable {
    let id: String
    let name: String
    let addresses: [String]
    let wireless: Bool
    var label: String { "\(name) · \(id)" }

    static func available() -> [Adapter] {
        var names: [String: (String, Bool)] = [:]
        for interface in SCNetworkInterfaceCopyAll() as? [SCNetworkInterface] ?? [] {
            guard let bsdName = SCNetworkInterfaceGetBSDName(interface) as String? else { continue }
            let name = SCNetworkInterfaceGetLocalizedDisplayName(interface) as String? ?? bsdName
            let wireless = SCNetworkInterfaceGetInterfaceType(interface) == kSCNetworkInterfaceTypeIEEE80211
            names[bsdName] = (name, wireless)
        }
        var first: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&first) == 0 else { return [] }
        defer { freeifaddrs(first) }
        var addresses: [String: Set<String>] = [:]
        var cursor = first
        while let entry = cursor {
            defer { cursor = entry.pointee.ifa_next }
            guard let address = entry.pointee.ifa_addr,
                  address.pointee.sa_family == UInt8(AF_INET),
                  entry.pointee.ifa_flags & UInt32(IFF_UP) != 0,
                  entry.pointee.ifa_flags & UInt32(IFF_RUNNING) != 0,
                  entry.pointee.ifa_flags & UInt32(IFF_LOOPBACK) == 0,
                  entry.pointee.ifa_flags & UInt32(IFF_BROADCAST) != 0 else { continue }
            let id = String(cString: entry.pointee.ifa_name)
            guard id.hasPrefix("en") || id.hasPrefix("bridge") else { continue }
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            guard getnameinfo(address, socklen_t(address.pointee.sa_len), &host,
                              socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0 else { continue }
            addresses[id, default: []].insert(String(cString: host))
        }
        return addresses.map { id, ips in
            let info = names[id] ?? (id, false)
            return Adapter(id: id, name: info.0, addresses: ips.sorted(), wireless: info.1)
        }.sorted { lhs, rhs in
            if lhs.wireless != rhs.wireless { return !lhs.wireless }
            return lhs.id.localizedStandardCompare(rhs.id) == .orderedAscending
        }
    }
}

// Blocking BSD socket calls run on this actor, never on the SwiftUI main actor.
actor BridgeService {
    func discover(interface: String) throws -> [MAC] {
        try Task.checkCancellation()
        return try NetAT(interface: interface).discover()
    }
    func read(interface: String, device: MAC, command: String) throws -> QueryResult {
        try Task.checkCancellation()
        let result = try NetAT(interface: interface).query(command, target: device)
        try Task.checkCancellation()
        return result
    }
}

@MainActor
final class BridgeModel: ObservableObject {
    @Published var adapters: [Adapter] = []
    @Published var adapterID = ""
    @Published var devices: [MAC] = []
    @Published var selectedID: String?
    @Published var readings: [QueryResult] = []
    @Published var isBusy = false
    @Published var activity = "Ready to scan"
    @Published var progress = 0.0
    @Published var error: String?
    @Published var refreshedAt: Date?
    @Published var hasScanned = false
    private let service = BridgeService()
    private var operation: Task<Void, Never>?
    private var generation = UUID()

    init() { updateAdapters() }

    var adapter: Adapter? { adapters.first { $0.id == adapterID } }
    var selected: MAC? { devices.first { $0.text == selectedID } }
    var hasResults: Bool { !readings.isEmpty }
    var responseCount: Int { readings.filter { $0.status == "received" }.count }

    func updateAdapters() {
        adapters = Adapter.available()
        if !adapters.contains(where: { $0.id == adapterID }) {
            let saved = UserDefaults.standard.string(forKey: "selectedAdapter")
            adapterID = adapters.first(where: { $0.id == saved })?.id ?? adapters.first?.id ?? ""
        }
    }

    func scan() {
        cancel()
        updateAdapters()
        guard !adapterID.isEmpty else {
            error = "Connect an Ethernet adapter and a powered bridge, then scan again."
            return
        }
        UserDefaults.standard.set(adapterID, forKey: "selectedAdapter")
        devices = []; selectedID = nil; readings = []; refreshedAt = nil
        error = nil; isBusy = true; progress = 0; activity = "Looking for bridges…"
        hasScanned = false
        let token = generation, interface = adapterID
        operation = Task {
            do {
                let found = try await service.discover(interface: interface)
                guard generation == token, !Task.isCancelled else { return }
                devices = found; hasScanned = true
                if let device = found.first {
                    selectedID = device.text
                    try await load(device: device, interface: interface, token: token)
                } else { activity = "No bridges found" }
            } catch is CancellationError {
                return
            } catch {
                guard generation == token else { return }
                self.error = error.localizedDescription
                activity = "Couldn’t reach the bridge"
            }
            if generation == token { isBusy = false; operation = nil }
        }
    }

    func select(_ device: MAC) {
        guard !isBusy, selectedID != device.text else { return }
        selectedID = device.text
        refresh()
    }

    func refresh() {
        guard !isBusy, let device = selected else { return }
        cancel()
        readings = []; refreshedAt = nil; error = nil
        isBusy = true; progress = 0
        let token = generation, interface = adapterID
        operation = Task {
            do { try await load(device: device, interface: interface, token: token) }
            catch is CancellationError { return }
            catch {
                guard generation == token else { return }
                self.error = error.localizedDescription
                activity = "Refresh failed"
            }
            if generation == token { isBusy = false; operation = nil }
        }
    }

    private func load(device: MAC, interface: String, token: UUID) async throws {
        for (index, command) in NetAT.queries.enumerated() {
            try Task.checkCancellation()
            guard generation == token else { throw CancellationError() }
            activity = "Reading \(Self.fieldName(command).lowercased())…"
            let result = try await service.read(interface: interface, device: device, command: command)
            guard generation == token else { throw CancellationError() }
            readings.append(result)
            progress = Double(index + 1) / Double(NetAT.queries.count)
        }
        refreshedAt = Date()
        activity = responseCount == NetAT.queries.count ? "All settings refreshed" : "Some settings are unavailable"
    }

    func cancel() {
        generation = UUID()
        operation?.cancel(); operation = nil; isBusy = false
        activity = "Stopped"
    }

    func reading(_ command: String) -> QueryResult? { readings.first { $0.command == command } }
    func value(_ command: String, prefix: String) -> String? {
        guard let result = reading(command), result.status == "received" else { return nil }
        return result.response.components(separatedBy: .newlines)
            .first { $0.hasPrefix(prefix) }?
            .dropFirst(prefix.count).trimmingCharacters(in: .whitespacesAndNewlines)
    }
    var role: String {
        switch value("at+mode?", prefix: "+MODE:") {
        case "sta": return "Receiver"
        case "ap": return "Transmitter"
        case let role?: return role.uppercased()
        default: return "—"
        }
    }
    var ssid: String { value("at+ssid?", prefix: "+SSID:") ?? "—" }
    var bandwidth: String { value("at+bss_bw?", prefix: "+BSS_BW:")?.replacingOccurrences(of: "MHz", with: " MHz") ?? "—" }
    var power: String { value("at+txpower?", prefix: "+TXPOWER:")?.replacingOccurrences(of: "dbm", with: " dBm") ?? "—" }
    var security: String { value("at+keymgmt?", prefix: "+KEYMGMT:") ?? "—" }
    var channels: [String] {
        guard let text = value("at+chan_list?", prefix: "+CHAN_LIST:") else { return [] }
        return text.split(separator: ",").compactMap { part in
            guard let number = Double(part.trimmingCharacters(in: .whitespaces)) else { return nil }
            return String(format: number.truncatingRemainder(dividingBy: 10) == 0 ? "%.0f MHz" : "%.1f MHz", number / 10)
        }
    }
    var wirelessConnected: Bool? {
        guard let result = reading("at+conn_state"), result.status == "received" else { return nil }
        if result.response.contains("+DISCONNECT") { return false }
        if result.response.contains("+CONNECTED") { return true }
        return nil
    }

    static func fieldName(_ command: String) -> String {
        ["at+mode?": "Role", "at+ssid?": "Network name", "at+bss_bw?": "Bandwidth",
         "at+chan_list?": "Channels", "at+txpower?": "Transmit power",
         "at+keymgmt?": "Security", "at+conn_state": "Wireless link"][command] ?? command
    }

    func exportSnapshot() {
        guard let selected, !isBusy, !readings.isEmpty else { return }
        struct Snapshot: Encodable {
            let capturedAt: Date
            let interface: String
            let deviceMAC: String
            let changesMade = false
            let queries: [QueryResult]
        }
        let snapshot = Snapshot(capturedAt: refreshedAt ?? Date(), interface: adapterID,
                                deviceMAC: selected.text, queries: readings)
        let panel = NSSavePanel()
        panel.title = "Export Bridge Snapshot"
        panel.nameFieldStringValue = "halow-snapshot.json"
        panel.canCreateDirectories = true
        panel.begin { [self] result in
            guard result == .OK, let url = panel.url else { return }
            do {
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                encoder.dateEncodingStrategy = .iso8601
                try encoder.encode(snapshot).write(to: url, options: .atomic)
                activity = "Snapshot exported"
            } catch { self.error = "Couldn’t export the snapshot: \(error.localizedDescription)" }
        }
    }
}
