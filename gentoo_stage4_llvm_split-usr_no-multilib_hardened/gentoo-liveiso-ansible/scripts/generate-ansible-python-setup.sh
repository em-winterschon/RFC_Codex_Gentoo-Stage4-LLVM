#!/usr/bin/env bash
set -euo pipefail

# Generates a self-contained setup script for the ansible Python environment.
# The generated script:
#   - checks out this repository
#   - validates the Python 3 version
#   - ensures pip is available
#   - installs pipenv (if missing)
#   - creates/uses a pipenv and installs requirements.txt

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUTPUT_PATH="${1:-${SCRIPT_DIR}/setup-ansible-python-env.sh}"

cat > "${OUTPUT_PATH}" << 'GENERATED'
#!/usr/bin/env bash
set -euo pipefail

REPO_URL="${REPO_URL:-https://github.com/em-winterschon/RFC_Codex_Gentoo-Stage4-LLVM.git}"
CHECKOUT_DIR="${CHECKOUT_DIR:-RFC_Codex_Gentoo-Stage4-LLVM}"
BRANCH="${BRANCH:-main}"
PYTHON_MIN_MINOR="${PYTHON_MIN_MINOR:-11}"

ANSIBLE_REL_PATH="gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible"

log() {
  printf '[setup-ansible-env] %s\n' "$*"
}

ensure_python() {
  if ! command -v python3 > /dev/null 2>&1; then
    echo "python3 was not found in PATH. Please install Python 3.${PYTHON_MIN_MINOR}+ first." >&2
    exit 1
  fi

  local version minor
  version="$(python3 -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}")')"
  minor="$(python3 -c 'import sys; print(sys.version_info.minor)')"

  if [[ "${minor}" -lt "${PYTHON_MIN_MINOR}" ]]; then
    echo "python3 ${version} detected; need Python >= 3.${PYTHON_MIN_MINOR}." >&2
    exit 1
  fi

  log "python3 ${version} detected."
}

ensure_pip() {
  if python3 -m pip --version > /dev/null 2>&1; then
    log "pip already available."
    return
  fi

  log "pip not found, attempting bootstrap with ensurepip."
  python3 -m ensurepip --upgrade

  if ! python3 -m pip --version > /dev/null 2>&1; then
    echo "Unable to bootstrap pip. Install pip manually and re-run." >&2
    exit 1
  fi

  log "pip installed successfully."
}

ensure_pipenv() {
  if command -v pipenv > /dev/null 2>&1; then
    log "pipenv already installed."
    return
  fi

  log "Installing pipenv for current user."
  python3 -m pip install --user --upgrade pipenv

  if ! command -v pipenv > /dev/null 2>&1; then
    local userbase_bin
    userbase_bin="$(python3 -m site --user-base)/bin"
    export PATH="${userbase_bin}:${PATH}"
  fi

  if ! command -v pipenv > /dev/null 2>&1; then
    echo "pipenv was installed but is not on PATH; add it and re-run." >&2
    exit 1
  fi

  log "pipenv available at $(command -v pipenv)."
}

checkout_repo() {
  if [[ -d "${CHECKOUT_DIR}/.git" ]]; then
    log "Repository already present at ${CHECKOUT_DIR}; updating branch ${BRANCH}."
    git -C "${CHECKOUT_DIR}" fetch --all --tags --prune
    git -C "${CHECKOUT_DIR}" checkout "${BRANCH}"
    git -C "${CHECKOUT_DIR}" pull --ff-only origin "${BRANCH}"
    return
  fi

  log "Cloning ${REPO_URL} into ${CHECKOUT_DIR} (branch: ${BRANCH})."
  git clone --branch "${BRANCH}" --single-branch "${REPO_URL}" "${CHECKOUT_DIR}"
}

install_ansible_requirements() {
  local ansible_dir requirements
  ansible_dir="${CHECKOUT_DIR}/${ANSIBLE_REL_PATH}"
  requirements="${ansible_dir}/requirements.txt"

  if [[ ! -f "${requirements}" ]]; then
    echo "Missing ${requirements}." >&2
    exit 1
  fi

  pushd "${ansible_dir}" > /dev/null
  log "Creating/updating pipenv with ${requirements}."
  PIPENV_VENV_IN_PROJECT="${PIPENV_VENV_IN_PROJECT:-1}" \
    pipenv --python "$(command -v python3)" install -r requirements.txt
  popd > /dev/null

  log "Done. Activate with: cd ${ansible_dir} && pipenv shell"
}

main() {
  checkout_repo
  ensure_python
  ensure_pip
  ensure_pipenv
  install_ansible_requirements
}

main "$@"
GENERATED

chmod +x "${OUTPUT_PATH}"

echo "Generated ${OUTPUT_PATH}"
echo "Run it with: ${OUTPUT_PATH}"
