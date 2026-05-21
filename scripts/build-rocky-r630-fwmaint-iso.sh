#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat << 'EOF'
Build a Rocky 8 boot ISO with an embedded firmware-maintenance kickstart.

Required environment:
  FORGE_AUTHORIZED_KEY  SSH public key installed for root on the maintenance OS.

Optional environment:
  BASE_ISO              Source Rocky boot ISO.
  OUT_ISO               Output custom ISO path.
  WORKDIR               Extraction/work directory.
  KS_PATH               Generated kickstart path.
  ISO_LABEL             ISO volume label to preserve for inst.stage2.
  MAINT_HOSTNAME        Maintenance OS hostname.
  STATIC_IP             Static installer/OS IP address.
  NETMASK               Static netmask.
  GATEWAY               Static gateway.
  DNS                   Static DNS servers.
  INSTALL_BOOTPROTO     Installer network method: static or dhcp.
  INSTALL_NET_DEVICE    Installer network device name or kickstart selector.
  ISCSI_PORTAL          iSCSI target portal IP.
  ISCSI_TARGET          iSCSI target IQN.
  ISCSI_BOOT_TARGET     iSCSI target IQN used by the installed OS netroot.
  ISCSI_INITIATOR       iSCSI initiator IQN.
  BOOTNET_IFNAME        Installed OS initramfs NIC name.
  BOOTNET_MAC           Installed OS boot NIC MAC for ifname= mapping.
  STORAGE_MODE          Storage selection mode: iscsi or local.
  LOCAL_DISK_BY_ID      Preferred /dev/disk/by-id substring for local mode.
  ROCKY_BASEOS_URL      Rocky BaseOS install URL.
  ROCKY_APPSTREAM_URL   Rocky AppStream repo URL.
EOF
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

: "${FORGE_AUTHORIZED_KEY:?FORGE_AUTHORIZED_KEY must contain the SSH public key to install}"

BASE_ISO="${BASE_ISO:-/srv/provisioning/iso/Rocky-8.10-x86_64-boot.iso}"
OUT_ISO="${OUT_ISO:-/srv/provisioning/iso/Rocky-8.10-r630-pri-fwmaint.iso}"
WORKDIR="${WORKDIR:-/srv/provisioning/work/rocky-8.10-pri-fwmaint}"
KS_PATH="${KS_PATH:-/srv/provisioning/ks/r630-pri-fwmaint.ks}"
ISO_LABEL="${ISO_LABEL:-Rocky-8-10-x86_64-dvd}"
MAINT_HOSTNAME="${MAINT_HOSTNAME:-kvm-sfo200-pri-9922-fwmaint.rfc1918.host}"
STATIC_IP="${STATIC_IP:-10.200.99.22}"
NETMASK="${NETMASK:-255.255.255.0}"
GATEWAY="${GATEWAY:-10.200.99.1}"
DNS="${DNS:-9.9.9.9,1.1.1.1}"
INSTALL_BOOTPROTO="${INSTALL_BOOTPROTO:-static}"
INSTALL_NET_DEVICE="${INSTALL_NET_DEVICE:-link}"
ISCSI_PORTAL="${ISCSI_PORTAL:-10.200.99.24}"
ISCSI_TARGET="${ISCSI_TARGET:-iqn.2026-05.host.rfc1918:fmt2.pri-firmware-maint}"
ISCSI_BOOT_TARGET="${ISCSI_BOOT_TARGET:-${ISCSI_TARGET}}"
ISCSI_INITIATOR="${ISCSI_INITIATOR:-iqn.2026-05.host.rfc1918:fmt2.pri-x710-1}"
BOOTNET_IFNAME="${BOOTNET_IFNAME:-bootnet}"
BOOTNET_MAC="${BOOTNET_MAC:-24:6e:96:42:65:d2}"
STORAGE_MODE="${STORAGE_MODE:-iscsi}"
LOCAL_DISK_BY_ID="${LOCAL_DISK_BY_ID:-virtio-pri_fwmaint}"
ROCKY_BASEOS_URL="${ROCKY_BASEOS_URL:-https://download.rockylinux.org/pub/rocky/8/BaseOS/x86_64/os/}"
ROCKY_APPSTREAM_URL="${ROCKY_APPSTREAM_URL:-https://download.rockylinux.org/pub/rocky/8/AppStream/x86_64/os/}"

for cmd in mount umount rsync mkisofs sed awk; do
  command -v "$cmd" > /dev/null || {
    echo "missing required command: $cmd" >&2
    exit 1
  }
done

if [[ ! -s "$BASE_ISO" ]]; then
  echo "base ISO not found or empty: $BASE_ISO" >&2
  exit 1
fi

