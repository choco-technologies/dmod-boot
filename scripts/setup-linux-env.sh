#!/usr/bin/env bash

set -euo pipefail

TOOLS_DIR="${TOOLS_DIR:-/tools}"
ARM_NONE_EABI_VERSION="${ARM_NONE_EABI_VERSION:-10.3-2021.10}"
CMAKE_VERSION="${CMAKE_VERSION:-3.31.3}"
RENODE_VERSION="${RENODE_VERSION:-1.15.3}"
ESP_IDF_TOOLS_VERSION="${ESP_IDF_TOOLS_VERSION:-5.2.1}"
ESP_IDF_VERSION="${ESP_IDF_VERSION:-4.4.7}"
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
  --esp-version VERSION    ESP IDF tools version (default: 5.2.1)
  --esp-idf-version VER    ESP-IDF git tag version for headers (default: 4.4.7)
  --skip-dmod-setup        Skip DMOD base environment setup
  --skip-choco-scripts     Skip install-choco-scripts.sh execution
  --skip-profile-setup     Do not write /etc/profile.d/dmod-tools.sh
  --help                   Show this help message

Environment overrides:
  TOOLS_DIR
  ARM_NONE_EABI_VERSION
  CMAKE_VERSION
  RENODE_VERSION
  ESP_IDF_TOOLS_VERSION
    ESP_IDF_VERSION
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
        --esp-version)
            ESP_IDF_TOOLS_VERSION="$2"
            shift 2
            ;;
        --esp-idf-version)
            ESP_IDF_VERSION="$2"
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
# libgtk2.0-0 -> libgtk2.0-0t64 (T64 ABI systems)
PACKAGES=(
    "wget"
    "git"
    "policykit-1"
    "screen"
    "uml-utilities"
    "libc6-dev"
    "gcc"
    "python3"
    "python3-pip"
    "gdb-multiarch"
)

# Try libgtk2.0-0 first, fallback to libgtk2.0-0t64
if ${SUDO} apt-cache search --names-only "^libgtk2.0-0$" | grep -q . && ! ${SUDO} apt-cache search --names-only "^libgtk2.0-0t64$" | grep -q .; then
    PACKAGES+=("libgtk2.0-0")
else
    echo "[DMBOOT] Using libgtk2.0-0t64 variant..."
    PACKAGES+=("libgtk2.0-0t64")
fi

${SUDO} apt-get install -y "${PACKAGES[@]}"

echo "[DMBOOT 2/3] Installing Renode ${RENODE_VERSION}..."

# Use the actual directory name that the archive creates
RENODE_DIR="${TOOLS_DIR}/renode_${RENODE_VERSION}_portable"
if [[ -x "${RENODE_DIR}/renode" ]] && "${RENODE_DIR}/renode" --version 2>&1 | grep -q "${RENODE_VERSION}"; then
    echo "    Renode ${RENODE_VERSION} already installed at ${RENODE_DIR}"
else
    RENODE_ARCHIVE="renode-${RENODE_VERSION}.linux-portable.tar.gz"
    RENODE_URL="https://github.com/renode/renode/releases/download/v${RENODE_VERSION}/${RENODE_ARCHIVE}"
    RENODE_TEMP="/tmp/${RENODE_ARCHIVE}"

    if [[ ! -f "${RENODE_TEMP}" ]]; then
        echo "    Downloading Renode portable (this may take a few minutes)..."
        wget -q "${RENODE_URL}" -O "${RENODE_TEMP}"
    else
        echo "    Using cached Renode archive..."
    fi
    
    echo "    Extracting Renode to ${TOOLS_DIR}..."
    ${SUDO} mkdir -p "${TOOLS_DIR}"
    ${SUDO} tar -xzf "${RENODE_TEMP}" -C "${TOOLS_DIR}"
    
    # Create symlink in /usr/local/bin for easy access
    ${SUDO} ln -sf "${RENODE_DIR}/renode" /usr/local/bin/renode
    
    echo "    Renode installed successfully at ${RENODE_DIR}"
