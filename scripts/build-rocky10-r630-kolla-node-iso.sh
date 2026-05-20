#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Build a Rocky Linux 10 R630 Kolla-node boot ISO with an embedded kickstart.

This installer is intentionally narrow:
  - IDSDM is used for /boot and /boot/efi.
  - The two Intel SSDSCKKB240G8R SATA devices are used as RAID1 OS media.
  - SAS data bays and Optane cache devices such as INTEL SSDPED1D480GA are excluded from clearpart.

Required environment:
  FORGE_AUTHORIZED_KEY  SSH public key installed for root and ADMIN_USER.

Optional environment:
  BASE_ISO              Source Rocky 10 boot ISO.
  OUT_ISO               Output custom ISO path.
  WORKDIR               Extraction/work directory.
  KS_PATH               Generated kickstart path.
  ISO_LABEL             Source ISO volume label. Auto-detected with isoinfo if unset.
  NODE_HOSTNAME         Installed host FQDN.
  ADMIN_USER            Non-root administrative user, default: verwalterin.
  STATIC_IP             Static management IP address.
  PREFIX                Static CIDR prefix length.
  NETMASK               Static netmask for installer boot args.
  GATEWAY               Static gateway.
  DNS                   Comma-separated DNS servers.
  INSTALL_NET_DEVICE    Installer network device selector, default: link.
  MGMT_BOND_ENABLED     Enable bond0 for management, default: false.
  MGMT_BOND_MEMBERS     Comma-separated bond0 members, default: bootnet,eno2np1.
  FRONTEND_BOND_MEMBERS Comma-separated bond1 members, default: eno3np2,eno4np3.
  MGMT_BOND_OPTIONS     NetworkManager bond0 options.
  FRONTEND_BOND_OPTIONS NetworkManager bond1 options.
  OS_DISK_MODEL         Required OS disk model substring, default: SSDSCKKB240G8R.
  IDSDM_MODEL           Required boot disk model substring, default: IDSDM.
  ROCKY_BASEOS_URL      Rocky 10 BaseOS install URL.
  ROCKY_APPSTREAM_URL   Rocky 10 AppStream repo URL.
EOF
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

: "${FORGE_AUTHORIZED_KEY:?FORGE_AUTHORIZED_KEY must contain the SSH public key to install}"

BASE_ISO="${BASE_ISO:-/srv/provisioning/iso/Rocky-10-x86_64-boot.iso}"
OUT_ISO="${OUT_ISO:-/srv/provisioning/iso/Rocky-10-r630-kolla-node.iso}"
WORKDIR="${WORKDIR:-/srv/provisioning/work/rocky10-r630-kolla-node}"
KS_PATH="${KS_PATH:-/srv/provisioning/ks/r630-kolla-node.ks}"
ISO_LABEL="${ISO_LABEL:-}"
NODE_HOSTNAME="${NODE_HOSTNAME:-kvm-sfo200-pri-9922.rfc1918.host}"
ADMIN_USER="${ADMIN_USER:-verwalterin}"
STATIC_IP="${STATIC_IP:-10.200.99.22}"
PREFIX="${PREFIX:-24}"
NETMASK="${NETMASK:-255.255.255.0}"
GATEWAY="${GATEWAY:-10.200.99.1}"
DNS="${DNS:-10.200.99.1,9.9.9.9}"
INSTALL_NET_DEVICE="${INSTALL_NET_DEVICE:-link}"
MGMT_BOND_ENABLED="${MGMT_BOND_ENABLED:-false}"
MGMT_BOND_MEMBERS="${MGMT_BOND_MEMBERS:-bootnet,eno2np1}"
FRONTEND_BOND_MEMBERS="${FRONTEND_BOND_MEMBERS:-eno3np2,eno4np3}"
MGMT_BOND_OPTIONS="${MGMT_BOND_OPTIONS:-mode=802.3ad,miimon=100,lacp_rate=fast,xmit_hash_policy=layer3+4}"
FRONTEND_BOND_OPTIONS="${FRONTEND_BOND_OPTIONS:-mode=802.3ad,miimon=100,lacp_rate=fast,xmit_hash_policy=layer3+4}"
OS_DISK_MODEL="${OS_DISK_MODEL:-SSDSCKKB240G8R}"
IDSDM_MODEL="${IDSDM_MODEL:-IDSDM}"
ROCKY_BASEOS_URL="${ROCKY_BASEOS_URL:-https://dl.rockylinux.org/pub/rocky/10/BaseOS/x86_64/os/}"
ROCKY_APPSTREAM_URL="${ROCKY_APPSTREAM_URL:-https://dl.rockylinux.org/pub/rocky/10/AppStream/x86_64/os/}"