mkdir -p "$(dirname "$OUT_ISO")" "$(dirname "$KS_PATH")" "$WORKDIR"
rm -rf "$WORKDIR/extract" "$WORKDIR/mnt"
mkdir -p "$WORKDIR/extract" "$WORKDIR/mnt"

case "$INSTALL_BOOTPROTO" in
static)
  network_line="network --device=${INSTALL_NET_DEVICE} --bootproto=static --ip=${STATIC_IP} --netmask=${NETMASK} --gateway=${GATEWAY} --nameserver=${DNS} --hostname=${MAINT_HOSTNAME} --activate"
  boot_network_args="ip=${STATIC_IP}::${GATEWAY}:${NETMASK}:${MAINT_HOSTNAME}:${INSTALL_NET_DEVICE}:none rd.neednet=1"
  ;;
dhcp)
  network_line="network --device=${INSTALL_NET_DEVICE} --bootproto=dhcp --hostname=${MAINT_HOSTNAME} --activate"
  boot_network_args="ip=dhcp rd.neednet=1"
  ;;
*)
  echo "INSTALL_BOOTPROTO must be static or dhcp, got: $INSTALL_BOOTPROTO" >&2
  exit 1
  ;;
esac

cat > "$KS_PATH" << EOF
# RFC1918 R630 firmware-maintenance installer.
# This install must fail closed unless the expected iSCSI LUN is visible.
text
eula --agreed
reboot
url --url="${ROCKY_BASEOS_URL}"
repo --name="AppStream" --baseurl="${ROCKY_APPSTREAM_URL}"
lang en_US.UTF-8
keyboard --vckeymap=us --xlayouts='us'
timezone America/Los_Angeles --utc
${network_line}
rootpw --lock
selinux --permissive
firewall --disabled
services --enabled=sshd,NetworkManager
firstboot --disable

%pre --interpreter=/bin/bash --erroronfail --log=/tmp/r630-fwmaint-pre.log
set -euo pipefail
target="${ISCSI_TARGET}"
portal="${ISCSI_PORTAL}"
initiator="${ISCSI_INITIATOR}"
storage_mode="${STORAGE_MODE}"
local_disk_by_id="${LOCAL_DISK_BY_ID}"
disk=""

udevadm settle || true

case "\$storage_mode" in
  iscsi)
    echo "Preparing iSCSI session: initiator=\$initiator target=\$target portal=\$portal:3260"
    modprobe iscsi_tcp || true
    mkdir -p /etc/iscsi
    printf 'InitiatorName=%s\n' "\$initiator" >/etc/iscsi/initiatorname.iscsi

    if command -v iscsid >/dev/null 2>&1; then
      iscsid || true
    fi

    if command -v iscsiadm >/dev/null 2>&1; then
      iscsiadm -m discovery -t sendtargets -p "\$portal:3260" || true
      iscsiadm -m node -T "\$target" -p "\$portal:3260" --login || true
    elif command -v iscsistart >/dev/null 2>&1; then
      iscsistart -i "\$initiator" -t "\$target" -g 1 -a "\$portal" -p 3260 || true
    else
      echo "ERROR: neither iscsiadm nor iscsistart exists in installer environment" >&2
      exit 1
    fi
    ;;
  local)
    echo "Preparing local seed-disk install: by-id substring=\$local_disk_by_id"
    ;;
  *)
    echo "ERROR: unsupported STORAGE_MODE=\$storage_mode" >&2
    exit 1
    ;;
esac

