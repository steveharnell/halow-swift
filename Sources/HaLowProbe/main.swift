// Native macOS read-only NetAT proof of concept. No third-party dependencies.
// This is a CLI transport prototype, not a finished SwiftUI application.
import Foundation
import Darwin

struct ProbeError: Error, CustomStringConvertible {
    let description: String
    init(_ message: String) { description = message }
}

struct MAC: Equatable, Hashable, Codable {
    let bytes: [UInt8]
    init(_ text: String) throws {
        let parts = text.split(separator: ":", omittingEmptySubsequences: false)
        let decoded = parts.compactMap { $0.count == 2 ? UInt8($0, radix: 16) : nil }
        guard parts.count == 6, decoded.count == 6 else { throw ProbeError("Invalid MAC address") }
        bytes = decoded
    }
    init(bytes: [UInt8]) { precondition(bytes.count == 6); self.bytes = bytes }
    var text: String { bytes.map { String(format: "%02x", $0) }.joined(separator: ":") }
}

struct Packet {
    let kind: UInt8
    let destination: [UInt8]
    let source: [UInt8]
    let payload: [UInt8]
    func encode() throws -> [UInt8] {
        guard destination.count == 6, source.count == 6, payload.count <= 65520 else {
            throw ProbeError("Invalid NetAT packet size")
        }
        let length = UInt16(payload.count)
        return [kind, UInt8(length >> 8), UInt8(length & 0xff)] + destination + source + payload
    }
    static func decode(_ bytes: [UInt8]) -> Packet? {
        guard bytes.count >= 15 else { return nil }
        let length = Int(bytes[1]) << 8 | Int(bytes[2])
        guard bytes.count == 15 + length else { return nil }
        return Packet(kind: bytes[0], destination: Array(bytes[3..<9]),
                      source: Array(bytes[9..<15]), payload: Array(bytes[15...]))
    }
    func matches(kind expected: UInt8, cookie: [UInt8], target: MAC?) -> Bool {
        kind == expected && destination == cookie && (target == nil || source == target!.bytes)
    }
}

struct QueryResult: Codable {
    let command: String
    let response: String
    let receivedPackets: Int
    let sourceIPs: [String]
    let status: String
}

final class NetAT {
    let descriptor: Int32
    static let queries = ["at+mode?", "at+ssid?", "at+bss_bw?", "at+chan_list?",
                          "at+txpower?", "at+keymgmt?", "at+conn_state"]

    init(interface: String) throws {
        var index = if_nametoindex(interface)
        guard index != 0 else { throw ProbeError("Unknown network interface: \(interface)") }
        descriptor = Darwin.socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
        guard descriptor >= 0 else { throw ProbeError("socket: \(String(cString: strerror(errno)))") }
        do {
            var enabled: Int32 = 1
            guard setsockopt(descriptor, SOL_SOCKET, SO_BROADCAST, &enabled,
                             socklen_t(MemoryLayout<Int32>.size)) == 0,
                  setsockopt(descriptor, IPPROTO_IP, IP_BOUND_IF, &index,
                             socklen_t(MemoryLayout<UInt32>.size)) == 0 else {
                throw ProbeError("Socket setup: \(String(cString: strerror(errno)))")
            }
            var local = sockaddr_in()
            local.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
            local.sin_family = sa_family_t(AF_INET)
            local.sin_port = UInt16(56789).bigEndian
            local.sin_addr.s_addr = INADDR_ANY
            let result = withUnsafePointer(to: &local) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    Darwin.bind(descriptor, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }
            guard result == 0 else {
                throw ProbeError("Cannot bind UDP 56789; close other NetAT tools. \(String(cString: strerror(errno)))")
            }
        } catch { Darwin.close(descriptor); throw error }
    }
    deinit { Darwin.close(descriptor) }

    private func exchange(kind: UInt8, target: MAC?, text: String = "",
                          timeout: Double = 1.5) throws -> [(Packet, String)] {
        let cookie = (0..<6).map { _ in UInt8.random(in: 0...255) }
        let packet = Packet(kind: kind, destination: target?.bytes ?? Array(repeating: 255, count: 6),
                            source: cookie, payload: Array(text.utf8))
        let encoded = try packet.encode()
        var broadcast = sockaddr_in()
        broadcast.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        broadcast.sin_family = sa_family_t(AF_INET)
        broadcast.sin_port = UInt16(56789).bigEndian
        broadcast.sin_addr.s_addr = INADDR_BROADCAST
        let sent = encoded.withUnsafeBytes { buffer in
            withUnsafePointer(to: &broadcast) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    Darwin.sendto(descriptor, buffer.baseAddress, buffer.count, 0, $0,
                                  socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }
        }
        guard sent == encoded.count else { throw ProbeError("sendto: \(String(cString: strerror(errno)))") }
        let deadline = ProcessInfo.processInfo.systemUptime + timeout
        var replies: [(Packet, String)] = []
        while ProcessInfo.processInfo.systemUptime < deadline {
            var pollFD = pollfd(fd: descriptor, events: Int16(POLLIN), revents: 0)
            let remaining = max(1, Int32((deadline - ProcessInfo.processInfo.systemUptime) * 1000))
            let ready = Darwin.poll(&pollFD, 1, min(remaining, 100))
            if ready < 0 {
                if errno == EINTR { continue }
                throw ProbeError("poll: \(String(cString: strerror(errno)))")
            }
            if ready == 0 { continue }
            guard pollFD.revents & Int16(POLLIN) != 0 else {
                throw ProbeError("UDP receive socket became unavailable")
            }
            var bytes = [UInt8](repeating: 0, count: 65535)
            var remote = sockaddr_in()
            var remoteLength = socklen_t(MemoryLayout<sockaddr_in>.size)
            let received = bytes.withUnsafeMutableBytes { buffer in
                withUnsafeMutablePointer(to: &remote) {
                    $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                        Darwin.recvfrom(descriptor, buffer.baseAddress, buffer.count, MSG_DONTWAIT,
                                        $0, &remoteLength)
                    }
                }
            }
            if received < 0 {
                if errno == EAGAIN || errno == EWOULDBLOCK || errno == EINTR { continue }
                throw ProbeError("recvfrom: \(String(cString: strerror(errno)))")
            }
            guard remote.sin_port == UInt16(56789).bigEndian,
                  let reply = Packet.decode(Array(bytes.prefix(received))),
                  reply.matches(kind: kind == 1 ? 2 : 4, cookie: cookie, target: target) else { continue }
            var address = remote.sin_addr
            var addressText = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
            _ = inet_ntop(AF_INET, &address, &addressText, socklen_t(INET_ADDRSTRLEN))
            let sourceIP = String(decoding: addressText.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
            replies.append((reply, sourceIP))
        }
        return replies
    }

