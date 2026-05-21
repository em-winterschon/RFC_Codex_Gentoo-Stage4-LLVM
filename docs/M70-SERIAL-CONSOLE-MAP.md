# M70 Serial Console Map

Captured from `admin-sun99-forge-099070` on 2026-05-21.

This document records the current USB RS232 console inventory on the M70 Forge
node. Use the stable `/dev/serial/by-id/...` paths for automation. The
`/dev/ttyUSB*` names are observed runtime aliases only and can move when another
USB serial adapter is attached.

## Current Assignments

| Target device | Function | Stable M70 path | Current tty | Baud | Evidence |
| --- | --- | --- | --- | --- | --- |
| `gw_rfc99_mkccr2004_16g` | CCR2004 gateway RouterOS console | `/dev/serial/by-id/usb-FTDI_FT232R_USB_UART_A9888PID-if00-port0` | `/dev/ttyUSB0` | `115200` | Previously validated prompt `[admin@gw-rfc99-mkccr2004-16g] >`; adapter still present on M70. |
| `sw_mgmt_mkcrs354` | CRS354 distribution switch RouterOS console | `/dev/serial/by-id/usb-FTDI_FT232R_USB_UART_AB0MRY3W-if00-port0` | `/dev/ttyUSB1` | `115200` | Previously validated prompt `[admin@sw-mgmt-mkcrs354] >`; adapter still present on M70. |
| `sw_spine_crs309_rfc99` | CRS309 spine switch RouterOS console | `/dev/serial/by-id/usb-FTDI_FT232R_USB_UART_AB0MRY3X-if00-port0` | `/dev/ttyUSB4` | `115200` | Previously validated prompt `[admin@sw-spine-crs309-rfc99] >`; adapter still present on M70. |

The older Hasslehoff-era notes showed CRS309 at `/dev/ttyUSB2`. On M70 it is
currently `/dev/ttyUSB4` because another dual-port FT2232H adapter is present
ahead of it in enumeration order.

## Unassigned Live Ports

| Adapter | Stable M70 path | Current tty | Notes |
| --- | --- | --- | --- |
| FTDI FT2232H `FT5W5FZH`, interface 0 | `/dev/serial/by-id/usb-FTDI_FT2232H_device_FT5W5FZH-if00-port0` | `/dev/ttyUSB2` | Unassigned. One of the FT2232H ports is known to be physically disconnected as of 2026-05-21. |
| FTDI FT2232H `FT5W5FZH`, interface 1 | `/dev/serial/by-id/usb-FTDI_FT2232H_device_FT5W5FZH-if01-port0` | `/dev/ttyUSB3` | Unassigned. Candidate for a future ATS/PDU/UPS RJ12 console adapter path after physical cabling is installed. |

Power devices in the SUN99/RFC99 rack use RJ12 serial ports. They are not
modeled as attached to M70 serial paths yet because the RJ12 adapter cabling is
not installed.

## Observed USB Topology

| USB path | Device | Stable identity |
| --- | --- | --- |
| `pci-0000:00:15.0-usb-0:2.1:1.0` | FTDI FT232R | `A9888PID` |
| `pci-0000:00:15.0-usb-0:2.2.1:1.0` | FTDI FT232R | `AB0MRY3W` |
| `pci-0000:00:15.0-usb-0:2.2.4:1.0` | FTDI FT232R | `AB0MRY3X` |
| `pci-0000:00:15.0-usb-0:2.4.4:1.0` | FTDI FT2232H interface 0 | `FT5W5FZH` |
| `pci-0000:00:15.0-usb-0:2.4.4:1.1` | FTDI FT2232H interface 1 | `FT5W5FZH` |

The attached CyberPower UPS appears as USB HID under the same M70 USB hub stack,
not as an RS232 console path.

## Draft Stable Aliases

The draft udev aliases live in
[`docs/udev/99-rfc99-serial-aliases.rules`](udev/99-rfc99-serial-aliases.rules).
They intentionally create only M70-local symlinks under `/dev/rfc99-serial/`.
Install them only after deciding whether M70 or a dedicated serial gateway VM is
the durable console host.

Target aliases:

| Alias | Target |
| --- | --- |
| `/dev/rfc99-serial/ccr2004-gateway` | `gw_rfc99_mkccr2004_16g` |
| `/dev/rfc99-serial/crs354-distribution` | `sw_mgmt_mkcrs354` |
| `/dev/rfc99-serial/crs309-spine` | `sw_spine_crs309_rfc99` |
| `/dev/rfc99-serial/spare-ft2232h-a` | Unassigned FT2232H interface 0 |
| `/dev/rfc99-serial/spare-ft2232h-b` | Unassigned FT2232H interface 1 |

## NetBox State

As of this capture, NetBox has no `dcim.console-server-port` records for M70.
It has console-port records for the ATS and old `gw_rfc99_mkcrs309`, but not for
the active CCR2004, CRS354, or CRS309 console links. The safe next NetBox action
is additive modeling only:

1. Add M70 console-server ports for the three known FTDI adapters.
2. Add console ports for `gw_rfc99_mkccr2004_16g`, `sw_mgmt_mkcrs354`, and
   `sw_spine_crs309_rfc99` if missing.
3. Cable those console-server ports to the corresponding device console ports.
4. Add ATS/PDU/UPS console links only after the RJ12 adapter paths are physically
   installed and identified.

No NetBox console cabling changes were applied during this note capture.

## Serial Tooling Readiness

The RouterOS serial helper exists at
[`scripts/routeros-serial-command.py`](../scripts/routeros-serial-command.py),
but M70 does not currently have the Python `serial` module installed.

Verified package plan on 2026-05-21:

```console
emerge -pv dev-python/pyserial
```

Portage would install:

- `dev-python/pyserial-3.5-r3`

No package install was performed during this capture. Install `dev-python/pyserial`
before using the RouterOS serial helper on M70.
