# HaLow Swift

Native Swift tools for configuring REUMAR/Taixin-compatible Wi-Fi HaLow Ethernet bridges on macOS.

The native **SwiftUI macOS window** discovers bridges on a selected network adapter and displays their role, SSID, channel bandwidth, channel list, configured transmit power, security mode, and wireless connection state. It supports refresh, cancellation, response details, and local JSON snapshot export. The companion command-line reader uses the same shared transport.

The prototype has been compiled and tested against a connected REUMAR bridge. Discovery and all seven queries succeeded. Eight protocol checks also passed. Configuration writes and firmware operations are not implemented.

## Launch the graphical app

```sh
bash scripts/build-app.sh
open "dist/HaLow Swift.app"
```

The build script creates a locally signed development app with a native window and app icon. It scans an active Ethernet adapter on launch. Choose another adapter in the sidebar when needed. Snapshot exports contain the device identifier and SSID and are saved only when requested.

The window currently displays live settings. Configuration editing and firmware operations are not implemented. This local development build is not a notarized or sandboxed distribution build.

## Command-line reader

Requires macOS and an installed Swift toolchain, supplied by Xcode or the Xcode command-line tools. The Swift package declares Swift tools 5.9 or newer; the package was built with the installed Xcode compiler.

```sh
swift build
swift run halow-probe --self-test
swift run halow-probe --interface en8
```

Replace `en8` with the network adapter connected to your bridge. If several devices respond, select the intended device using its discovered MAC:

```sh
swift run halow-probe --interface en8 --mac 02:00:00:00:00:01
```

That address is an illustrative example. The program requires the selected device to respond to discovery before querying it.

Output is JSON. To keep a local capture:

```sh
swift run halow-probe --interface en8 > snapshot.json
```

Only one NetAT utility should bind UDP port 56789 at a time. Allow local-network access for the responsible app/program if macOS requests it. Administrator privileges were not required during the hardware validation.

## How it works

The bridge's NetAT protocol uses UDP port 56789 and a small binary header around AT command text. The implementation uses native BSD sockets through Swift's `Darwin` module, binds to the selected interface, and sends UDP broadcasts. Replies are correlated by a random transaction cookie and device identifier. This supports units that reply using source IP `0.0.0.0`.

The command allowlist contains seven reads. The executable cannot change configuration, reboot, reset, or flash firmware. It does not read passwords or keys, although JSON output includes device identifiers and the SSID. Keep captures local unless deliberately anonymized.

The transport currently uses fixed response windows, retries silent reads once, and joins multipart replies in arrival order. The GUI runs socket work on a separate actor and supports cancellation between transactions. Closing a pending operation can take up to the current transaction timeout. Firmware capability detection and distribution signing/sandbox validation remain future work.

## Project notes

- [App plan](docs/app-plan.md)
- [NetAT protocol and verified queries](docs/protocol.md)
- [Firmware research and upstream sources](docs/firmware-research.md)

The installed device firmware image has not been extracted. A public upstream source SDK was located for research, but it has not been matched to the installed firmware. This project communicates with the existing firmware and does not require replacing it.

This repository contains the Swift prototype and generalized research notes. Device captures, credentials, local network configuration, and third-party firmware archives are excluded.
