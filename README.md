# llama.cpp Updater & Builder

[![Shell Script Quality Check](https://github.com/mhajder/llama.cpp-updater/workflows/Shell%20Script%20Quality%20Check/badge.svg)](https://github.com/mhajder/llama.cpp-updater/actions)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

A powerful shell script that automatically downloads and updates llama.cpp binaries from the latest nightly GitHub release, or builds from source with optimal GPU acceleration. This tool simplifies the process of keeping your llama.cpp installation up-to-date across different platforms and architectures.

Since v0.2.0 llama.cpp publishes both stable `vX.Y.Z` tags and per-commit `b[NUM]` nightly tags. Only the nightlies carry prebuilt binaries, so the script always selects the most recent `b[NUM]` release.

## Features

- **Cross-platform support**: Works seamlessly on Linux and macOS with full architecture detection
- **Intelligent architecture detection**: Automatically detects x64 and ARM64 architectures for optimal binary selection
- **Advanced Vulkan support**: Automatically detects Vulkan capabilities on Ubuntu and falls back to the regular build when no Vulkan asset was published
- **Flexible build options**: Choose between fast binary downloads or optimized source builds with automatic GPU acceleration detection
- **Smart installation management**: Install to current directory or specify custom paths with automatic directory creation
- **Safe update process**: Overwrites its own previously installed files and leaves everything else in the target directory untouched
- **Efficient extraction**: Handles both `.tar.gz` and `.zip` assets, and moves the payload out of the archive's `llama-*` wrapper directory (older `llama-*/bin` and `build/bin` layouts are still recognised)
- **Clean installation**: Automatically removes temporary files, empty directories, and build artifacts after installation
- **Comprehensive error handling**: Detailed error messages and recovery suggestions for common issues

## Requirements

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
  - `libcurl4-openssl-dev` - enables HTTP/HTTPS model downloading capabilities
  - `zlib1g-dev` - provides compression support for better performance
  - `pkg-config` - assists with automatic dependency detection during build
- **GPU acceleration libraries (automatically detected)**:
  - CUDA toolkit 11.0+ (for NVIDIA GPU acceleration)
  - Vulkan SDK and drivers (for cross-vendor GPU support, including AMD and Intel)
  - OpenCL libraries and drivers (alternative GPU acceleration method)
  - Metal framework (macOS only, automatically available on Apple Silicon and Intel Macs)

## Usage

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

### Help:
```bash
./update-llama.sh --help
```

## Supported Systems

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
- **CUDA Detection**: Checks for `nvcc` compiler and NVIDIA GPU presence
- **Vulkan Detection**: Verifies Vulkan loader libraries and functional GPU access
- **OpenCL Detection**: Searches for OpenCL runtime libraries and compatible devices
- **Metal Detection**: Automatically enabled on macOS for optimal Apple GPU utilization

**Note**: Vulkan variants are not published for every nightly. When the Vulkan asset is missing the script falls back to the regular Ubuntu build for the same architecture.

## Binary Download vs Build from Source

| Feature | Binary Download | Build from Source |
|---|---|---|
| **Setup Speed** | ⚡ Very Fast (2-5 minutes) | 🐌 Slow (15-45 minutes) |
| **Performance** | ✅ Good (pre-optimized) | 🚀 Excellent (hardware-specific) |
| **GPU Support** | ✅ Pre-selected variants | 🎯 Auto-detected optimal |
| **Disk Space** | 📦 ~60MB installed | 💾 ~2GB (full build) |
| **Dependencies** | Minimal (curl, tar) | Full (git, cmake, compiler) |
| **CURL Support** | ✅ Always included | ✅ If dev libraries available |
| **Server Features** | ✅ Full server functionality | ✅ If dependencies met |
| **Customization** | ❌ Fixed build configuration | ✅ Tailored to your hardware |
| **Ubuntu ARM64** | ✅ Official nightly assets | ✅ Full support with optimizations |
| **Latest Features** | 🔄 Latest nightly (`b[NUM]`) | 🔄 Always bleeding edge |

### Recommendations:
- **Choose Binary Download** if you want quick setup and good performance
- **Choose Build from Source** if you want maximum performance or have specific GPU requirements

## Release archive layout

Current llama.cpp assets are `.tar.gz` archives containing a single versioned
directory, for example `llama-b10582/`, with the binaries and their shared
libraries side by side:

```
llama-b10582/llama-cli
llama-b10582/libggml-base.so
llama-b10582/LICENSE
```

The script moves everything out of that directory into the target directory,
preserving the symlinks between versioned library names, then marks the
installed binaries executable. Older archives that nested the payload under
`llama-*/bin` or `build/bin` are still recognised.

## Troubleshooting

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
   sudo apt-get install libcurl4-openssl-dev zlib1g-dev
   
   # On macOS with Homebrew
   brew install git cmake curl
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
   - The script prints the full asset list of the selected release when nothing matches

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

7. **CMake CURL errors** (common on minimal systems):
   ```bash
   # Install CURL development libraries for full functionality
   sudo apt-get install libcurl4-openssl-dev
   
   # For systems with conflicting CURL versions
   sudo apt-get remove libcurl4-gnutls-dev
   sudo apt-get install libcurl4-openssl-dev
   ```

8. **Missing development libraries** (comprehensive setup):
   ```bash
   # Complete development environment (Ubuntu/Debian)
   sudo apt-get update
   sudo apt-get install build-essential git cmake \
     libcurl4-openssl-dev zlib1g-dev pkg-config \
     vulkan-utils mesa-vulkan-drivers
   
   # Essential build environment (basic requirements)
   sudo apt-get install build-essential git cmake
   
   # macOS complete setup
   brew install git cmake curl pkg-config
   xcode-select --install  # Install command line tools
   ```

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

**Note**: This script downloads and manages llama.cpp binaries. The llama.cpp project itself is subject to its own license terms. Please refer to the [llama.cpp repository](https://github.com/ggml-org/llama.cpp) for information about its licensing.
