import Foundation
import Darwin
import HaLowCore

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
