# Windows Environment Setup for dmod-boot

## Overview

dmod-boot supports native Windows development and build workflows.

Supported workflows:

1. **Native Windows (PowerShell + CMake)** - Recommended when you want to work without WSL/Docker
2. **WSL2 + Ubuntu** - Linux-like workflow on Windows
3. **Docker Desktop** - fastest way to get a ready-to-use environment

---

## Option 1: Native Windows (Recommended)

### 1. Install required tools

Use the repository helper script (no admin-required package installation; tools are downloaded to user-writable directory):

```powershell
.\scripts\setup-windows-env.ps1
```

By default this downloads/extracts tools to:

```powershell
$env:USERPROFILE\tools\dmboot
```

Then (for the current shell session):

```powershell
. "$env:USERPROFILE\tools\dmboot\activate-dmboot-tools.ps1"
```

Downloaded tools:

- **CMake** (3.10+)
- **Ninja** (optional, recommended)
- **GNU Arm Embedded Toolchain** (`arm-none-eabi-*`)
- **Python 3**
- **dmod tools** (`dmf-get`, `todmp`, `dmod_loader`) - install/build separately from the dmod project and add them to `PATH` (this script does not install them globally)
- **OpenOCD** (for hardware workflow)
- **Renode** (optional, for emulation workflow)

Optional script flags:

```powershell
.\scripts\setup-windows-env.ps1 -ToolsDir D:\tools\dmboot -SkipRenode
.\scripts\setup-windows-env.ps1 -DryRun
```

### 2. Configure and build (PowerShell)

From repository root:

```powershell
cmake -DCMAKE_BUILD_TYPE=Debug -DTARGET=STM32F746xG -S . -B build
cmake --build build --config Debug
```

### 3. Optional: Renode emulation mode

```powershell
cmake -DCMAKE_BUILD_TYPE=Debug -DDMBOOT_EMULATION=ON -S . -B build
cmake --build build --config Debug
cmake --build build --target connect
```

---

## Option 2: WSL2 + Ubuntu

### 1. Install WSL2

In **PowerShell (Run as Administrator)**:

```powershell
wsl --install -d Ubuntu-24.04
```

Reboot if prompted, then launch Ubuntu and create your Linux user.

### 2. Install VS Code integrations (Windows side)

Install:

- **Visual Studio Code**
- **Remote - WSL** extension

Open the project folder from WSL:

```bash
cd /path/to/dmod-boot
code .
```

### 3. Install build dependencies in WSL

In Ubuntu (WSL terminal):

```bash
sudo apt-get update
sudo apt-get install -y \
  git cmake ninja-build make \
  gcc-arm-none-eabi gdb-multiarch \
  python3 python3-pip \
  wget policykit-1 screen uml-utilities \
  libgtk2.0-0t64 || sudo apt-get install -y libgtk2.0-0
```

### 4. Install Renode (optional, for emulation)

If you plan to run in emulation mode (`DMBOOT_EMULATION=ON`), install Renode in WSL:

```bash
# Example for version 1.15.3
wget -q https://github.com/renode/renode/releases/download/v1.15.3/renode-1.15.3.linux-portable.tar.gz
mkdir -p "$HOME/tools"
tar -xzf renode-1.15.3.linux-portable.tar.gz -C "$HOME/tools"
export PATH="$PATH:$HOME/tools/renode_1.15.3_portable"
```

You can add the `PATH` line to `~/.bashrc`.

### 5. Configure and build

From the repository root in WSL:

```bash
cmake -DCMAKE_BUILD_TYPE=Debug -DTARGET=STM32F746xG -S . -B build
cmake --build build --config Debug
```

Alternative targets include `STM32F407G` and board-based builds (for example `-DBOARD=stm32f746g-disco`).

### 6. Build for Renode emulation (optional)

```bash
cmake -DCMAKE_BUILD_TYPE=Debug -DDMBOOT_EMULATION=ON -S . -B build
cmake --build build --config Debug
```

### 7. Run common workflow targets

```bash
cmake --build build --target install-firmware
cmake --build build --target connect
cmake --build build --target monitor-gdb
```

---

## Option 3: Docker Desktop (Quick Start)

### 1. Install Docker Desktop on Windows

Enable WSL2 backend during Docker Desktop setup.

### 2. Run the prepared container

From the repository directory (PowerShell):

```powershell
docker run -it --rm `
  -v ${PWD}:/workspace `
  -w /workspace `
  chocotechnologies/dmboot:1.0.0 `
  bash
```

Inside the container:

```bash
cmake -S . -B build
cmake --build build
```

This image already includes the required toolchain and utilities.

---

## Flashing and Debugging Hardware from Windows

- For OpenOCD/JTAG/SWD hardware debugging, **WSL2 USB forwarding** may be required (`usbipd-win`).
- Some probes/tools are easier to use from native Linux than from Windows + WSL2.
- If hardware access is problematic, use `DMBOOT_EMULATION=ON` with Renode for development and CI-like testing.

---

## Troubleshooting

### `bash: command not found` or script errors

Make sure you are running commands in **WSL Ubuntu** or inside the Docker container, not in plain `cmd.exe`.

### CMake cannot find ARM toolchain

Verify tools are in `PATH`:

```bash
arm-none-eabi-gcc --version
cmake --version
python3 --version
```

### Renode not found

Check installation path and `PATH` export:

```bash
which renode
renode --version
```

### Build directory issues after switching environments

```bash
rm -rf build
cmake -S . -B build
cmake --build build
```

---

## Recommended Daily Workflow on Windows

1. Open Ubuntu (WSL2)
2. Enter repository directory
3. Run `code .` to open VS Code in WSL context
4. Configure/build with CMake
5. Use Renode emulation for routine development
6. Use hardware flashing/debugging only when needed