fi

echo ""
echo "[DMBOOT 3/3] Installing ESP32-S3 toolchain..."

# Use ESP-IDF installer approach for xtensa-esp32s3-elf toolchain
ESP_TOOLS_DIR="${TOOLS_DIR}/esp-tools"
XTENSA_TOOLCHAIN_DIR=""
XTENSA_TOOLCHAIN_DIR_LEGACY="${ESP_TOOLS_DIR}/xtensa-esp32s3-elf"
XTENSA_TOOLCHAIN_DIR_MODERN="${ESP_TOOLS_DIR}/xtensa-esp-elf"

if [[ -x "${XTENSA_TOOLCHAIN_DIR_LEGACY}/bin/xtensa-esp32s3-elf-gcc" ]]; then
    XTENSA_TOOLCHAIN_DIR="${XTENSA_TOOLCHAIN_DIR_LEGACY}"
    echo "    ESP32-S3 toolchain already installed at ${XTENSA_TOOLCHAIN_DIR}"
elif [[ -x "${XTENSA_TOOLCHAIN_DIR_MODERN}/bin/xtensa-esp-elf-gcc" ]]; then
    XTENSA_TOOLCHAIN_DIR="${XTENSA_TOOLCHAIN_DIR_MODERN}"
    echo "    ESP32-S3 toolchain already installed at ${XTENSA_TOOLCHAIN_DIR}"
else
    echo "    Downloading and installing ESP32-S3 toolchain..."
    ${SUDO} mkdir -p "${ESP_TOOLS_DIR}"
    
    # Detect architecture and download appropriate toolchain
    ARCH=$(uname -m)
    if [[ "${ARCH}" == "x86_64" ]]; then
        TOOLCHAIN_ARCH="x86_64"
        ESP_IDF_ARCH_KEY="linux-amd64"
    elif [[ "${ARCH}" == "aarch64" ]]; then
        TOOLCHAIN_ARCH="aarch64"
        ESP_IDF_ARCH_KEY="linux-arm64"
    else
        echo "    Warning: Unsupported architecture ${ARCH}. ESP32-S3 toolchain may not be available." >&2
        TOOLCHAIN_ARCH="x86_64"
        ESP_IDF_ARCH_KEY="linux-amd64"
    fi

    # Prefer current ESP-IDF manifest (v5.x uses xtensa-esp-elf, not xtensa-esp32s3-elf).
    TOOLCHAIN_URL="$(python3 - <<PY
import json
import urllib.request

esp_idf_version = "${ESP_IDF_TOOLS_VERSION}"
arch_key = "${ESP_IDF_ARCH_KEY}"
manifest_url = f"https://raw.githubusercontent.com/espressif/esp-idf/v{esp_idf_version}/tools/tools.json"

try:
    with urllib.request.urlopen(manifest_url, timeout=20) as response:
        manifest = json.load(response)
    tool = next((entry for entry in manifest.get("tools", []) if entry.get("name") == "xtensa-esp-elf"), None)
    if tool is None:
        print("")
    else:
        version = next((version for version in tool.get("versions", []) if version.get("status") == "recommended"), None)
        if version is None and tool.get("versions"):
            version = tool["versions"][0]
        url = ""
        if version is not None:
            download = version.get(arch_key)
            if isinstance(download, dict):
                url = download.get("url", "")
        print(url)
except Exception:
    print("")
