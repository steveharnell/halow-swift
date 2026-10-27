# macOS app plan

A native SwiftUI window now discovers compatible HaLow bridges on a selected Ethernet adapter and displays live configuration. It includes refresh, cancellation, response details, and JSON export. The GUI and CLI share the same transport; a firmware replacement is not required. Editing and applying configuration remain planned work.

## Milestones

1. **Discovery and overview — implemented.** Enumerate Ethernet adapters, discover devices, select a device, and display the seven verified properties. Distinguish disconnected wireless status from an unreachable device or unsupported command.
2. **Draft editor.** Keep pending edits separate from live state. Add role, SSID, credentials, bandwidth, and channel controls after validating each setter's syntax and limits on the connected firmware. Validate full field contents and reject command delimiters/newlines.
3. **Apply and verify.** Refresh the baseline, show changed fields, apply commands sequentially, and read each setting back. Report a partial apply using verified device state; the underlying protocol does not provide an atomic multi-setting transaction. Changes may interrupt the paired radio link.
4. **Persistence and recovery.** Test save behavior and planned restarts with both units. Do not infer persistent storage merely from a successful setter response, or promise automatic rollback after losing the link.

Firmware upload, factory reset, and raw flash access are outside the first release.

## Architecture

The implemented `HaLowCore` target provides the common NetAT protocol and read-only transport. The GUI's `BridgeService` actor runs socket transactions away from the main actor. Its `BridgeModel` drives discovery, selected-device readings, progress, cancellation, and snapshot export. Each transaction closes its socket before the next transaction begins. Add typed configuration drafts and a command capability/dialect adapter when implementing writes.

Start with the verified legacy reads in [protocol.md](protocol.md). Firmware generations differ. Do not derive setters solely from getter names or enable controls solely because commands appear in a newer source release.

Match replies by cookie and identifier, use bounded timeouts, and serialize transactions. Later write support must handle uncertain state after timeout. Credential exports should be opt-in, with secrets omitted from routine logs and diagnostic captures.

## macOS packaging

Include `NSLocalNetworkUsageDescription` and validate local-network permissions using a stable signing identity. Evaluate the outgoing and incoming network capabilities needed by a sandboxed app for broadcast send and wildcard-bound UDP receive. The multicast entitlement is not required on macOS; an iOS port has separate requirements.

The build script supplies a local ad hoc signature and the local-network usage description for a development app. A Developer ID signature, notarization, and sandbox validation remain separate distribution work.

## Validation

Completed: native Swift compilation, eight protocol/read-only checks, and live discovery with all seven configuration/status reads in the graphical app. Refresh, cancellation followed by refresh, and local JSON export were exercised through the running window. The exported file contained all seven successful readings. App bundle signature verification passed. Device settings were not changed.

Next: validate one set/readback operation and then multi-field updates. Test unplug/replug, multiple radios, malformed/delayed replies, unsupported command dialects, denied local-network access, interrupted apply, paired-unit compatibility, and persistence after a planned restart.

References: [Apple local network privacy](https://developer.apple.com/documentation/technotes/tn3179-understanding-local-network-privacy) and [incoming network entitlement](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.security.network.server).
