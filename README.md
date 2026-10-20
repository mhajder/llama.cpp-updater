<div align="center">

# llama.cpp Updater & Builder

**Keep llama.cpp up to date with one command: grab the latest nightly binaries or build from source with GPU acceleration**

[![Shell Script Quality Check](https://github.com/mhajder/llama.cpp-updater/actions/workflows/shellcheck.yml/badge.svg)](https://github.com/mhajder/llama.cpp-updater/actions/workflows/shellcheck.yml)
[![License](https://img.shields.io/github/license/mhajder/llama.cpp-updater)](https://github.com/mhajder/llama.cpp-updater/blob/main/LICENSE)
[![Last commit](https://img.shields.io/github/last-commit/mhajder/llama.cpp-updater)](https://github.com/mhajder/llama.cpp-updater/commits/main)
[![Stars](https://img.shields.io/github/stars/mhajder/llama.cpp-updater?style=flat&logo=github)](https://github.com/mhajder/llama.cpp-updater/stargazers)

[![Bash](https://img.shields.io/badge/Bash-script-4EAA25?logo=gnubash&logoColor=white)](https://github.com/mhajder/llama.cpp-updater/blob/main/update-llama.sh)
[![Platforms](https://img.shields.io/badge/platform-Linux%20%7C%20macOS-555?logo=linux&logoColor=white)](https://github.com/mhajder/llama.cpp-updater#-supported-systems)
[![GPU](https://img.shields.io/badge/GPU-CUDA%20%7C%20Vulkan%20%7C%20Metal-76B900)](https://github.com/mhajder/llama.cpp-updater#-supported-systems)
[![llama.cpp](https://img.shields.io/badge/for-llama.cpp-FF8C00)](https://github.com/ggml-org/llama.cpp)

[Quick start](https://github.com/mhajder/llama.cpp-updater#-quick-start) · [Usage](https://github.com/mhajder/llama.cpp-updater#-usage) · [Supported systems](https://github.com/mhajder/llama.cpp-updater#-supported-systems) · [Troubleshooting](https://github.com/mhajder/llama.cpp-updater#-troubleshooting)

</div>

A powerful shell script that automatically downloads and updates llama.cpp binaries from the latest nightly GitHub release, or builds from source with optimal GPU acceleration. This tool simplifies the process of keeping your llama.cpp installation up-to-date across different platforms and architectures.

Since v0.2.0 llama.cpp publishes both stable `vX.Y.Z` tags and per-commit `b[NUM]` nightly tags. Only the nightlies carry prebuilt binaries, so the script always selects the most recent `b[NUM]` release.

## 🚀 Quick start

Download the script, make it executable and install the latest llama.cpp nightly into a directory of your choice:

```bash
curl -fsSL https://raw.githubusercontent.com/mhajder/llama.cpp-updater/main/update-llama.sh -o update-llama.sh
chmod +x update-llama.sh
./update-llama.sh ~/llama.cpp
```

Run the same command again whenever you want to update. To always use the newest script, clone the repository instead and `git pull` before running it.

## ✨ Features

- **Cross-platform support**: Works seamlessly on Linux and macOS with full architecture detection
- **Intelligent architecture detection**: Automatically detects x64 and ARM64 architectures for optimal binary selection
- **Advanced Vulkan support**: Automatically detects a usable Vulkan GPU on Ubuntu, prefers the newest Vulkan build and falls back to the regular build only when none of the latest releases has one (`--vulkan` refuses to fall back)
- **Flexible build options**: Choose between fast binary downloads or optimized source builds with automatic GPU acceleration detection
- **Smart installation management**: Install to current directory or specify custom paths with automatic directory creation
- **Safe update process**: New files are staged first and swapped in together; if anything fails, or the run is interrupted, the previous installation is restored
- **Stale file cleanup**: Removes files a previous run installed that the new release no longer ships (tracked in `.llama-cpp-updater-manifest`) and leaves everything else in the target directory untouched
- **Efficient extraction**: Handles both `.tar.gz` and `.zip` assets, and moves the payload out of the archive's `llama-*` wrapper directory (older `llama-*/bin` and `build/bin` layouts are still recognised)
- **Verified downloads**: Checks each downloaded archive against the sha256 digest GitHub publishes for the asset
- **Skips unchanged releases**: Does nothing when the latest release is already installed (`--force` reinstalls)
- **Clean installation**: Removes the download, the extracted archive and the source build tree when done, and clears staging directories left by interrupted runs; a lock stops two runs from updating the same directory at once
- **Comprehensive error handling**: Detailed error messages and recovery suggestions for common issues

## 📋 Requirements

### For binary downloads (recommended for quick setup):
- `curl` or `wget` (for downloading files from GitHub releases)
- `tar` (for extracting `.tar.gz` archives, the format used by all current Linux and macOS assets)
- `unzip` (only needed for older `.zip` assets)
- Internet connection to access GitHub API and download assets
- ~60MB free disk space (~16MB download, ~40MB extracted)

### For building from source (recommended for maximum performance):
- `git` (for cloning the llama.cpp repository)
- `cmake` (build system, version 3.14 or higher required)
- `make` or equivalent build tools (build-essential on Ubuntu)
- C++ compiler with C++17 support (gcc 8+, clang 7+, or equivalent)
- ~2GB free disk space for source code and build artifacts
- **Optional dependencies for enhanced features**:
  - `libssl-dev` - enables HTTPS model downloads (llama.cpp uses OpenSSL; curl is no longer used)
  - `zlib1g-dev` - provides compression support for better performance
  - `pkg-config` - assists with automatic dependency detection during build
- **GPU acceleration libraries (automatically detected)**:
  - CUDA toolkit 11.0+ (for NVIDIA GPU acceleration)
  - Vulkan SDK and drivers (for cross-vendor GPU support, including AMD and Intel)
  - OpenCL libraries and drivers (alternative GPU acceleration method)
  - Metal framework (macOS only, automatically available on Apple Silicon and Intel Macs)

## 💡 Usage

### Basic usage (install to current directory):
```bash
./update-llama.sh
```

### Install to a specific directory:
```bash
./update-llama.sh /path/to/target/directory
```

### Build from source (recommended for best performance):
```bash
./update-llama.sh --build-from-source ./custom-dir
```

### Force specific Ubuntu variant:
```bash
# Force Vulkan build (Ubuntu x64 and ARM64)
./update-llama.sh --vulkan ./bin

# Force regular build (disable Vulkan auto-detection)
./update-llama.sh --force-regular ./bin
```

### Reinstall the current release:
Re-running the script does nothing when the latest release is already installed. Use `--force` to reinstall it anyway (or to rebuild from source, for example after installing GPU libraries):
```bash
./update-llama.sh --force ./bin
```

### Avoid GitHub API rate limits:
Unauthenticated GitHub API requests are limited to 60 per hour per IP address, which shared CI runners and NAT'd networks can hit. Set a token (no scopes needed) to raise the limit to 5000:
```bash
GITHUB_TOKEN=ghp_yourtoken ./update-llama.sh ./bin
```
`GH_TOKEN` works too. The token is only sent to `api.github.com`, and never appears on a command line.

### Help:
```bash
./update-llama.sh --help
```

## 💻 Supported Systems

| OS | Architecture | Binary Packages | Build from Source |
|---|---|---|---|
| Linux (Ubuntu) | x64 | `llama-*-bin-ubuntu-x64.tar.gz`<br>`llama-*-bin-ubuntu-vulkan-x64.tar.gz` | ✅ Auto GPU detection |
| Linux (Ubuntu) | ARM64 | `llama-*-bin-ubuntu-arm64.tar.gz`<br>`llama-*-bin-ubuntu-vulkan-arm64.tar.gz` | ✅ Full support |
| macOS | x64 | `llama-*-bin-macos-x64.tar.gz` | ✅ Metal acceleration |
| macOS | ARM64 | `llama-*-bin-macos-arm64.tar.gz` | ✅ Metal acceleration |

### GPU Acceleration (Build from Source - Optimal Performance)
| Platform | GPU Support | Auto-detected | Performance Notes |
|---|---|---|---|
| Linux | CUDA, Vulkan, OpenCL | ✅ | CUDA preferred for NVIDIA, Vulkan for AMD/Intel |
| macOS | Metal | ✅ | Native Apple Silicon optimization, Intel Mac support |
| All Platforms | CPU optimizations | ✅ | SIMD instructions, multi-threading, architecture-specific |

**Advanced GPU Detection Logic**:
- **CUDA Detection**: Looks for the `nvcc` compiler on `PATH`, in `$CUDA_HOME/bin`, `$CUDA_PATH/bin` and `/usr/local/cuda/bin`
- **Vulkan Detection**: Uses the GPU list from `vulkaninfo` when installed (software renderers such as llvmpipe don't count), otherwise the presence of the Vulkan loader library; building also needs `glslc` and the Vulkan and SPIR-V headers
- **OpenCL Detection**: Requires the OpenCL headers (`CL/cl.h`), the `libOpenCL.so` development link and Python 3; devices are not probed
- **Metal Detection**: Automatically enabled on macOS for optimal Apple GPU utilization

**Note**: Vulkan variants are not published for every nightly. The script then installs the newest release among the latest ten that has a Vulkan build, and only falls back to the regular Ubuntu build for the same architecture when none does. With `--vulkan` it stops with an error instead of falling back.

## 🆚 Binary Download vs Build from Source

| Feature | Binary Download | Build from Source |
|---|---|---|
| **Setup Speed** | ⚡ Very Fast (2-5 minutes) | 🐌 Slow (15-45 minutes) |
| **Performance** | ✅ Good (pre-optimized) | 🚀 Excellent (hardware-specific) |
| **GPU Support** | ✅ Pre-selected variants | 🎯 Auto-detected optimal |
| **Disk Space** | 📦 ~60MB installed | 💾 ~2GB (full build) |
| **Dependencies** | Minimal (curl, tar) | Full (git, cmake, compiler) |
| **HTTPS Downloads** | ✅ Always included | ✅ If OpenSSL dev libraries available |
| **Server Features** | ✅ Full server functionality | ✅ If dependencies met |
| **Customization** | ❌ Fixed build configuration | ✅ Tailored to your hardware |
| **Ubuntu ARM64** | ✅ Official nightly assets | ✅ Full support with optimizations |
| **Latest Features** | 🔄 Latest nightly (`b[NUM]`) | 🔄 Latest published nightly (`b[NUM]`) |

### Recommendations:
- **Choose Binary Download** if you want quick setup and good performance
- **Choose Build from Source** if you want maximum performance or have specific GPU requirements

## 📦 Release archive layout

Current llama.cpp assets are `.tar.gz` archives containing a single versioned
directory, for example `llama-b10582/`, with the binaries and their shared
libraries side by side:

```
llama-b10582/llama-cli
llama-b10582/libggml-base.so
llama-b10582/LICENSE
```

The script stages everything from that directory inside the target directory,
preserving the symlinks between versioned library names, marks the binaries
(detected by their ELF or Mach-O header) executable, then swaps the files into
place. Files the previous run installed but the new release no longer ships are
removed, and the installed names are recorded in `.llama-cpp-updater-manifest`.
Older archives that nested the payload under `llama-*/bin` or `build/bin` are
still recognised.

## 🩺 Troubleshooting

### Common Issues

1. **Missing dependencies for binary downloads**:
   ```bash
   # On Ubuntu/Debian
   sudo apt-get install curl tar
   
   # On macOS with Homebrew
   brew install curl
   ```

2. **Missing dependencies for building from source**:
   ```bash
   # Essential build tools (Ubuntu/Debian)
   sudo apt-get install git cmake build-essential
   
   # Optional but recommended libraries (Ubuntu/Debian)
   sudo apt-get install libssl-dev zlib1g-dev
   
   # On macOS with Homebrew
   brew install git cmake
   ```

3. **Permission denied**:
   ```bash
   chmod +x update-llama.sh
   ```

4. **No suitable binary found**:
   - Check if your system/architecture is supported
   - Try building from source: `./update-llama.sh --build-from-source`
   - Verify internet connection
   - Check GitHub releases page manually
   - When nothing matches, the script prints the `.zip`/`.tar.gz` archives of the newest release

5. **Vulkan detection issues**:
   ```bash
   # Install Vulkan tools for detection
   sudo apt-get install vulkan-utils
   
   # Force regular build if Vulkan causes issues
   ./update-llama.sh --force-regular
   ```

6. **Build from source fails**:
   - Ensure all build dependencies are installed
   - Check available disk space (build requires ~2GB)
   - Try without GPU acceleration if drivers are problematic

7. **"OpenSSL not found, HTTPS support disabled"** (common on minimal systems):
   ```bash
   # Install OpenSSL development libraries so llama.cpp can download models over HTTPS
   sudo apt-get install libssl-dev
   ```

8. **Missing development libraries** (comprehensive setup):
   ```bash
   # Complete development environment (Ubuntu/Debian)
   sudo apt-get update
   sudo apt-get install build-essential git cmake \
     libssl-dev zlib1g-dev pkg-config \
     vulkan-utils mesa-vulkan-drivers
   
   # Essential build environment (basic requirements)
   sudo apt-get install build-essential git cmake
   
   # macOS complete setup
   brew install git cmake pkg-config
   xcode-select --install  # Install command line tools
   ```

## 🤝 Contributing

Contributions are welcome. See [CONTRIBUTING.md](https://github.com/mhajder/llama.cpp-updater/blob/main/CONTRIBUTING.md) for the checks to run and the commit message format, and use the [issue templates](https://github.com/mhajder/llama.cpp-updater/issues/new/choose) for bugs and feature requests.

Found a security problem? Please report it privately as described in [SECURITY.md](https://github.com/mhajder/llama.cpp-updater/blob/main/SECURITY.md).

## 📜 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

**Note**: This script downloads and manages llama.cpp binaries. The llama.cpp project itself is subject to its own license terms. Please refer to the [llama.cpp repository](https://github.com/ggml-org/llama.cpp) for information about its licensing.
