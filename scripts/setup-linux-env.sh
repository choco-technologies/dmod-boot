#!/usr/bin/env bash

set -euo pipefail

TOOLS_DIR="${TOOLS_DIR:-/tools}"
ARM_NONE_EABI_VERSION="${ARM_NONE_EABI_VERSION:-10.3-2021.10}"
CMAKE_VERSION="${CMAKE_VERSION:-3.31.3}"
RENODE_VERSION="${RENODE_VERSION:-1.15.3}"
SKIP_CHOCO_SCRIPTS="${SKIP_CHOCO_SCRIPTS:-false}"
SKIP_PROFILE_SETUP="${SKIP_PROFILE_SETUP:-false}"
SKIP_DMOD_SETUP="${SKIP_DMOD_SETUP:-false}"

print_help() {
    cat << 'EOF'
Prepare native Linux environment for DMOD Boot (equivalent to Docker/Dockerfile).

Usage:
  ./scripts/setup-linux-env.sh [OPTIONS]

Options:
  --tools-dir PATH         Tools directory (default: /tools)
  --arm-version VERSION    arm-none-eabi version (default: 10.3-2021.10)
  --cmake-version VERSION  CMake version (default: 3.31.3)
  --renode-version VERSION Renode version (default: 1.15.3)
  --skip-dmod-setup        Skip DMOD base environment setup
  --skip-choco-scripts     Skip install-choco-scripts.sh execution
  --skip-profile-setup     Do not write /etc/profile.d/dmod-tools.sh
  --help                   Show this help message

Environment overrides:
  TOOLS_DIR
  ARM_NONE_EABI_VERSION
  CMAKE_VERSION
  RENODE_VERSION
  SKIP_DMOD_SETUP
  SKIP_CHOCO_SCRIPTS
  SKIP_PROFILE_SETUP
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --tools-dir)
            TOOLS_DIR="$2"
            shift 2
            ;;
        --arm-version)
            ARM_NONE_EABI_VERSION="$2"
            shift 2
            ;;
        --cmake-version)
            CMAKE_VERSION="$2"
            shift 2
            ;;
        --renode-version)
            RENODE_VERSION="$2"
            shift 2
            ;;
        --skip-dmod-setup)
            SKIP_DMOD_SETUP="true"
            shift
            ;;
        --skip-choco-scripts)
            SKIP_CHOCO_SCRIPTS="true"
            shift
            ;;
        --skip-profile-setup)
            SKIP_PROFILE_SETUP="true"
            shift
            ;;
        --help)
            print_help
            exit 0
            ;;
        *)
            echo "Unknown parameter: $1" >&2
            print_help
            exit 1
            ;;
    esac
done

if command -v sudo >/dev/null 2>&1; then
    SUDO="sudo"
else
    SUDO=""
fi

if [[ "${EUID}" -ne 0 ]] && [[ -z "${SUDO}" ]]; then
    echo "This script needs root privileges or sudo." >&2
    exit 1
fi

# Run DMOD base environment setup if not skipped
if [[ "${SKIP_DMOD_SETUP}" != "true" ]]; then
    # Try to find dmod setup script relative to this script
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    DMOD_SETUP_SCRIPT="${SCRIPT_DIR}/../../dmod/scripts/setup-linux-env.sh"
    
    if [[ -f "${DMOD_SETUP_SCRIPT}" ]]; then
        echo "[DMBOOT] Running DMOD base environment setup..."
        # Pass through common arguments to dmod setup
        bash "${DMOD_SETUP_SCRIPT}" \
            --tools-dir "${TOOLS_DIR}" \
            --arm-version "${ARM_NONE_EABI_VERSION}" \
            --cmake-version "${CMAKE_VERSION}" \
            $([ "${SKIP_CHOCO_SCRIPTS}" = "true" ] && echo "--skip-choco-scripts" || true) \
            $([ "${SKIP_PROFILE_SETUP}" = "true" ] && echo "--skip-profile-setup" || true)
    else
        echo "[DMBOOT] Warning: DMOD setup script not found at ${DMOD_SETUP_SCRIPT}" >&2
        echo "[DMBOOT] Continuing with DMOD Boot specific setup..." >&2
    fi
else
    echo "[DMBOOT] Skipping DMOD base setup (--skip-dmod-setup)."
fi

echo ""
echo "[DMBOOT 1/3] Installing DMOD Boot specific apt packages..."
export DEBIAN_FRONTEND=noninteractive
${SUDO} apt-get update

# Try to install packages, with fallbacks for modern systems
# libncurses5 -> libncurses6 (newer systems)
# libgtk2.0-0 -> libgtk2.0-0t64 (T64 ABI systems)
PACKAGES=(
    "wget"
    "policykit-1"
    "screen"
    "uml-utilities"
    "libc6-dev"
    "gcc"
    "python3"
    "python3-pip"
)

# Try libncurses5 first, fallback to libncurses6
if ${SUDO} apt-cache search --names-only "^libncurses5$" | grep -q .; then
    PACKAGES+=("libncurses5")
else
    echo "[DMBOOT] libncurses5 not found, using libncurses6..."
    PACKAGES+=("libncurses6")
fi

# Try libgtk2.0-0 first, fallback to libgtk2.0-0t64
if ${SUDO} apt-cache search --names-only "^libgtk2.0-0$" | grep -q . && ! ${SUDO} apt-cache search --names-only "^libgtk2.0-0t64$" | grep -q .; then
    PACKAGES+=("libgtk2.0-0")
else
    echo "[DMBOOT] Using libgtk2.0-0t64 variant..."
    PACKAGES+=("libgtk2.0-0t64")
fi

${SUDO} apt-get install -y "${PACKAGES[@]}"

echo "[DMBOOT 2/3] Installing Renode ${RENODE_VERSION}..."
RENODE_VERSION_DEB="renode_${RENODE_VERSION}_amd64.deb"
RENODE_URL="https://github.com/renode/renode/releases/download/v${RENODE_VERSION}/${RENODE_VERSION_DEB}"
RENODE_TEMP="/tmp/${RENODE_VERSION_DEB}"

wget -q "${RENODE_URL}" -O "${RENODE_TEMP}"
${SUDO} dpkg -i "${RENODE_TEMP}" || ${SUDO} apt-get install -f -y
rm -f "${RENODE_TEMP}"

echo "[DMBOOT 3/3] Installing dmffs..."
dmf-get make_dmffs --type dmf

# Add alias for make_dmffs if bash available
if [[ -f "${HOME}/.bashrc" ]]; then
    if ! grep -q "make_dmffs" "${HOME}/.bashrc"; then
        echo "" >> "${HOME}/.bashrc"
        echo "# DMOD Boot make_dmffs alias (added by setup-linux-env.sh)" >> "${HOME}/.bashrc"
        echo "alias make_dmffs='dmod_loader \${DMOD_DMF_DIR}/make_dmffs.dmf --args'" >> "${HOME}/.bashrc"
    fi
fi

echo ""
echo "[DMBOOT] Verifying installed tools..."
renode --version || true

echo ""
echo "[DMBOOT] Environment prepared successfully!"
echo "[DMBOOT] Restart your terminal or run: source ~/.bashrc"
