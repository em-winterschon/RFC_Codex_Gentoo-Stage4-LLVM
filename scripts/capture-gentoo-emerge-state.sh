#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat << 'EOF'
Usage: capture-gentoo-emerge-state.sh [OUTPUT_DIR]

Captures Gentoo Portage state useful for rebuilding a workstation profile:
  - /var/lib/portage/world
  - completed packages from emerge.log since the current boot
  - raw emerge command lines since the current boot
  - requested package target candidates from those commands

Run as root on a Gentoo host or LiveISO so /var/log/emerge.log is readable.
EOF
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

timestamp="$(date +%Y%m%d-%H%M%S)"
host_short="$(hostname -s 2> /dev/null || hostname)"
output_dir="${1:-gentoo-emerge-state-${host_short}-${timestamp}}"
boot_epoch="$(stat -c %Y /proc/1)"
boot_time="$(uptime -s 2> /dev/null || date -d "@${boot_epoch}" '+%F %T')"

mkdir -p "${output_dir}"

read_emerge_logs() {
  local log
  shopt -s nullglob
  for log in /var/log/emerge.log /var/log/emerge.log.*; do
    [[ -e "${log}" ]] || continue
    case "${log}" in
    *.gz) gzip -cd -- "${log}" ;;
    *.bz2) bzip2 -cd -- "${log}" ;;
    *.xz) xz -cd -- "${log}" ;;
    *) sed -n '1,$p' "${log}" ;;
    esac
  done
  shopt -u nullglob
}

normalize_versioned_atom() {
  local atom="$1"
  if command -v qatom > /dev/null 2>&1; then
    qatom -F '%{CATEGORY}/%{PN}' "${atom}" 2> /dev/null && return 0
  fi
  sed -E 's/-[0-9][^-]*(-r[0-9]+)?$//' <<< "${atom}"
}

resolve_target_atom() {
  local target="$1"
  local matches

  if [[ "${target}" == */* ]]; then
    printf '%s\n' "${target}"
    return 0
  fi

  if command -v qlist > /dev/null 2>&1; then
    matches="$(qlist -IC 2> /dev/null | awk -F/ -v pn="${target}" '$2 == pn { print }')"
    if [[ "$(wc -l <<< "${matches}")" -eq 1 && -n "${matches}" ]]; then
      printf '%s\n' "${matches}"
      return 0
    fi
  fi

  printf '%s\n' "${target}"
}

{
  printf 'host=%s\n' "$(hostname -f 2> /dev/null || hostname)"
  printf 'captured_at=%s\n' "$(date -Is)"
  printf 'boot_time=%s\n' "${boot_time}"
  printf 'boot_epoch=%s\n' "${boot_epoch}"
  printf 'emerge_log_cutoff=current boot\n'
  printf 'world_file=/var/lib/portage/world\n'
  printf 'qlist=%s\n' "$(command -v qlist || true)"
  printf 'qatom=%s\n' "$(command -v qatom || true)"
  printf 'emerge=%s\n' "$(command -v emerge || true)"
} > "${output_dir}/metadata.env"

if [[ -f /var/lib/portage/world ]]; then
  sort -u /var/lib/portage/world > "${output_dir}/world.atoms"
else
  : > "${output_dir}/world.atoms"
fi

read_emerge_logs | awk -v boot="${boot_epoch}" '
  $1 + 0 >= boot && /::: completed emerge / {
    atom = $0
    sub(/^.*::: completed emerge \([0-9]+ of [0-9]+\) /, "", atom)
    sub(/ to \/.*/, "", atom)
    print atom
  }
' | sort -u > "${output_dir}/merged-since-boot.versioned"

: > "${output_dir}/merged-since-boot.atoms"
while IFS= read -r atom; do
  [[ -n "${atom}" ]] || continue
  normalize_versioned_atom "${atom}" >> "${output_dir}/merged-since-boot.atoms"
done < "${output_dir}/merged-since-boot.versioned"
sort -u -o "${output_dir}/merged-since-boot.atoms" "${output_dir}/merged-since-boot.atoms"

read_emerge_logs | awk -v boot="${boot_epoch}" '
  $1 + 0 >= boot && /\*\*\* emerge / {
    line = $0
    sub(/^[0-9]+:[[:space:]]+\*\*\* emerge[[:space:]]+/, "", line)
    print line
  }
' | sort -u > "${output_dir}/emerge-commands-since-boot.raw"

awk '
  {
    for (i = 1; i <= NF; i++) {
      if ($i !~ /^-/ && $i !~ /^[[:space:]]*$/) {
        print $i
      }
    }
  }
' "${output_dir}/emerge-commands-since-boot.raw" | sort -u > "${output_dir}/requested-targets-since-boot.raw"

: > "${output_dir}/requested-targets-since-boot.resolved"
while IFS= read -r target; do
  [[ -n "${target}" ]] || continue
  resolve_target_atom "${target}" >> "${output_dir}/requested-targets-since-boot.resolved"
done < "${output_dir}/requested-targets-since-boot.raw"
sort -u -o "${output_dir}/requested-targets-since-boot.resolved" "${output_dir}/requested-targets-since-boot.resolved"

{
  sed -n '1,$p' "${output_dir}/world.atoms"
  awk '/^[[:alnum:]_.+-]+\/[[:alnum:]_.+-]+/ { print }' "${output_dir}/requested-targets-since-boot.resolved"
} | sort -u > "${output_dir}/primary-candidates.atoms"

{
  printf '# Gentoo Emerge State Capture\n\n'
  printf '%s\n' "- Host: \`$(hostname -f 2> /dev/null || hostname)\`"
  printf '%s\n' "- Captured at: \`$(date -Is)\`"
  printf '%s\n' "- Boot time: \`${boot_time}\`"
  printf '%s\n' "- Completed merges since boot: \`$(wc -l < "${output_dir}/merged-since-boot.versioned")\`"
  printf '%s\n' "- World atoms: \`$(wc -l < "${output_dir}/world.atoms")\`"
  printf '%s\n' "- Primary candidates: \`$(wc -l < "${output_dir}/primary-candidates.atoms")\`"
  printf '\n## Files\n\n'
  printf '%s\n' '- `metadata.env`'
  printf '%s\n' '- `world.atoms`'
  printf '%s\n' '- `merged-since-boot.versioned`'
  printf '%s\n' '- `merged-since-boot.atoms`'
  printf '%s\n' '- `emerge-commands-since-boot.raw`'
  printf '%s\n' '- `requested-targets-since-boot.raw`'
  printf '%s\n' '- `requested-targets-since-boot.resolved`'
  printf '%s\n' '- `primary-candidates.atoms`'
} > "${output_dir}/README.md"

printf 'Captured Gentoo emerge state in %s\n' "${output_dir}"
