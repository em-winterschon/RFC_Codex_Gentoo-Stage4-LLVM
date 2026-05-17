# FMT2 OpenVPN Compatibility Transport

## Current State

Temporary FMT2/SFO200 reachability is provided by the M70 Forge admin host:

- Host: `admin-sun99-forge-099070.rfc1918.host`
- LAN IP: `172.16.99.70`
- Service: `openvpn.fmt2`
- Tunnel interface: `tun-fmt2`
- Tunnel local IP: `192.168.132.2`
- Tunnel peer IP: `192.168.132.1`
- Remote endpoint: `gw-sfo200-vip.vernetzen.io:11948/tcp`

This is a compatibility shim for the legacy OPNsense static-key OpenVPN tunnel.
It is not the desired long-term transport. Keep BigNetwork and/or RouterOS
replacement work active until a cleaner permanent path is validated.

## Secret Handling

Runtime files live outside the repo:

- `/root/operator-private/fmt2-openvpn/runtime/fmt2-client.active.conf`
- `/root/operator-private/fmt2-openvpn/runtime/fmt2-static.key`

On M70:

- `/etc/openvpn/fmt2.conf`
- `/etc/openvpn/fmt2/fmt2-static.key`

Do not commit the static key or the full private runtime config. If this service
is automated, store secret material through Ansible Vault and render it only to
the target host with `0600` permissions.

## Routed Prefixes

CCR2004 has temporary static routes pointing at M70:

- `10.100.99.0/24 via 172.16.99.70`
- `10.200.99.0/24 via 172.16.99.70`
- `172.18.20.0/24 via 172.16.99.70`

M70 has OpenVPN-installed routes through `tun-fmt2`:

- `10.100.99.0/24 via 192.168.132.1`
- `10.200.99.0/24 via 192.168.132.1`
- `172.18.20.0/24 via 192.168.132.1`

M70 also enables IPv4 forwarding and temporary SNAT from `172.16.99.0/24` to the
three FMT2 prefixes. This keeps return routing simple while the legacy FMT2
router state is still being reconstructed.

## Validation

Validated from M70 through `tun-fmt2`:

- `192.168.132.1`
- `10.200.99.1`
- `172.18.20.1`
- `172.18.20.4`
- `10.100.99.1`

Validated from X12AGAIN through normal LAN routing via CCR2004:

- `10.200.99.1`
- `172.18.20.1`
- `172.18.20.4`
- `10.100.99.1`

Targeted TCP scan from X12AGAIN showed:

- `10.200.99.1`: HTTPS open, SSH/HTTP/Check_MK agent filtered
- `172.18.20.1`: HTTPS open, SSH/HTTP/Check_MK agent filtered
- `172.18.20.4`: SSH and HTTPS open, HTTP/Check_MK agent filtered
- `10.100.99.1`: host up, tested TCP ports filtered

## Backout

On CCR2004:

```routeros
/ip route remove [find where comment~"FORGE TEMP FMT2 OpenVPN"]
```

On M70:

```sh
rc-service openvpn.fmt2 stop
rc-update del openvpn.fmt2 default
iptables -D FORWARD -j FORGE-FMT2-OPENVPN 2>/dev/null || true
iptables -F FORGE-FMT2-OPENVPN 2>/dev/null || true
iptables -X FORGE-FMT2-OPENVPN 2>/dev/null || true
iptables -t nat -D POSTROUTING -s 172.16.99.0/24 -d 10.100.99.0/24 -o tun-fmt2 -j MASQUERADE 2>/dev/null || true
iptables -t nat -D POSTROUTING -s 172.16.99.0/24 -d 10.200.99.0/24 -o tun-fmt2 -j MASQUERADE 2>/dev/null || true
iptables -t nat -D POSTROUTING -s 172.16.99.0/24 -d 172.18.20.0/24 -o tun-fmt2 -j MASQUERADE 2>/dev/null || true
/etc/init.d/iptables save
```

Only disable `net.ipv4.ip_forward` if no other M70 role needs forwarding.