for cmd in awk grep mkisofs mount rsync sed sort umount; do
  command -v "$cmd" >/dev/null || {
    echo "missing required command: $cmd" >&2
    exit 1
  }
done

if [[ ! -s "$BASE_ISO" ]]; then
  echo "base ISO not found or empty: $BASE_ISO" >&2
  exit 1
fi

if [[ -z "$ISO_LABEL" ]]; then
  command -v isoinfo >/dev/null || {
    echo "ISO_LABEL is unset and isoinfo is unavailable for source ISO label detection" >&2
    exit 1
  }
  ISO_LABEL="$(isoinfo -d -i "$BASE_ISO" | awk -F': ' '/Volume id:/ {print $2; exit}')"
fi

if [[ -z "$ISO_LABEL" ]]; then
  echo "failed to determine ISO label for $BASE_ISO" >&2
  exit 1
fi

mkdir -p "$(dirname "$OUT_ISO")" "$(dirname "$KS_PATH")" "$WORKDIR"
rm -rf "$WORKDIR/extract" "$WORKDIR/mnt"
mkdir -p "$WORKDIR/extract" "$WORKDIR/mnt"

network_line="network --device=${INSTALL_NET_DEVICE} --bootproto=static --ip=${STATIC_IP} --netmask=${NETMASK} --gateway=${GATEWAY} --nameserver=${DNS} --hostname=${NODE_HOSTNAME} --activate"
BOOT_DNS1="${DNS%%,*}"
BOOT_DNS2=""
if [[ "$DNS" == *,* ]]; then
  BOOT_DNS2="${DNS#*,}"
  BOOT_DNS2="${BOOT_DNS2%%,*}"
fi
BOOT_IP_DNS_ARGS="$BOOT_DNS1"
if [[ -n "$BOOT_DNS2" && "$BOOT_DNS2" != "$BOOT_DNS1" ]]; then
  BOOT_IP_DNS_ARGS="${BOOT_DNS1}:${BOOT_DNS2}"
fi
boot_network_args="ip=${STATIC_IP}::${GATEWAY}:${NETMASK}:${NODE_HOSTNAME}:${INSTALL_NET_DEVICE}:none:${BOOT_IP_DNS_ARGS} rd.neednet=1 nameserver=${BOOT_DNS1}"
DNS_KEYFILE="$(printf '%s' "$DNS" | tr ',' ';');"

cat >"$KS_PATH" <<EOF
# RFC1918 FMT2 R630 Rocky Linux 10 Kolla node installer.
# This install fails closed unless IDSDM and exactly two ${OS_DISK_MODEL} OS disks are visible.
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
services --enabled=sshd,NetworkManager,chronyd,rsyslog
firstboot --disable

%pre --interpreter=/bin/bash --erroronfail --log=/tmp/r630-rocky10-kolla-pre.log
set -euo pipefail
os_model="${OS_DISK_MODEL}"
idsdm_model="${IDSDM_MODEL}"
os_candidates=()
sd_candidates=()

disk_size_gib() {
  local dev=\$1
  awk -v sectors="\$(cat "/sys/block/\${dev}/size")" 'BEGIN { printf "%.0f", sectors * 512 / 1024 / 1024 / 1024 }'
}

disk_model() {
  local dev=\$1
  tr -d '[:space:]' <"/sys/block/\${dev}/device/model" 2>/dev/null || true
}

