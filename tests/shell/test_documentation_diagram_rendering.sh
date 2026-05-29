#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
ANSIBLE_ROOT="${REPO_ROOT}/gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible"
PROFILE="${ANSIBLE_ROOT}/profile-definitions/documentation-diagram-renderer.yml"
M70_CANARY_HOST_VARS="${ANSIBLE_ROOT}/inventories/local-network/host_vars/m70_canary.yml"
DOC="${REPO_ROOT}/docs/DOCUMENTATION-DIAGRAM-RENDERING-STANDARD.md"
WIKI_DOC="${REPO_ROOT}/docs/wiki/Documentation-Diagram-Rendering-Standard.md"
CANARY_DOC="${REPO_ROOT}/docs/M70-CANARY-VALIDATION-LANE.md"
WIKI_CANARY_DOC="${REPO_ROOT}/docs/wiki/M70-Canary-Validation-Lane.md"
EOD_DOC="${REPO_ROOT}/docs/EOD-STATUS-2026-05-26.md"
WIKI_EOD_DOC="${REPO_ROOT}/docs/wiki/EOD-Status-2026-05-26.md"
DIAGRAM_DIR="${REPO_ROOT}/docs/diagrams"

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

assert_file_contains() {
  local file="$1"
  local pattern="$2"

  [[ -f "${file}" ]] || fail "missing file ${file}"
  grep -Fq "${pattern}" "${file}" || fail "expected ${file} to contain ${pattern}"
}

assert_rendered_diagram() {
  local stem="$1"

  [[ -s "${DIAGRAM_DIR}/${stem}.puml" ]] || fail "missing PlantUML source ${stem}"
  [[ -s "${DIAGRAM_DIR}/${stem}.png" ]] || fail "missing rendered PNG ${stem}"
  [[ -s "${DIAGRAM_DIR}/${stem}.svg" ]] || fail "missing rendered SVG ${stem}"
}

assert_file_contains "${PROFILE}" "profile_id: documentation-diagram-renderer"
assert_file_contains "${PROFILE}" "dev-java/openjdk-bin"
assert_file_contains "${PROFILE}" "media-gfx/graphviz"
assert_file_contains "${PROFILE}" "media-gfx/plantuml"
assert_file_contains "${PROFILE}" "media-libs/gd"
assert_file_contains "${PROFILE}" "media-libs/gd fontconfig jpeg png truetype zlib"
assert_file_contains "${PROFILE}" "media-libs/freetype harfbuzz png"
assert_file_contains "${PROFILE}" "media-gfx/graphviz cairo nls"
assert_file_contains "${PROFILE}" "diagram-render-native-cc.conf"
assert_file_contains "${PROFILE}" "FEATURES=\"\${FEATURES} -distcc\""
assert_file_contains "${PROFILE}" "dev-libs/fribidi diagram-render-native-cc.conf"
assert_file_contains "${PROFILE}" "media-libs/freetype diagram-render-native-cc.conf"
assert_file_contains "${PROFILE}" "media-libs/harfbuzz diagram-render-native-cc.conf"
assert_file_contains "${PROFILE}" "harfbuzz-12.3.2-clang21-varc-extra-semi.patch"
assert_file_contains "${PROFILE}" '#pragma GCC diagnostic ignored "-Wextra-semi-stmt"'
assert_file_contains "${M70_CANARY_HOST_VARS}" "documentation-diagram-renderer.yml"

assert_file_contains "${DOC}" "Documentation Diagram Rendering Standard"
assert_file_contains "${DOC}" '| PlantUML source | `docs/diagrams/*.puml` | Source files are committed and reviewed. |'
assert_file_contains "${DOC}" "| Component | Package Atom | Required Policy | Reason |"
assert_file_contains "${DOC}" "| Architecture Area | CCP Trigger | Minimum Documentation |"
assert_file_contains "${DOC}" '```plantuml'
assert_file_contains "${DOC}" "ccp-documentation-diagram-rendering-2026-05-26.png"
assert_file_contains "${WIKI_DOC}" "Documentation Diagram Rendering Standard"
assert_file_contains "${WIKI_DOC}" "ccp-documentation-diagram-rendering-2026-05-26.png"
assert_file_contains "${REPO_ROOT}/docs/wiki/Home.md" "Documentation Diagram Rendering Standard"
assert_file_contains "${REPO_ROOT}/docs/wiki/_Sidebar.md" "Documentation Diagram Rendering Standard"
assert_file_contains "${REPO_ROOT}/docs/wiki/README.md" "Documentation-Diagram-Rendering-Standard.md"

assert_file_contains "${CANARY_DOC}" "CCP Benchmark Promotion Gate"
assert_file_contains "${CANARY_DOC}" "| Validation Target | Current Evidence | Promotion Requirement |"
assert_file_contains "${CANARY_DOC}" "m70-vpp-lacp-benchmark-ccp-2026-05-26.png"
assert_file_contains "${CANARY_DOC}" '```plantuml'
assert_file_contains "${WIKI_CANARY_DOC}" "CCP Benchmark Promotion Gate"
assert_file_contains "${WIKI_CANARY_DOC}" "m70-vpp-lacp-benchmark-ccp-2026-05-26.png"
assert_file_contains "${WIKI_CANARY_DOC}" '```plantuml'

assert_file_contains "${EOD_DOC}" "| Concern | Follow-up Action | Current State |"
assert_file_contains "${EOD_DOC}" "PlantUML/Graphviz/GD dependency policy"
assert_file_contains "${EOD_DOC}" "documentation-diagram-renderer"
assert_file_contains "${WIKI_EOD_DOC}" "| Concern | Follow-up Action | Current State |"
assert_file_contains "${WIKI_EOD_DOC}" "PlantUML/Graphviz/GD dependency policy"

assert_rendered_diagram "ccp-documentation-diagram-rendering-2026-05-26"
assert_rendered_diagram "m70-vpp-lacp-benchmark-ccp-2026-05-26"

printf 'PASS: %s\n' "$(basename "$0")"
