# macOS app plan

Build a SwiftUI app that discovers compatible HaLow bridges on a selected Ethernet adapter, displays their current configuration, and applies deliberate changes with readback verification. The existing Swift CLI establishes the transport; a firmware replacement is not required.

## Milestones

1. **Discovery and overview.** Enumerate Ethernet adapters, discover devices, select a device, and display the seven verified properties. Distinguish disconnected wireless status from an unreachable device or unsupported command.
2. **Draft editor.** Keep pending edits separate from live state. Add role, SSID, credentials, bandwidth, and channel controls after validating each setter's syntax and limits on the connected firmware. Validate full field contents and reject command delimiters/newlines.
3. **Apply and verify.** Refresh the baseline, show changed fields, apply commands sequentially, and read each setting back. Report a partial apply using verified device state; the underlying protocol does not provide an atomic multi-setting transaction. Changes may interrupt the paired radio link.
4. **Persistence and recovery.** Test save behavior and planned restarts with both units. Do not infer persistent storage merely from a successful setter response, or promise automatic rollback after losing the link.

Firmware upload, factory reset, and raw flash access are outside the first release.

## Architecture

Use a `BridgeDevice` identity model, a typed `BridgeConfiguration`, a command capability/dialect adapter, and a `NetATTransport` actor owning the UDP socket. A SwiftUI view model exposes discovery, refresh, draft editing, and apply progress. Keep command syntax and parsing outside views. Run socket operations away from the main actor and support cancellation.

Start with the verified legacy reads in [protocol.md](protocol.md). Firmware generations differ. Do not derive setters solely from getter names or enable controls solely because commands appear in a newer source release.

Match replies by cookie and identifier, use bounded timeouts, and serialize transactions. Later write support must handle uncertain state after timeout. Credential exports should be opt-in, with secrets omitted from routine logs and diagnostic captures.

## macOS packaging

Include `NSLocalNetworkUsageDescription` and validate local-network permissions using a stable signing identity. Evaluate the outgoing and incoming network capabilities needed by a sandboxed app for broadcast send and wildcard-bound UDP receive. The multicast entitlement is not required on macOS; an iOS port has separate requirements.

The current executable has been tested as a CLI. That does not validate permissions or behavior for a signed, sandboxed SwiftUI app.

## Validation

Completed: native Swift compilation, eight protocol/read-only checks, live discovery, and all seven configuration/status reads. Device settings were not changed.

Next: the SwiftUI discovery/overview screen, followed by one validated set/readback operation and then multi-field updates. Test unplug/replug, multiple radios, malformed/delayed replies, unsupported command dialects, denied local-network access, interrupted apply, paired-unit compatibility, and persistence after a planned restart.

References: [Apple local network privacy](https://developer.apple.com/documentation/technotes/tn3179-understanding-local-network-privacy) and [incoming network entitlement](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.security.network.server).