for sysdev in /sys/block/sd*; do
  [ -e "\$sysdev" ] || continue
  dev="\$(basename "\$sysdev")"
  model="\$(disk_model "\$dev")"
  size_gib="\$(disk_size_gib "\$dev")"
  case "\$model" in
    *HUSMM3240ASS*|*INTELSSDPED1D480GA*)
      echo "Skipping protected data/cache media: \$dev \$model \${size_gib}GiB"
      continue
      ;;
  esac
  if [[ "\$model" == *"\$os_model"* ]] && [ "\$size_gib" -ge 100 ] && [ "\$size_gib" -le 260 ]; then
    os_candidates+=("\$dev")
  fi
  if [[ "\$model" == *"\$idsdm_model"* ]] && [ "\$size_gib" -ge 8 ] && [ "\$size_gib" -le 100 ]; then
    sd_candidates+=("\$dev")
  fi
done

IFS=\$'\n' os_candidates=(\$(printf '%s\n' "\${os_candidates[@]}" | sort))
IFS=\$'\n' sd_candidates=(\$(printf '%s\n' "\${sd_candidates[@]}" | sort))
unset IFS

if [ "\${#os_candidates[@]}" -ne 2 ]; then
  echo "ERROR: expected exactly two ${OS_DISK_MODEL} OS disks, found \${#os_candidates[@]}: \${os_candidates[*]}" >&2
  lsblk -dn -o NAME,MODEL,SIZE,TYPE >&2 || true
  exit 1
fi

if [ "\${#sd_candidates[@]}" -lt 1 ]; then
  echo "ERROR: expected IDSDM boot media matching ${IDSDM_MODEL}" >&2
  lsblk -dn -o NAME,MODEL,SIZE,TYPE >&2 || true
  exit 1
fi

os_pri="\${os_candidates[0]}"
os_sec="\${os_candidates[1]}"
sd_pri="\${sd_candidates[0]}"

cat >/tmp/diskpart.cfg <<PART
ignoredisk --only-use=\$sd_pri,\$os_pri,\$os_sec
zerombr
clearpart --all --initlabel --drives=\$sd_pri,\$os_pri,\$os_sec
bootloader --location=mbr --driveorder=\$sd_pri --boot-drive=\$sd_pri --append="intel_iommu=on iommu=pt console=tty0 console=ttyS0,115200n8 crashkernel=auto net.ifnames=1"

part /boot/efi --asprimary --fstype="efi" --ondrive=\$sd_pri --size=600 --fsoptions="defaults,uid=0,gid=0,umask=077,shortname=winnt"
part /boot --asprimary --fstype="ext4" --ondrive=\$sd_pri --size=1024

part raid.13 --asprimary --fstype="mdmember" --ondrive=\$os_pri --size=8192
part raid.12 --asprimary --fstype="mdmember" --ondrive=\$os_pri --size=1 --grow
part raid.23 --asprimary --fstype="mdmember" --ondrive=\$os_sec --size=8192
part raid.22 --asprimary --fstype="mdmember" --ondrive=\$os_sec --size=1 --grow

raid swap --device=3 --fstype="swap" --level=RAID1 raid.13 raid.23
raid / --device=2 --fstype="xfs" --level=RAID1 raid.12 raid.22
PART

echo "Selected IDSDM boot media: \$sd_pri"
echo "Selected OS mirror media: \$os_pri \$os_sec"
cat /tmp/diskpart.cfg
%end

%include /tmp/diskpart.cfg

%packages
@^minimal-environment
bash-completion
chrony
curl
dnf-plugins-core
ethtool
gcc
git
iproute
iputils
libffi-devel
mdadm
net-tools
NetworkManager
openssh-server
openssl-devel
pciutils
podman
python3
python3-devel
python3-pip
rsyslog
sudo
tar
vim-minimal
wget
xfsprogs
%end

%post --interpreter=/bin/bash --log=/root/r630-rocky10-kolla-post.log
set -euo pipefail

install -d -m 0700 /root/.ssh
cat >/root/.ssh/authorized_keys <<'KEYEOF'
${FORGE_AUTHORIZED_KEY}
KEYEOF
chmod 0600 /root/.ssh/authorized_keys

if ! id "${ADMIN_USER}" >/dev/null 2>&1; then
  useradd -m -G wheel -s /bin/bash "${ADMIN_USER}"
