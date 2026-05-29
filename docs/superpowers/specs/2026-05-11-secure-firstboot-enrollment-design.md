# Secure First-Boot Enrollment Design

## Goal

Remove the K10 reboot-durable AAA blocker without embedding `/etc/krb5.keytab`
or any long-lived host secret in HTTP netboot artifacts.

## Architecture

The supported first implementation is FreeIPA one-time password enrollment
delivered through a short-lived encrypted first-boot bundle. The bundle contains
only enrollment material required to let the host create its own durable
`/etc/krb5.keytab` during first boot. The netboot rootfs remains generic and
safe to serve over unauthenticated HTTP.

The first cryptographic transport is `age` because `app-crypt/age` is available
in the Gentoo tree and can be included in Stage5 host profiles without Guru repo
dependencies. Tang/Clevis is tracked as an optional NBDE-style hardening layer
after a Gentoo Guru version is explicitly pinned and tested. `aespipe` is kept
as a break-glass/manual archive option, not the unattended enrollment default.

## Enrollment Flow

1. FreeIPA controller creates or updates the host entry.
2. FreeIPA controller generates a host OTP with `ipa host-add --random` or the
   equivalent `host-mod` OTP reset flow.
3. Provisioning automation writes a JSON bundle with realm, domain, FQDN, IPA
   server, CA trust expectation, expiration timestamp, and OTP.
4. Provisioning automation encrypts the bundle to the target host's `age`
   recipient.
5. The target boots from the generic Stage5 rootfs and starts an OpenRC
   first-boot enrollment service.
6. The first-boot script fetches the encrypted bundle, decrypts it with the
   local `age` identity file, checks expiry and FQDN, enrolls the host, starts
   SSSD, validates NSS/SSH/PAM, and deletes the consumed bundle.
7. The installed host keeps the generated `/etc/krb5.keytab`; the netboot image
   never contains it.

## Files

- `profile-package-lists/stage5-secure-firstboot-enrollment.packages` adds
  `app-crypt/age` and bootstrap helpers.
- `profile-definitions/secure-firstboot-enrollment.yml` describes the
  enrollment method, package layer, and optional Clevis/Tang future path.
- `scripts/validate_secure_firstboot_bundle.py` validates plaintext bundle JSON
  before encryption and rejects expired bundles or secret hygiene mistakes.
- `scripts/render_secure_firstboot_bundle.py` renders plaintext bundle JSON from
  non-secret CLI input plus an OTP supplied through an environment variable.
- `roles/secure_firstboot_enrollment` installs the OpenRC service and local
  enrollment script scaffold.
- `tests/shell/test_secure_firstboot_enrollment.sh` covers file wiring, package
  availability declarations, secret-hygiene checks, and validator behavior.

## Security Rules

- No `krb5.keytab` content is allowed in rootfs artifacts, docs, manifests, or
  repo-tracked files.
- The plaintext OTP is accepted only from an environment variable or Ansible
  Vault-backed runtime variable.
- Rendered plaintext bundles are operator-private build artifacts and must not
  be committed.
- Encrypted bundles must include an expiry and expected FQDN.
- Tang-only decryption is not sufficient for host enrollment secrets because
  Tang proves network presence, not host identity.
- Clevis/Tang is allowed only as `tpm2+tang` or another host-bound policy after
  the Gentoo Guru package set is pinned and tested.

## Acceptance Criteria

- Stage5 profile metadata can include the first-boot enrollment package layer.
- The bundle validator accepts a valid unexpired bundle.
- The bundle validator rejects missing OTP, wrong method, missing expiry, and
  expired bundles.
- The first-boot role renders an OpenRC service disabled by default unless the
  host opts in.
- K10 E2ET can change the durable-enrollment blocker from "no design" to
  "requires disk install or secure first-boot bundle apply".