PY
)"

    if [[ -z "${TOOLCHAIN_URL}" ]]; then
        echo "    Could not resolve toolchain from ESP-IDF manifest; trying legacy URL pattern..."
        TOOLCHAIN_FILE="xtensa-esp32s3-elf-${ESP_IDF_TOOLS_VERSION}-linux-${TOOLCHAIN_ARCH}.tar.xz"
        TOOLCHAIN_CANDIDATES=(
            "https://dl.espressif.com/esp-idf-tools/releases/tools/xtensa-esp32s3-elf/${ESP_IDF_TOOLS_VERSION}/${TOOLCHAIN_FILE}"
            "https://github.com/espressif/tools/releases/download/xtensa-esp32s3-elf-${ESP_IDF_TOOLS_VERSION}/${TOOLCHAIN_FILE}"
            "https://github.com/espressif/esp-idf/releases/download/v${ESP_IDF_TOOLS_VERSION}/${TOOLCHAIN_FILE}"
        )

        for candidate_url in "${TOOLCHAIN_CANDIDATES[@]}"; do
            echo "    Trying: ${candidate_url}"
            if wget --spider -q "${candidate_url}" 2>/dev/null; then
                TOOLCHAIN_URL="${candidate_url}"
                echo "    Found toolchain at: ${TOOLCHAIN_URL}"
                break
            fi
        done
    fi
    
    if [[ -z "${TOOLCHAIN_URL}" ]]; then
        echo ""
        echo "    Warning: ESP32-S3 toolchain (${ESP_IDF_TOOLS_VERSION}) not found in official sources." >&2
        echo "    Please install manually from: https://github.com/espressif/tools/releases" >&2
        echo "    And extract to: ${XTENSA_TOOLCHAIN_DIR}" >&2
        echo "    Or install via: https://docs.espressif.com/projects/esp-idf/en/latest/esp32s3/get-started/linux-setup.html" >&2
    else
        TOOLCHAIN_FILE="$(basename "${TOOLCHAIN_URL}")"
        TOOLCHAIN_TEMP="/tmp/${TOOLCHAIN_FILE}"
        
        if [[ ! -f "${TOOLCHAIN_TEMP}" ]]; then
            echo "    Downloading ESP32-S3 toolchain (this may take a few minutes)..."
            if ! wget -q "${TOOLCHAIN_URL}" -O "${TOOLCHAIN_TEMP}"; then
                echo "    Error: Failed to download from ${TOOLCHAIN_URL}" >&2
                TOOLCHAIN_TEMP=""
            fi
        else
            echo "    Using cached ESP32-S3 toolchain archive..."
        fi
        
        if [[ -f "${TOOLCHAIN_TEMP}" ]]; then
            echo "    Extracting ESP32-S3 toolchain to ${ESP_TOOLS_DIR}..."
            ${SUDO} tar -xf "${TOOLCHAIN_TEMP}" -C "${ESP_TOOLS_DIR}"
            echo "    ESP32-S3 toolchain installed successfully"
        fi
    fi
fi

ESP_IDF_DIR="${ESP_TOOLS_DIR}/esp-idf"
ESP_IDF_TAG="v${ESP_IDF_VERSION}"
ESP_IDF_VERSION_MARKER="${ESP_IDF_DIR}/.dmboot-espidf-version"

echo ""
echo "[DMBOOT 4/4] Installing ESP-IDF (${ESP_IDF_TAG}) for Xtensa HAL headers..."
${SUDO} mkdir -p "${ESP_TOOLS_DIR}"

if [[ -f "${ESP_IDF_DIR}/components/xtensa/include/xtensa/hal.h" ]]; then
    echo "    ESP-IDF already available at ${ESP_IDF_DIR}"
else
    true
fi

NEEDS_ESP_IDF_REINSTALL="true"
if [[ -f "${ESP_IDF_VERSION_MARKER}" ]] \
   && [[ "$(cat "${ESP_IDF_VERSION_MARKER}" 2>/dev/null || true)" == "${ESP_IDF_TAG}" ]] \
   && [[ -f "${ESP_IDF_DIR}/components/xtensa/include/xtensa/hal.h" ]] \
   && [[ -f "${ESP_IDF_DIR}/components/esp_hw_support/include/soc/cpu.h" ]] \
   && [[ -f "${ESP_IDF_DIR}/components/esp_hw_support/include/soc/compare_set.h" ]]; then
    NEEDS_ESP_IDF_REINSTALL="false"
fi