fi
passwd -l "${ADMIN_USER}" || true
install -d -m 0700 "/home/${ADMIN_USER}/.ssh"
cp /root/.ssh/authorized_keys "/home/${ADMIN_USER}/.ssh/authorized_keys"
chown -R "${ADMIN_USER}:${ADMIN_USER}" "/home/${ADMIN_USER}/.ssh"
chmod 0600 "/home/${ADMIN_USER}/.ssh/authorized_keys"

install -d -m 0755 /etc/sudoers.d /etc/ssh/sshd_config.d
cat >/etc/sudoers.d/90-rfc1918-admin <<'SUDOEOF'
%wheel ALL=(ALL) NOPASSWD: ALL
SUDOEOF
chmod 0440 /etc/sudoers.d/90-rfc1918-admin

cat >/etc/ssh/sshd_config.d/10-rfc1918-kolla-node.conf <<'SSHEOF'
PermitRootLogin prohibit-password
PasswordAuthentication no
PubkeyAuthentication yes
SSHEOF

cat >/etc/modules-load.d/rfc1918-kolla-node.conf <<'MODEOF'
bonding
8021q
vfio
vfio_pci
MODEOF

systemctl enable sshd NetworkManager chronyd rsyslog podman.socket

# Kolla-Ansible target host prerequisites live on the node; kolla-ansible itself runs on the deployer VM.
dnf -y config-manager --set-enabled crb || true

install -d -m 0700 /etc/NetworkManager/system-connections
rm -f /etc/NetworkManager/system-connections/bond0*.nmconnection
rm -f /etc/NetworkManager/system-connections/bond1*.nmconnection

cat >/etc/NetworkManager/system-connections/bootnet.nmconnection <<'NMEOF'
[connection]
id=bootnet
uuid=__BOOTNET_UUID__
type=ethernet
interface-name=bootnet
autoconnect=true

[ethernet]

[ipv4]
method=manual
address1=${STATIC_IP}/${PREFIX},${GATEWAY}
dns=${DNS_KEYFILE}
dns-search=rfc1918.host;

[ipv6]
method=ignore
NMEOF

sed -i "s/__BOOTNET_UUID__/\$(uuidgen)/" /etc/NetworkManager/system-connections/bootnet.nmconnection

if [[ "${MGMT_BOND_ENABLED}" == "true" ]]; then
  rm -f /etc/NetworkManager/system-connections/bootnet.nmconnection
  cat >/etc/NetworkManager/system-connections/bond0.nmconnection <<'NMEOF'
[connection]
id=bond0
uuid=__BOND0_UUID__
type=bond
interface-name=bond0
autoconnect=true

[bond]
options=${MGMT_BOND_OPTIONS}

[ipv4]
method=manual
address1=${STATIC_IP}/${PREFIX},${GATEWAY}
dns=${DNS_KEYFILE}
dns-search=rfc1918.host;

[ipv6]
method=ignore
NMEOF

  sed -i "s/__BOND0_UUID__/\$(uuidgen)/" /etc/NetworkManager/system-connections/bond0.nmconnection

  IFS=',' read -r -a mgmt_bond_members <<<"${MGMT_BOND_MEMBERS}"
  for member in "\${mgmt_bond_members[@]}"; do
    cat >"/etc/NetworkManager/system-connections/bond0-\${member}.nmconnection" <<NMEOF
[connection]
id=bond0-\${member}
uuid=\$(uuidgen)
type=ethernet
interface-name=\${member}
autoconnect=true
master=bond0
slave-type=bond

[ethernet]

[ipv4]
method=disabled

[ipv6]
method=ignore
NMEOF
  done
else
  echo "R630 management LACP remains disabled by default; bootnet owns ${STATIC_IP}/${PREFIX}."
fi

cat >/etc/NetworkManager/system-connections/bond1.nmconnection <<'NMEOF'
[connection]
id=bond1
uuid=__BOND1_UUID__
type=bond
interface-name=bond1
autoconnect=true

[bond]
options=${FRONTEND_BOND_OPTIONS}

[ipv4]
method=disabled

[ipv6]
method=ignore
NMEOF

sed -i "s/__BOND1_UUID__/\$(uuidgen)/" /etc/NetworkManager/system-connections/bond1.nmconnection