for _ in 1 2 3 4 5 6 7 8 9 10; do
  udevadm settle || true
  if { [ "\$storage_mode" = "iscsi" ] && ls /dev/disk/by-path/*iscsi* >/dev/null 2>&1; } ||
     { [ "\$storage_mode" = "local" ] && ls /dev/disk/by-id/*"\$local_disk_by_id"* >/dev/null 2>&1; }; then
    break
  fi
  sleep 2
done

if [ "\$storage_mode" = "iscsi" ]; then
  for path in /dev/disk/by-path/*iscsi*; do
    [ -e "\$path" ] || continue
    case "\$path" in
      *"\$portal"*"\$target"*|*"\$target"*)
        resolved="\$(readlink -f "\$path")"
        base="\$(basename "\$resolved")"
        if [ -b "/dev/\$base" ]; then
          disk="\$base"
          break
        fi
        ;;
    esac
  done
else
  for path in /dev/disk/by-id/*"\$local_disk_by_id"*; do
    [ -e "\$path" ] || continue
    resolved="\$(readlink -f "\$path")"
    base="\$(basename "\$resolved")"
    if [ -b "/dev/\$base" ]; then
      disk="\$base"
      break
    fi
  done

  if [ -z "\$disk" ]; then
    for sysdev in /sys/block/vd* /sys/block/sd* /sys/block/nvme*n*; do
      [ -e "\$sysdev" ] || continue
      base="\$(basename "\$sysdev")"
      sectors="\$(cat "\$sysdev/size" 2>/dev/null || echo 0)"
      case "\$base" in loop*|sr*|dm-*) continue ;; esac
      if [ "\$sectors" -gt 41943040 ]; then
        disk="\$base"
        break
      fi
    done
  fi
fi

if [ "\$storage_mode" = "iscsi" ] && [ -z "\$disk" ]; then
  for sysdev in /sys/block/sd* /sys/block/nvme*n*; do
    [ -e "\$sysdev" ] || continue
    base="\$(basename "\$sysdev")"
    props="\$(udevadm info --query=property --path="\$sysdev" 2>/dev/null || true)"
    if printf '%s\n' "\$props" | grep -F "\$target" >/dev/null; then
      disk="\$base"
      break
    fi
  done
fi

if [ -z "\$disk" ] || [ ! -b "/dev/\$disk" ]; then
  echo "ERROR: expected install disk not found for STORAGE_MODE=\$storage_mode" >&2
  ls -l /dev/disk/by-path || true
  ls -l /dev/disk/by-id || true
  exit 1
fi

cat >/tmp/part-include <<PART
ignoredisk --only-use=\$disk
zerombr
clearpart --all --initlabel --drives=\$disk
bootloader --location=mbr --boot-drive=\$disk --driveorder=\$disk --append="console=tty0 console=ttyS0,115200n8 net.ifnames=1 rd.iscsi.initiator=${ISCSI_INITIATOR}"
part /boot/efi --fstype=efi --size=600 --ondisk=\$disk
part /boot --fstype=xfs --size=1024 --ondisk=\$disk
part swap --size=4096 --ondisk=\$disk
part / --fstype=xfs --size=8192 --grow --ondisk=\$disk
PART

echo "Selected install disk: /dev/\$disk"
cat /tmp/part-include
%end

%include /tmp/part-include

%packages
@^minimal-environment
openssh-server
NetworkManager
curl
wget
tar
gzip
bzip2
xz
vim-minimal
bash-completion
pciutils
usbutils
iproute
net-tools
ethtool
lsscsi
sg3_utils
smartmontools
nvme-cli
iscsi-initiator-utils
dracut-network
grub2-efi-x64
shim-x64
efibootmgr
dnf-utils
python3
%end

%post --interpreter=/bin/bash --log=/root/r630-fwmaint-post.log
set -euo pipefail
mkdir -p /root/.ssh
cat >/root/.ssh/authorized_keys <<'KEYEOF'
${FORGE_AUTHORIZED_KEY}
KEYEOF
chmod 700 /root/.ssh
chmod 600 /root/.ssh/authorized_keys
restorecon -Rv /root/.ssh || true

mkdir -p /etc/ssh/sshd_config.d
cat >/etc/ssh/sshd_config.d/10-rfc1918-fwmaint.conf <<'SSHEOF'
PermitRootLogin prohibit-password
PasswordAuthentication no
PubkeyAuthentication yes
SSHEOF

cat >/etc/yum.repos.d/dell-system-update.repo <<'REPOEOF'
[dell-system-update_independent]
name=Dell System Update - OS Independent
baseurl=https://linux.dell.com/repo/hardware/dsu/os_independent/
enabled=1
gpgcheck=0

[dell-system-update_dependent]
name=Dell System Update - RHEL8 x86_64
baseurl=https://linux.dell.com/repo/hardware/dsu/os_dependent/RHEL8_64/
enabled=1
gpgcheck=0
REPOEOF

systemctl enable sshd NetworkManager
nmcli connection add type ethernet ifname '*' con-name r630-fwmaint-static autoconnect yes ipv4.method manual ipv4.addresses ${STATIC_IP}/24 ipv4.gateway ${GATEWAY} ipv4.dns "$(printf '%s' "${DNS}" | tr ',' ' ')" || true
mkdir -p /etc/iscsi /etc/dracut.conf.d
printf 'InitiatorName=%s\n' "${ISCSI_INITIATOR}" >/etc/iscsi/initiatorname.iscsi

cat >/etc/dracut.conf.d/90-rfc1918-iscsi-root.conf <<'DRACUTEOF'
# The installed maintenance OS boots with explicit static iSCSI root arguments
# from GRUB. Do not embed rd.iscsi.firmware/ip=ibft in initramfs; Dell iBFT
# data can diverge from the target name that Linux must log into.
add_dracutmodules+=" network iscsi "
force_drivers+=" ixgbe iscsi_tcp "
hostonly_cmdline="no"
DRACUTEOF

grub_extra="rd.neednet=1 ifname=${BOOTNET_IFNAME}:${BOOTNET_MAC} ip=${STATIC_IP}::${GATEWAY}:${NETMASK}:${MAINT_HOSTNAME}:${BOOTNET_IFNAME}:none nameserver=${DNS%%,*} rd.iscsi.initiator=${ISCSI_INITIATOR} netroot=iscsi:${ISCSI_PORTAL}::3260:0:${ISCSI_BOOT_TARGET} rd.iscsi.param=node.session.timeo.replacement_timeout=30 console=tty0 console=ttyS0,115200n8 net.ifnames=1"
if grep -q '^GRUB_CMDLINE_LINUX=' /etc/default/grub; then
  old_cmdline="\$(sed -n 's/^GRUB_CMDLINE_LINUX="\\(.*\\)"/\\1/p' /etc/default/grub)"
  sed -i "s|^GRUB_CMDLINE_LINUX=.*|GRUB_CMDLINE_LINUX=\"\${grub_extra} \${old_cmdline}\"|" /etc/default/grub
else
  printf 'GRUB_CMDLINE_LINUX="%s"\n' "\$grub_extra" >>/etc/default/grub
fi

dracut -f --regenerate-all
grub2-mkconfig -o /boot/grub2/grub.cfg
if [ -d /boot/efi/EFI/rocky ]; then
  grub2-mkconfig -o /boot/efi/EFI/rocky/grub.cfg || true
  mkdir -p /boot/efi/EFI/BOOT
  [ -f /boot/efi/EFI/rocky/shimx64.efi ] && cp -f /boot/efi/EFI/rocky/shimx64.efi /boot/efi/EFI/BOOT/BOOTX64.EFI || true
  [ -f /boot/efi/EFI/rocky/grubx64.efi ] && cp -f /boot/efi/EFI/rocky/grubx64.efi /boot/efi/EFI/BOOT/grubx64.efi || true
fi
dnf -y clean all || true
%end
EOF

mount -o loop,ro "$BASE_ISO" "$WORKDIR/mnt"
rsync -aH --delete "$WORKDIR/mnt/" "$WORKDIR/extract/"
umount "$WORKDIR/mnt"
cp "$KS_PATH" "$WORKDIR/extract/ks-r630-pri-fwmaint.cfg"

python3 - "$WORKDIR/extract" "$ISO_LABEL" "$boot_network_args" << 'PY'
from pathlib import Path
import sys

root = Path(sys.argv[1])
label = sys.argv[2]
boot_network_args = sys.argv[3]
extra = (
    f"inst.stage2=hd:LABEL={label} "
    f"inst.ks=hd:LABEL={label}:/ks-r630-pri-fwmaint.cfg "
    f"{boot_network_args} "
    "inst.text console=tty0 console=ttyS0,115200n8"
)

grub = root / "EFI/BOOT/grub.cfg"
text = grub.read_text()
entry = f"""menuentry 'RFC1918 R630 pri firmware maintenance install' --class fedora --class gnu-linux --class gnu --class os {{
    linuxefi /images/pxeboot/vmlinuz {extra}
    initrdefi /images/pxeboot/initrd.img
}}

"""
text = text.replace('set default="1"', 'set default="0"')
text = text.replace("set timeout=60", "set timeout=5")
if "RFC1918 R630 pri firmware maintenance install" not in text:
    marker = "### BEGIN /etc/grub.d/10_linux ###"
    if marker in text:
        text = text.replace(marker, marker + "\n" + entry, 1)
    else:
        text = entry + text
grub.write_text(text)

isolinux = root / "isolinux/isolinux.cfg"
if isolinux.exists():
    iso = isolinux.read_text()
    stanza = f"""
label rfc1918-fwmaint
  menu label ^RFC1918 R630 pri firmware maintenance install
  kernel vmlinuz
  append initrd=initrd.img {extra}
"""
    iso = iso.replace("timeout 600", "timeout 50")
    if "label rfc1918-fwmaint" not in iso:
        iso += stanza
    isolinux.write_text(iso)
PY

rm -f "$OUT_ISO"
mkisofs \
  -o "$OUT_ISO" \
  -V "$ISO_LABEL" \
  -J -joliet-long -R \
  -b isolinux/isolinux.bin \
  -c isolinux/boot.cat \
  -no-emul-boot \
  -boot-load-size 4 \
  -boot-info-table \
  -eltorito-alt-boot \
  -e images/efiboot.img \
  -no-emul-boot \
  "$WORKDIR/extract"

sha256sum "$OUT_ISO" | tee "$OUT_ISO.sha256"
echo "built: $OUT_ISO"