if [[ "${NEEDS_ESP_IDF_REINSTALL}" == "true" ]]; then
    echo "    Installing clean ESP-IDF checkout at ${ESP_IDF_TAG}..."
    ${SUDO} rm -rf "${ESP_IDF_DIR}"
    if ! ${SUDO} git clone --depth 1 --branch "${ESP_IDF_TAG}" \
        https://github.com/espressif/esp-idf.git "${ESP_IDF_DIR}"; then
        echo "    Error: Failed to clone ESP-IDF tag ${ESP_IDF_TAG}." >&2
        exit 1
    fi
    echo "${ESP_IDF_TAG}" | ${SUDO} tee "${ESP_IDF_VERSION_MARKER}" >/dev/null
fi

if [[ -f "${ESP_IDF_DIR}/components/xtensa/include/xtensa/hal.h" ]]; then
    echo "    Xtensa HAL header found: ${ESP_IDF_DIR}/components/xtensa/include/xtensa/hal.h"
else
    echo "    Warning: xtensa/hal.h is still missing under ${ESP_IDF_DIR}" >&2
fi

if [[ ! -f "${ESP_IDF_DIR}/components/esp_hw_support/include/soc/cpu.h" ]] \
   || [[ ! -f "${ESP_IDF_DIR}/components/esp_hw_support/include/soc/compare_set.h" ]]; then
    echo "    Error: ESP-IDF at ${ESP_IDF_DIR} is incompatible (missing legacy soc headers)." >&2
    echo "    Expected version line: ${ESP_IDF_TAG}" >&2
    exit 1
fi

if [[ -x "${XTENSA_TOOLCHAIN_DIR_LEGACY}/bin/xtensa-esp32s3-elf-gcc" ]]; then
    XTENSA_TOOLCHAIN_DIR="${XTENSA_TOOLCHAIN_DIR_LEGACY}"
elif [[ -x "${XTENSA_TOOLCHAIN_DIR_MODERN}/bin/xtensa-esp-elf-gcc" ]]; then
    XTENSA_TOOLCHAIN_DIR="${XTENSA_TOOLCHAIN_DIR_MODERN}"
fi

# Configure PATH for ESP32-S3 toolchain if available
if [[ -n "${XTENSA_TOOLCHAIN_DIR}" ]] && [[ -d "${XTENSA_TOOLCHAIN_DIR}" ]]; then
    if [[ "${SKIP_PROFILE_SETUP}" != "true" ]]; then
        echo "Updating /etc/profile.d/dmboot-tools.sh for ESP toolchain..."
        ${SUDO} tee /etc/profile.d/dmboot-tools.sh >/dev/null << 'EOF'
#!/usr/bin/env sh
# DMOD Boot tools PATH configuration
EOF
        if [[ -d "${RENODE_DIR}" ]]; then
            ${SUDO} tee -a /etc/profile.d/dmboot-tools.sh >/dev/null << EOF
if [ -d "${RENODE_DIR}" ]; then
    case ":\$PATH:" in
        *:"${RENODE_DIR}":*) ;;
        *) export PATH="\$PATH:${RENODE_DIR}" ;;
    esac
fi
EOF
        fi
        if [[ -d "${XTENSA_TOOLCHAIN_DIR}" ]]; then
            ${SUDO} tee -a /etc/profile.d/dmboot-tools.sh >/dev/null << EOF
if [ -d "${XTENSA_TOOLCHAIN_DIR}/bin" ]; then
    case ":\$PATH:" in
        *:"${XTENSA_TOOLCHAIN_DIR}/bin":*) ;;
        *) export PATH="${XTENSA_TOOLCHAIN_DIR}/bin:\$PATH" ;;
    esac
fi
EOF
        fi
    if [[ -d "${ESP_IDF_DIR}" ]]; then
        ${SUDO} tee -a /etc/profile.d/dmboot-tools.sh >/dev/null << EOF
if [ -d "${ESP_IDF_DIR}" ]; then
    export IDF_PATH="${ESP_IDF_DIR}"
    export ESP_IDF_PATH="${ESP_IDF_DIR}"