    func discover() throws -> [MAC] {
        let replies = try exchange(kind: 1, target: nil)
        return Array(Set(replies.map { MAC(bytes: $0.0.source) })).sorted { $0.text < $1.text }
    }
    func query(_ command: String, target: MAC) throws -> QueryResult {
        guard Self.queries.contains(command) else { throw ProbeError("Command is outside the read-only allowlist") }
        var replies = try exchange(kind: 3, target: target, text: command)
        if replies.isEmpty { replies = try exchange(kind: 3, target: target, text: command) }
        let response = replies.map { String(decoding: $0.0.payload, as: UTF8.self) }.joined()
        let status = replies.isEmpty ? "timeout" :
            (response.contains("valid cmds:") ? "unsupported" : (response.contains("ERROR") ? "device_error" : "received"))
        return QueryResult(command: command, response: response, receivedPackets: replies.count,
                           sourceIPs: Array(Set(replies.map { $0.1 })).sorted(), status: status)
    }
}

func runSelfTests() throws {
    func require(_ value: Bool, _ message: String) throws {
        if !value { throw ProbeError("Self-test failed: \(message)") }
    }
    let cookie: [UInt8] = [1, 2, 3, 4, 5, 6]
    let mac = try MAC("02:00:00:00:00:01")
    let fixture = [UInt8]([4, 0, 15] + cookie + mac.bytes + Array("+MODE:sta\r\nOK\r\n".utf8))
    guard let reply = Packet.decode(fixture) else { throw ProbeError("Valid fixture rejected") }
    try require(reply.matches(kind: 4, cookie: cookie, target: mac), "valid reply rejected")
    try require(!reply.matches(kind: 4, cookie: Array(repeating: 9, count: 6), target: mac), "foreign cookie accepted")
    try require(!reply.matches(kind: 4, cookie: cookie, target: MAC(bytes: Array(repeating: 7, count: 6))), "foreign device accepted")
    try require(!reply.matches(kind: 2, cookie: cookie, target: mac), "wrong response kind accepted")
    try require(Packet.decode(Array(fixture.dropLast())) == nil, "truncated payload accepted")
    try require(Packet.decode([4, 0, 0]) == nil, "short header accepted")
    let request = try Packet(kind: 3, destination: mac.bytes, source: cookie, payload: Array("at+mode?".utf8)).encode()
    try require(request[1] == 0 && request[2] == 8, "request length is not big endian")
    try require(!NetAT.queries.contains("at+fwupg"), "upgrade unexpectedly allowed")
    print("8 protocol and read-only checks passed")
}

do {
    let arguments = Array(CommandLine.arguments.dropFirst())
    if arguments == ["--self-test"] { try runSelfTests(); exit(0) }
    guard arguments.count == 2 || arguments.count == 4,
          arguments[0] == "--interface", (arguments.count == 2 || arguments[2] == "--mac") else {
        throw ProbeError("Usage: halow-probe --interface en8 [--mac 02:00:00:00:00:01]\n       halow-probe --self-test")
    }
    let client = try NetAT(interface: arguments[1])
    let devices = try client.discover()
    let selected: MAC
    if arguments.count == 4 {
        selected = try MAC(arguments[3])
        guard devices.contains(selected) else { throw ProbeError("Selected device did not respond to discovery") }
    } else {
        guard devices.count == 1 else { throw ProbeError("Found \(devices.count) devices: \(devices.map(\.text).joined(separator: ", ")). Select one with --mac.") }
        selected = devices[0]
    }
    let results = try NetAT.queries.map { try client.query($0, target: selected) }
    struct Snapshot: Codable {
        let capturedAt: String
        let interface: String
        let deviceMAC: String
        let discoveredMACs: [String]
        let changesMade: Bool
        let firmwareImageExtracted: Bool
        let queries: [QueryResult]
    }
    let snapshot = Snapshot(capturedAt: ISO8601DateFormatter().string(from: Date()), interface: arguments[1],
                            deviceMAC: selected.text, discoveredMACs: devices.map(\.text), changesMade: false,
                            firmwareImageExtracted: false, queries: results)
    let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let output = try encoder.encode(snapshot)
    FileHandle.standardOutput.write(output); FileHandle.standardOutput.write(Data([10]))
} catch {
    FileHandle.standardError.write(Data("\(error)\n".utf8)); exit(1)
}
