#!/bin/bash
set -euo pipefail

IPA_HOST="${IPA_HOST:-172.16.99.63}"
IPA_SSH_USER="${IPA_SSH_USER:-codex}"
IPA_FQDN="${IPA_FQDN:-ipa01.rfc1918.host}"
IPA_REALM="${IPA_REALM:-RFC1918.HOST}"
IPA_DOMAIN="${IPA_DOMAIN:-rfc1918.host}"
IPA_IP="${IPA_IP:-172.16.99.63}"
IPA_IDSTART="${IPA_IDSTART:-200000}"
IPA_IDMAX="${IPA_IDMAX:-399999}"
IDENTITY_SECRET_FILE="${IDENTITY_SECRET_FILE:-/root/operator-private/identity/ipa01.env}"

mkdir -p "$(dirname "${IDENTITY_SECRET_FILE}")"
chmod 0700 "$(dirname "${IDENTITY_SECRET_FILE}")"

if [[ ! -f "${IDENTITY_SECRET_FILE}" ]]; then
  {
    printf 'IPA_ADMIN_PASSWORD=%q\n' "$(openssl rand -base64 30)"
    printf 'IPA_DS_PASSWORD=%q\n' "$(openssl rand -base64 30)"
    printf 'RADIUS_LDAP_PASSWORD=%q\n' "$(openssl rand -base64 30)"
  } > "${IDENTITY_SECRET_FILE}"
  chmod 0600 "${IDENTITY_SECRET_FILE}"
fi

ssh_target="${IPA_SSH_USER}@${IPA_HOST}"
remote_env="/tmp/stage5-identity-bootstrap.env"
scp -q "${IDENTITY_SECRET_FILE}" "${ssh_target}:${remote_env}"
ssh -o BatchMode=yes -o ConnectTimeout=20 "${ssh_target}" \
  "sudo install -d -m 0700 /root/stage5-identity && sudo install -m 0600 ${remote_env} /root/stage5-identity/bootstrap.env && rm -f ${remote_env}"

ssh -o BatchMode=yes -o ConnectTimeout=20 "${ssh_target}" sudo bash -s -- \
  "${IPA_FQDN}" \
  "${IPA_REALM}" \
  "${IPA_DOMAIN}" \
  "${IPA_IP}" \
  "${IPA_IDSTART}" \
  "${IPA_IDMAX}" << 'REMOTE'
set -euo pipefail

ipa_fqdn="$1"
ipa_realm="$2"
ipa_domain="$3"
ipa_ip="$4"
ipa_idstart="$5"
ipa_idmax="$6"

# shellcheck source=/dev/null
source /root/stage5-identity/bootstrap.env

hostnamectl set-hostname "${ipa_fqdn}"
if ! grep -qE "^[[:space:]]*${ipa_ip}[[:space:]].*${ipa_fqdn}" /etc/hosts; then
  printf '%s %s %s\n' "${ipa_ip}" "${ipa_fqdn}" "${ipa_fqdn%%.*}" >>/etc/hosts
fi

dnf -y install \
  freeipa-server \
  freeipa-server-dns \
  freeradius \
  freeradius-ldap \
  freeradius-utils \
  oddjob-mkhomedir \
  sssd \
  sssd-tools

if ! command -v ipa >/dev/null 2>&1 || ! ipa server-find >/dev/null 2>&1; then
  ipa-server-install -U \
    --realm "${ipa_realm}" \
    --domain "${ipa_domain}" \
    --hostname "${ipa_fqdn}" \
    --ip-address "${ipa_ip}" \
    --idstart "${ipa_idstart}" \
    --idmax "${ipa_idmax}" \
    --no-ntp \
    --setup-kra \
    --ds-password "${IPA_DS_PASSWORD}" \
    --admin-password "${IPA_ADMIN_PASSWORD}"
fi

systemctl enable --now ipa.service
systemctl enable --now oddjobd.service

if command -v firewall-cmd >/dev/null 2>&1 && systemctl is-active --quiet firewalld; then
  firewall-cmd --permanent --add-service=freeipa-ldap
  firewall-cmd --permanent --add-service=freeipa-ldaps
  firewall-cmd --permanent --add-service=kerberos
  firewall-cmd --permanent --add-service=kpasswd
  firewall-cmd --permanent --add-service=http
  firewall-cmd --permanent --add-service=https
  firewall-cmd --permanent --add-port=1812/udp
  firewall-cmd --permanent --add-port=1813/udp
  firewall-cmd --reload
fi

kinit admin <<<"${IPA_ADMIN_PASSWORD}"
ipa group-find linux-admin >/dev/null 2>&1 || ipa group-add linux-admin --desc="Linux administrators"
ipa group-find ci-builder >/dev/null 2>&1 || ipa group-add ci-builder --desc="CI and builder farm operators"
ipa group-find network-admin >/dev/null 2>&1 || ipa group-add network-admin --desc="Network device administrators"
ipa group-find network-readonly >/dev/null 2>&1 || ipa group-add network-readonly --desc="Network device read-only operators"
ipa hostgroup-find linux-servers >/dev/null 2>&1 || ipa hostgroup-add linux-servers --desc="Managed Linux hosts"
ipa hostgroup-find container-hosts >/dev/null 2>&1 || ipa hostgroup-add container-hosts --desc="Podman container hosts"
ipa hostgroup-find ci-builders >/dev/null 2>&1 || ipa hostgroup-add ci-builders --desc="CI builder nodes"

if ! ipa user-show radiusd >/dev/null 2>&1; then
  printf '%s\n%s\n' "${RADIUS_LDAP_PASSWORD}" "${RADIUS_LDAP_PASSWORD}" | ipa user-add radiusd \
    --first=RADIUS \
    --last=Bridge \
    --shell=/sbin/nologin \
    --homedir=/var/empty/radiusd \
    --password || true
fi

ipa config-show >/dev/null
echo "FreeIPA bootstrap validated for ${ipa_fqdn}"
REMOTE