fi
EOF
    fi
        ${SUDO} chmod 644 /etc/profile.d/dmboot-tools.sh
        
        # Update user's bashrc
        if [[ -f "${HOME}/.bashrc" ]]; then
            if ! grep -q "dmboot-tools.sh" "${HOME}/.bashrc"; then
                echo "" >> "${HOME}/.bashrc"
                echo "# DMOD Boot tools PATH (added by setup-linux-env.sh)" >> "${HOME}/.bashrc"
                echo "if [ -f /etc/profile.d/dmboot-tools.sh ]; then" >> "${HOME}/.bashrc"
                echo "    . /etc/profile.d/dmboot-tools.sh" >> "${HOME}/.bashrc"
                echo "fi" >> "${HOME}/.bashrc"
            fi
        fi
    fi
fi

# Configure PATH for DMOD Boot tools
if [[ "${SKIP_PROFILE_SETUP}" != "true" ]]; then
    if [[ -z "${XTENSA_TOOLCHAIN_DIR}" ]] || [[ ! -d "${XTENSA_TOOLCHAIN_DIR}" ]]; then
        echo ""
        echo "Configuring PATH in /etc/profile.d/dmboot-tools.sh..."
        ${SUDO} tee /etc/profile.d/dmboot-tools.sh >/dev/null << EOF
#!/usr/bin/env sh
# DMOD Boot tools PATH configuration
if [ -d "${RENODE_DIR}" ]; then
    case ":\$PATH:" in
        *:"${RENODE_DIR}":*) ;;
        *) export PATH="\$PATH:${RENODE_DIR}" ;;
    esac
fi
if [ -d "${ESP_IDF_DIR}" ]; then
    export IDF_PATH="${ESP_IDF_DIR}"
    export ESP_IDF_PATH="${ESP_IDF_DIR}"
fi
EOF
        ${SUDO} chmod 644 /etc/profile.d/dmboot-tools.sh
        
        # Add to user's bashrc for non-login shells
        if [[ -f "${HOME}/.bashrc" ]]; then
            if ! grep -q "dmboot-tools.sh" "${HOME}/.bashrc"; then
                echo "" >> "${HOME}/.bashrc"
                echo "# DMOD Boot tools PATH (added by setup-linux-env.sh)" >> "${HOME}/.bashrc"
                echo "if [ -f /etc/profile.d/dmboot-tools.sh ]; then" >> "${HOME}/.bashrc"
                echo "    . /etc/profile.d/dmboot-tools.sh" >> "${HOME}/.bashrc"
                echo "fi" >> "${HOME}/.bashrc"
            fi
        fi
    fi
fi

echo "[DMBOOT 5/5] Installing dmffs..."
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
# Load dmboot tools PATH for verification
if [[ -f /etc/profile.d/dmboot-tools.sh ]]; then
    source /etc/profile.d/dmboot-tools.sh
fi
if command -v renode &>/dev/null; then
    echo "    Renode: $(renode --version)"
else
    echo "    Warning: renode not found in PATH. Restart your terminal or run: source ~/.bashrc"
fi

if command -v xtensa-esp32s3-elf-gcc &>/dev/null; then
    echo "    ESP32-S3 Toolchain: $(xtensa-esp32s3-elf-gcc --version | head -1)"
elif command -v xtensa-esp-elf-gcc &>/dev/null; then
    echo "    ESP32-S3 Toolchain: $(xtensa-esp-elf-gcc --version | head -1)"
else
    echo "    Warning: ESP32-S3 toolchain not found in PATH. Restart your terminal or run: source ~/.bashrc"
fi

if [[ -n "${IDF_PATH:-}" ]] && [[ -f "${IDF_PATH}/components/xtensa/include/xtensa/hal.h" ]]; then
    echo "    ESP-IDF: ${IDF_PATH}"
else
    echo "    Warning: IDF_PATH is not set (or xtensa/hal.h not found under it)."
fi

echo ""
echo "[DMBOOT] Environment prepared successfully!"
echo "[DMBOOT] Restart your terminal or run: source ~/.bashrc"
