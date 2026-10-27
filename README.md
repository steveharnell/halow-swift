# HaLow Swift

Native Swift tools for configuring REUMAR/Taixin-compatible Wi-Fi HaLow Ethernet bridges on macOS.

The first milestone is a working **read-only command-line prototype**. It discovers a bridge on a selected network adapter and reads its role, SSID, channel bandwidth, channel list, configured transmit power, security mode, and wireless connection state. A SwiftUI configuration editor is planned.

The prototype has been compiled and tested against a connected REUMAR bridge. Discovery and all seven queries succeeded. Eight protocol checks also passed. Configuration writes and firmware operations are not implemented.

## Build and run

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

The transport currently uses fixed response windows, retries silent reads once, and joins multipart replies in arrival order. It is a CLI prototype; a GUI needs asynchronous execution and cancellation, interface enumeration, capability detection, and signed-app network permission validation.

## Project notes

- [App plan](docs/app-plan.md)
- [NetAT protocol and verified queries](docs/protocol.md)
- [Firmware research and upstream sources](docs/firmware-research.md)

The installed device firmware image has not been extracted. A public upstream source SDK was located for research, but it has not been matched to the installed firmware. This project communicates with the existing firmware and does not require replacing it.

This repository contains the Swift prototype and generalized research notes. Device captures, credentials, local network configuration, and third-party firmware archives are excluded.