IFS=',' read -r -a frontend_bond_members <<<"${FRONTEND_BOND_MEMBERS}"
for member in "\${frontend_bond_members[@]}"; do
  cat >"/etc/NetworkManager/system-connections/bond1-\${member}.nmconnection" <<NMEOF
[connection]
id=bond1-\${member}
uuid=\$(uuidgen)
type=ethernet
interface-name=\${member}
autoconnect=true
master=bond1
slave-type=bond

[ethernet]

[ipv4]
method=disabled

[ipv6]
method=ignore
NMEOF
done

chmod 0600 /etc/NetworkManager/system-connections/*.nmconnection

cat >/etc/motd <<'MOTDEOF'
RFC1918 FMT2 R630 Rocky Linux 10 Kolla node.
Run kolla-ansible from ops-fmt2-kolla-deployer-9928; do not store Kolla secrets in plaintext git.
MOTDEOF

restorecon -Rv /root/.ssh "/home/${ADMIN_USER}/.ssh" /etc/ssh/sshd_config.d /etc/sudoers.d || true
dnf -y clean all || true
%end
EOF

mount -o loop,ro "$BASE_ISO" "$WORKDIR/mnt"
rsync -aH --delete "$WORKDIR/mnt/" "$WORKDIR/extract/"
umount "$WORKDIR/mnt"
cp "$KS_PATH" "$WORKDIR/extract/ks-r630-kolla-node.cfg"

python3 - "$WORKDIR/extract" "$ISO_LABEL" "$boot_network_args" <<'PY'
from pathlib import Path
import sys

root = Path(sys.argv[1])
label = sys.argv[2]
boot_network_args = sys.argv[3]
extra = (
    f"inst.stage2=hd:LABEL={label} "
    "inst.ks=hd:LABEL={label}:/ks-r630-kolla-node.cfg "
    f"{boot_network_args} "
    "inst.text console=tty0 console=ttyS0,115200n8"
)

grub = root / "EFI/BOOT/grub.cfg"
text = grub.read_text(encoding="utf-8")
entry = f"""menuentry 'RFC1918 R630 Rocky Linux 10 Kolla node install' --class fedora --class gnu-linux --class gnu --class os {{
    linuxefi /images/pxeboot/vmlinuz {extra}
    initrdefi /images/pxeboot/initrd.img
}}

"""
text = text.replace('set default="1"', 'set default="0"')
text = text.replace("set timeout=60", "set timeout=5")
if "RFC1918 R630 Rocky Linux 10 Kolla node install" not in text:
    marker = "### BEGIN /etc/grub.d/10_linux ###"
    if marker in text:
        text = text.replace(marker, marker + "\n" + entry, 1)
    else:
        text = entry + text
grub.write_text(text, encoding="utf-8")

isolinux = root / "isolinux/isolinux.cfg"
if isolinux.exists():
    iso = isolinux.read_text(encoding="utf-8")
    stanza = f"""
label rfc1918-kolla-node
  menu label ^RFC1918 R630 Rocky Linux 10 Kolla node install
  kernel vmlinuz
  append initrd=initrd.img {extra}
"""
    iso = iso.replace("timeout 600", "timeout 50")
    if "label rfc1918-kolla-node" not in iso:
        iso += stanza
    isolinux.write_text(iso, encoding="utf-8")
PY

rm -f "$OUT_ISO"
efi_boot_image="images/efiboot.img"
if [[ ! -f "$WORKDIR/extract/$efi_boot_image" ]]; then
  efi_boot_image="images/eltorito.img"
fi

if [[ -d "$WORKDIR/extract/isolinux" ]]; then
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
    -e "$efi_boot_image" \
    -no-emul-boot \
    "$WORKDIR/extract"
else
  mkisofs \
    -o "$OUT_ISO" \
    -V "$ISO_LABEL" \
    -J -joliet-long -R \
    -e "$efi_boot_image" \
    -no-emul-boot \
    "$WORKDIR/extract"
fi

sha256sum "$OUT_ISO" | tee "$OUT_ISO.sha256"
echo "built: $OUT_ISO"
