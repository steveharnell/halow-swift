# NetAT protocol

The transport below was validated on a REUMAR HaLow Ethernet bridge. Firmware variants may support different commands; treat the verified query list separately from commands present in newer SDKs.

Use IPv4 UDP with source and destination port `56789`. On macOS, bind an unconnected datagram socket to the selected interface with `IP_BOUND_IF`, enable `SO_BROADCAST`, bind to the wildcard local address, and send to `255.255.255.255`.

The tested unit returned NetAT responses from source IP `0.0.0.0`. A source address is not a reliable management endpoint. Match the protocol message type, correlation cookie, device identifier, source port, and datagram length.

## Packet layout

| Offset | Bytes | Meaning |
| --- | --- | --- |
| 0 | 1 | Message type |
| 1 | 2 | Payload length, big endian |
| 3 | 6 | Destination identifier, or response correlation cookie |
| 9 | 6 | Request correlation cookie, or responding device identifier |
| 15 | variable | Command or response text |

Message types are `1` discovery request, `2` discovery response, `3` AT command request, and `4` AT command response. Discovery uses six `0xff` bytes as the destination identifier. Command requests target a discovered identifier. A fresh six-byte random cookie distinguishes each transaction. The tested commands worked without an appended newline.

## Verified read commands

| Property | Command |
| --- | --- |
| Role | `at+mode?` |
| SSID | `at+ssid?` |
| Channel bandwidth | `at+bss_bw?` |
| Channel list | `at+chan_list?` |
| Configured transmit power | `at+txpower?` |
| Security mode | `at+keymgmt?` |
| Wireless connection state | `at+conn_state` |

These are the prototype's complete command allowlist. No configuration setters have been validated by this project.

The Taixin channel convention represents frequency in tenths of MHz. For example, the generic device value `9160` represents 916 MHz. The transmit-power query reports a setting, not an RF measurement.

The tested unit did not support the firmware-version queries attempted. A newer upstream source release includes different command names and query forms, including `WIFIMODE` and `=?`. A future app should detect read capabilities instead of assuming that a source release identifies a connected device's firmware.

## Reliability

Serialize transactions. Collect replies within a bounded window, and distinguish a timeout, unsupported command, device error, and a valid disconnected state. UDP can lose, duplicate, and reorder packets. The reviewed response format has no per-part sequence number; reconstructing incomplete multipart replies by guessing is not reliable.

For future writes, a timeout means unknown state. Read the setting back before deciding whether another setter is necessary. Do not automatically retry actions such as pairing, reset, or reboot.

## References

- [Taixin driver distribution's NetAT implementation](https://github.com/TXW8301/TXW8301-FMAC-linux-driver/blob/main/tools/test_app/libnetat.c)
- [Chip maker's bridge documentation](https://taixin-semi.com/en/docs/txw8301/latest/%E6%B3%B0%E8%8A%AFAH%E7%BD%91%E6%A1%A5%28V2.x%29%E4%BD%BF%E7%94%A8%E8%AF%B4%E6%98%8E?navigation=1&series=txw8301)
- [Chip maker's FAQ](https://www.taixin-semi.com/zh/docs/txw8301/latest/%E6%B3%B0%E8%8A%AFAH%E6%96%B9%E6%A1%88FAQ)
