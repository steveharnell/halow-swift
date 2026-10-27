# Firmware research

The installed firmware image has **not** been extracted. Its exact revision remains unverified. The native Swift configuration transport works with the existing bridge firmware.

A public source SDK from the chip maker was retrieved and inspected as a reference:

| Field | Value |
| --- | --- |
| Upstream repository | [Taixin-Semiconductor/TXW8301_WNB](https://github.com/Taixin-Semiconductor/TXW8301_WNB) |
| Source release | `v2.4.1.3-43933` |
| Pinned commit | `0e273c80ee141a8ee1273027d57a1aeaa8ec843c` |
| [Source archive](https://codeload.github.com/Taixin-Semiconductor/TXW8301_WNB/zip/0e273c80ee141a8ee1273027d57a1aeaa8ec843c) size | 8,522,535 bytes |
| Archive SHA-256 | `e0bd77d1d2c8038799a64059babdab957f56f4882647dad6b62f0bd9eaff62ee` |

The archive passed ZIP integrity checking and contains source, headers, libraries, and build support, but no `.bin` firmware images. This upstream release has not been matched to the tested REUMAR unit. The source archive and any locally captured device data are not redistributed in this repository.

The reviewed Ethernet updater API exposes discovery, version reports, parameter access, reboot, and firmware upload. No installed-image download operation was identified. Its firmware-file reader reads a host-side file rather than retrieving flash from the device. A low-level `NOR_RD` diagnostic appears in current source declarations, but the available declaration did not establish a safe flash-dump interface, and it was not invoked.

This does not prove that hardware or bootloader readback is unavailable. A complete installed-image backup remains separate research, potentially involving a verified debug/programmer interface or external-flash method.

The firmware source is useful for studying command handlers and differences among firmware generations. Keep upstream and component license notices if incorporating third-party code. The native Swift transport was implemented separately from the C reference.

References:

- [Pinned release README](https://github.com/Taixin-Semiconductor/TXW8301_WNB/tree/0e273c80ee141a8ee1273027d57a1aeaa8ec843c)
- [Current AT command registration](https://github.com/Taixin-Semiconductor/TXW8301_WNB/blob/0e273c80ee141a8ee1273027d57a1aeaa8ec843c/project/atcmd.c)
- [Updater protocol declarations](https://github.com/TXW8301/TXW8301-FMAC-linux-driver/blob/main/tools/test_app/libota.h)
- [Updater protocol implementation](https://github.com/TXW8301/TXW8301-FMAC-linux-driver/blob/main/tools/test_app/libota.c)
- [Host-side firmware-file reader](https://github.com/TXW8301/TXW8301-FMAC-linux-driver/blob/main/tools/test_app/hgota.c)
