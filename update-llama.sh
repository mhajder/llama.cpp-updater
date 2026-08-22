#!/bin/bash

# llama.cpp updater & builder script
# Automatically downloads and updates llama.cpp from the latest GitHub release
# Supports Linux and macOS

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to print colored output
print_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to detect system and architecture
detect_system() {
    local os=""
    local arch=""
    local variant=""

    # Detect OS
    case "$(uname -s)" in
    Linux*) os="ubuntu" ;;
    Darwin*) os="macos" ;;
    *)
        print_error "Unsupported operating system: $(uname -s)"
        exit 1
        ;;
    esac

    # Detect architecture
    case "$(uname -m)" in
    x86_64) arch="x64" ;;
    arm64) arch="arm64" ;;
    aarch64) arch="arm64" ;;
    *)
        print_error "Unsupported architecture: $(uname -m)"
        exit 1
        ;;
    esac

    # For Ubuntu x64, check for Vulkan support if not explicitly disabled
    if [ "$os" = "ubuntu" ] && [ "$arch" = "x64" ] && [ "$FORCE_REGULAR" != "1" ]; then
        if [ "$FORCE_VULKAN" = "1" ]; then
            variant="vulkan"
        elif check_vulkan_support; then
            variant="vulkan"
        fi
    fi

    if [ -n "$variant" ]; then
        echo "${os}-${variant}-${arch}"
    else
        echo "${os}-${arch}"
    fi
}

# Function to check if Vulkan is available on the system
check_vulkan_support() {
    # Check if vulkan-utils is installed
    if command -v vulkaninfo >/dev/null 2>&1; then
        # Try to run vulkaninfo to see if Vulkan is actually working
        if vulkaninfo >/dev/null 2>&1; then
            return 0
        fi
    fi

    # Check for Vulkan loader library
    if [ -f "/usr/lib/x86_64-linux-gnu/libvulkan.so.1" ] ||
        [ -f "/usr/lib/libvulkan.so.1" ] ||
        ldconfig -p 2>/dev/null | grep -q "libvulkan.so"; then
        return 0
    fi

    return 1
}

# Function to fetch data from GitHub API
github_get() {
    local api_url="$1"

    if command -v curl >/dev/null 2>&1; then
        curl -fsSL "$api_url"
    elif command -v wget >/dev/null 2>&1; then
        wget -qO- "$api_url"
    else
        print_error "Neither curl nor wget is available. Please install one of them."
        exit 1
    fi
}

# Function to get the latest bleeding-edge release
#
# llama.cpp bleeding-edge releases use the b[NUM] tag format.
# The GitHub releases API is queried for all releases and the first
# non-draft, non-prerelease b[NUM] release is selected.
get_latest_bleeding_release() {
    local releases_data

    releases_data=$(github_get "https://api.github.com/repos/ggml-org/llama.cpp/releases?per_page=10")

    if [ -z "$releases_data" ]; then
        print_error "Failed to fetch llama.cpp releases"
        return 1
    fi

    echo "$releases_data" |
        awk '
        /"tag_name":/ {
            if (match($0, /"b[0-9]+"/)) {
                tag = substr($0, RSTART + 1, RLENGTH - 2)
                print tag
                exit
            }
        }' |
        while read -r tag; do
            [ -n "$tag" ] && github_get "https://api.github.com/repos/ggml-org/llama.cpp/releases/tags/$tag"
        done
}

# Function to extract version from release data
get_version() {
    local release_data="$1"
    echo "$release_data" | grep '"tag_name"' | sed 's/.*"tag_name": *"\([^"]*\)".*/\1/'
}

# Function to find download URL for the current system
get_download_url() {
    local release_data="$1"
    local system_arch="$2"

    # Pattern to match the appropriate binary for the system
    local patterns=()
    case "$system_arch" in
    "ubuntu-x64")
        # Use tar.gz format for Linux releases
        patterns=("llama-.*-bin-ubuntu-x64\.tar\.gz")
        ;;
    "ubuntu-vulkan-x64")
        # Use tar.gz format for Linux releases
        patterns=("llama-.*-bin-ubuntu-vulkan-x64\.tar\.gz")
        ;;
    "ubuntu-arm64")
        print_error "Ubuntu ARM64 binaries are not available in llama.cpp releases"
        print_error "Only Ubuntu x64 is supported. Available Ubuntu packages:"
        echo "$release_data" | grep '"name"' | sed 's/.*"name": *"\([^"]*\)".*/\1/' | grep -i ubuntu
        exit 1
        ;;
    "macos-x64") patterns=("llama-.*-bin-macos-x64\.(tar\.gz|zip)") ;;
    "macos-arm64") patterns=("llama-.*-bin-macos-arm64\.(tar\.gz|zip)") ;;
    *)
        print_error "No pattern defined for system: $system_arch"
        exit 1
        ;;
    esac

    # Try each pattern in order and return the first match
    for pattern in "${patterns[@]}"; do
        local url
        url=$(echo "$release_data" | grep -o '"browser_download_url": *"[^"]*"' |
            grep -E "$pattern" |
            sed 's/.*"browser_download_url": *"\([^"]*\)".*/\1/' |
            head -n1)
        if [ -n "$url" ]; then
            echo "$url"
            return 0
        fi
    done

    # No URL found for any pattern
    return 1
}

# Function to download file
download_file() {
    local url="$1"
    local output="$2"

    print_info "Downloading from: $url"

    if command -v curl >/dev/null 2>&1; then
        curl -L -o "$output" "$url"
    elif command -v wget >/dev/null 2>&1; then
        wget -O "$output" "$url"
    else
        print_error "Neither curl nor wget is available."
        exit 1
    fi
}

# Function to extract zip file
extract_zip() {
    local zip_file="$1"
    local extract_dir="$2"

    if command -v unzip >/dev/null 2>&1; then
        unzip -q "$zip_file" -d "$extract_dir"
    else
        print_error "unzip is not available. Please install it."
        exit 1
    fi
}

# Function to extract tar.gz file
extract_targz() {
    local targz_file="$1"
    local extract_dir="$2"

    if command -v tar >/dev/null 2>&1; then
        tar -xzf "$targz_file" -C "$extract_dir"
    else
        print_error "tar is not available. Please install it."
        exit 1
    fi
}

# Function to move files from tar.gz extracted folder structure or build/bin to target directory
move_binaries() {
    local extract_dir="$1"
    local target_dir="$2"

    # Create target directory if it doesn't exist
    mkdir -p "$target_dir"

    # Check for version-specific folder (e.g., llama-b7330) from tar.gz archives
    local version_folder
    version_folder=$(find "$extract_dir" -maxdepth 1 -type d -name "llama-*" | head -n1)

    if [ -n "$version_folder" ] && [ -d "$version_folder" ]; then
        # tar.gz structure: extract_dir/llama-b7330/bin/*
        local bin_dir="$version_folder/bin"
        if [ -d "$bin_dir" ]; then
            print_info "Moving binaries from $version_folder/bin to $target_dir"
            for file in "$bin_dir"/*; do
                if [ -f "$file" ]; then
                    local filename
                    filename=$(basename "$file")
                    if [ -f "$target_dir/$filename" ]; then
                        print_warning "Overwriting existing file: $filename"
                    fi
                    mv "$file" "$target_dir/"
                    print_info "Moved: $filename"
                fi
            done
        else
            print_warning "bin directory not found in $version_folder"
            # Fallback: move all executable files from version folder
            for file in "$version_folder"/*; do
                if [ -f "$file" ] && [ -x "$file" ]; then
                    local filename
                    filename=$(basename "$file")
                    mv "$file" "$target_dir/"
                    print_info "Moved: $filename"
                fi
            done
        fi
        # Clean up version folder
        rm -rf "$version_folder"
    else
        # Fallback to zip structure: extract_dir/build/bin/*
        local build_bin_dir="$extract_dir/build/bin"
        if [ -d "$build_bin_dir" ]; then
            print_info "Moving binaries from build/bin to $target_dir"
            for file in "$build_bin_dir"/*; do
                if [ -f "$file" ]; then
                    local filename
                    filename=$(basename "$file")
                    if [ -f "$target_dir/$filename" ]; then
                        print_warning "Overwriting existing file: $filename"
                    fi
                    mv "$file" "$target_dir/"
                    print_info "Moved: $filename"
                fi
            done
            # Remove the empty build directory structure
            rm -rf "$extract_dir/build"
            print_info "Removed empty build directory"
        else
            print_warning "No bin directory found in extracted files"
            # Fallback: move all files from extract_dir
            for file in "$extract_dir"/*; do
                if [ -f "$file" ]; then
                    local filename
                    filename=$(basename "$file")
                    if [ -f "$target_dir/$filename" ]; then
                        print_warning "Overwriting existing file: $filename"
                    fi
                    mv "$file" "$target_dir/"
                    print_info "Moved: $filename"
                fi
            done
        fi
    fi
}

# Function to make binaries executable
make_executable() {
    local target_dir="$1"

    print_info "Making binaries executable"
    for file in "$target_dir"/*; do
        if [ -f "$file" ] && [[ ! $file =~ \.(txt|md|json)$ ]]; then
            chmod +x "$file"
        fi
    done
}

# Function to build from source
build_from_source() {
    local target_dir="$1"
    local temp_dir="$2"

    print_info "Building llama.cpp from source..."

    # Check for required build tools
    local missing_tools=""
    for tool in git cmake make; do
        if ! command -v "$tool" >/dev/null 2>&1; then
            missing_tools="$missing_tools $tool"
        fi
    done

    if [ -n "$missing_tools" ]; then
        print_error "Missing required build tools:$missing_tools"
        print_error "Please install them first:"
        print_error "  Ubuntu: sudo apt-get install git cmake build-essential"
        print_error "  macOS: brew install git cmake"
        exit 1
    fi

    # Check for optional dependencies and warn if missing
    local cmake_disable_flags=""

    # Check for CURL development libraries
    if ! pkg-config --exists libcurl 2>/dev/null &&
        ! [ -f "/usr/include/curl/curl.h" ] &&
        ! [ -f "/usr/local/include/curl/curl.h" ]; then
        print_warning "CURL development libraries not found, disabling CURL support"
        print_info "Install with: sudo apt-get install libcurl4-openssl-dev (Ubuntu) or brew install curl (macOS)"
        cmake_disable_flags="$cmake_disable_flags -DLLAMA_CURL=OFF"
    fi

    # Check for other optional dependencies
    if [ "$(uname -s)" = "Linux" ]; then
        # Check for additional Linux dependencies
        if ! pkg-config --exists zlib 2>/dev/null && ! [ -f "/usr/include/zlib.h" ]; then
            print_warning "zlib development libraries recommended for better compression"
            print_info "Install with: sudo apt-get install zlib1g-dev"
        fi
    fi

    # Clone the repository
    local repo_dir="$temp_dir/llama.cpp"
    print_info "Cloning llama.cpp repository..."
    if ! git clone https://github.com/ggml-org/llama.cpp.git "$repo_dir"; then
        print_error "Failed to clone repository"
        exit 1
    fi

    cd "$repo_dir"

    # Get the latest release tag
    local latest_tag
    latest_tag=$(git describe --tags --abbrev=0)
    print_info "Checking out latest release: $latest_tag"
    git checkout "$latest_tag"

    # Create build directory
    mkdir -p build
    cd build

    # Configure build with appropriate options
    local cmake_args=""

    # Detect and configure GPU support
    if [ "$(uname -s)" = "Linux" ]; then
        # Check for CUDA
        if command -v nvcc >/dev/null 2>&1; then
            print_info "CUDA detected, enabling CUDA support"
            cmake_args="$cmake_args -DGGML_CUDA=ON"
        # Check for Vulkan
        elif check_vulkan_support; then
            print_info "Vulkan detected, enabling Vulkan support"
            cmake_args="$cmake_args -DGGML_VULKAN=ON"
        # Check for OpenCL
        elif [ -f "/usr/lib/x86_64-linux-gnu/libOpenCL.so.1" ] || ldconfig -p 2>/dev/null | grep -q "libOpenCL.so"; then
            print_info "OpenCL detected, enabling OpenCL support"
            cmake_args="$cmake_args -DGGML_OPENCL=ON"
        fi
    elif [ "$(uname -s)" = "Darwin" ]; then
        # On macOS, enable Metal support
        print_info "macOS detected, enabling Metal support"
        cmake_args="$cmake_args -DGGML_METAL=ON"
    fi

    # Configure with CMake
    print_info "Configuring build with CMake..."
    if ! cmake .. "$cmake_args" "$cmake_disable_flags"; then
        print_error "CMake configuration failed"
        print_error "Common solutions:"
        print_error "  1. Install missing development libraries:"
        print_error "     Ubuntu: sudo apt-get install libcurl4-openssl-dev zlib1g-dev"
        print_error "     macOS: brew install curl"
        exit 1
    fi

    # Build
    print_info "Building llama.cpp (this may take several minutes)..."
    local cpu_count
    cpu_count=$(nproc 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo "4")
    if ! make -j"$cpu_count"; then
        print_error "Build failed"
        exit 1
    fi

    # Move binaries to target directory
    print_info "Installing built binaries to $target_dir"
    mkdir -p "$target_dir"

    # Copy all executables from bin directory
    if [ -d "bin" ]; then
        for file in bin/*; do
            if [ -f "$file" ] && [ -x "$file" ]; then
                local filename
                filename=$(basename "$file")
                if [ -f "$target_dir/$filename" ]; then
                    print_warning "Overwriting existing file: $filename"
                fi
                cp "$file" "$target_dir/"
                print_info "Installed: $filename"
            fi
        done
    fi

    # Also copy any dynamic libraries if they exist
    if [ -d "lib" ]; then
        for ext in so dylib; do
            for file in lib/*."$ext"; do
                if [ -f "$file" ]; then
                    local filename
                    filename=$(basename "$file")
                    cp "$file" "$target_dir/"
                    print_info "Installed library: $filename"
                fi
            done
        done
    fi

    cd - >/dev/null
    print_info "Build completed successfully!"
}

# Function to clean up temporary files
cleanup() {
    local temp_dir="$1"
    if [ -d "$temp_dir" ]; then
        rm -rf "$temp_dir"
        print_info "Cleaned up temporary files"
    fi
}

# Main function
main() {
    local target_dir="${1:-.}" # Use current directory if no parameter provided

    # Convert relative path to absolute path
    if [ "$target_dir" = "." ]; then
        target_dir=$(pwd)
    else
        # Create target directory if it doesn't exist
        mkdir -p "$target_dir"
        target_dir=$(cd "$target_dir" && pwd)
    fi

    print_info "llama.cpp Updater Script"
    print_info "Target directory: $target_dir"

    # Check if build from source is requested
    if [ "$BUILD_FROM_SOURCE" = "1" ]; then
        # Create temporary directory
        local temp_dir
        temp_dir=$(mktemp -d)

        # Set up cleanup trap
        trap 'cleanup "$temp_dir"' EXIT

        # Build from source
        build_from_source "$target_dir" "$temp_dir"

        print_info "Successfully built and installed llama.cpp from source"
        return 0
    fi

    # Detect system and architecture
    local system_arch
    system_arch=$(detect_system)
    if [ "$FORCE_VULKAN" = "1" ] && [[ $system_arch == *"vulkan"* ]]; then
        print_info "Forcing Vulkan build as requested"
    elif [[ $system_arch == *"vulkan"* ]]; then
        print_info "Vulkan support detected on system"
    fi
    print_info "Detected system: $system_arch"

    # Get latest bleeding-edge release
    print_info "Fetching latest bleeding-edge release information..."
    local release_data
    release_data=$(get_latest_bleeding_release) || true

    if [ -z "$release_data" ]; then
        print_error "Failed to fetch release information"
        exit 1
    fi

    # Extract version
    local version
    version=$(get_version "$release_data")
    if [ -z "$version" ]; then
        print_error "Failed to determine release version"
        exit 1
    fi
    print_info "Selected version: $version"

    # Get download URL
    local download_url
    download_url=$(get_download_url "$release_data" "$system_arch") || true

    if [ -z "$download_url" ]; then
        print_error "No suitable binary found for $system_arch"
        print_error "Available assets:"
        echo "$release_data" | grep '"name"' | sed 's/.*"name": *"\([^"]*\)".*/\1/' | grep -E '\.(zip|tar\.gz)$'
        exit 1
    fi

    print_info "Download URL: $download_url"

    # Create temporary directory
    local temp_dir
    temp_dir=$(mktemp -d)
    local archive_file="$temp_dir/llama-cpp.archive"
    local extract_dir="$temp_dir/extract"

    # Set up cleanup trap
    trap 'cleanup "$temp_dir"' EXIT

    # Download the file
    download_file "$download_url" "$archive_file"

    # Create extraction directory
    mkdir -p "$extract_dir"

    # Extract the downloaded archive
    print_info "Extracting files..."
    case "$download_url" in
    *.tar.gz)
        extract_targz "$archive_file" "$extract_dir"
        ;;
    *.zip)
        extract_zip "$archive_file" "$extract_dir"
        ;;
    *)
        print_error "Unsupported archive format: $download_url"
        exit 1
        ;;
    esac

    # Move binaries to target directory
    move_binaries "$extract_dir" "$target_dir"

    # Make binaries executable
    make_executable "$target_dir"

    print_info "Successfully updated llama.cpp to version $version"
    print_info "Binaries are available in: $target_dir"

    # List the installed files
    print_info "Installed files:"
    for file in "$target_dir"/*; do
        if [ -f "$file" ]; then
            local filename size
            filename=$(basename "$file")
            size=$(stat -c%s "$file" 2>/dev/null || stat -f%z "$file" 2>/dev/null || echo "unknown")
            echo "  $filename ($size bytes)"
        fi
    done
}

# Check if help is requested
if [ "$1" = "-h" ] || [ "$1" = "--help" ]; then
    echo "llama.cpp Updater & Builder Script"
    echo ""
    echo "Usage: $0 [OPTIONS] [target_directory]"
    echo ""
    echo "Downloads and installs the latest llama.cpp binaries for your system."
    echo ""
    echo "Options:"
    echo "  --build-from-source    Build from source instead of downloading binaries"
    echo "  --force-regular        Force regular Ubuntu build (disable Vulkan auto-detection)"
    echo "  --vulkan              Force Vulkan build for Ubuntu (if available)"
    echo "  -h, --help            Show this help message"
    echo ""
    echo "Arguments:"
    echo "  target_directory  Directory to install binaries (default: current directory)"
    echo ""
    echo "Examples:"
    echo "  $0                              # Download latest bleeding-edge release in current directory"
    echo "  $0 ./llama-bin                  # Download latest bleeding-edge release in ./llama-bin"
    echo "  $0 --build-from-source          # Build from source in current directory"
    echo "  $0 --build-from-source ./bin    # Build from source and install in ./bin"
    echo "  $0 --vulkan ./bin               # Force Vulkan build for Ubuntu"
    echo "  $0 --force-regular ./bin        # Force regular Ubuntu build (no Vulkan)"
    exit 0
fi

# Parse command line arguments
BUILD_FROM_SOURCE=""
FORCE_REGULAR=""
FORCE_VULKAN=""
TARGET_DIR=""

while [ $# -gt 0 ]; do
    case $1 in
    --build-from-source)
        BUILD_FROM_SOURCE="1"
        shift
        ;;
    --force-regular)
        FORCE_REGULAR="1"
        shift
        ;;
    --vulkan)
        FORCE_VULKAN="1"
        shift
        ;;
    -*)
        echo "Unknown option: $1"
        echo "Use --help for usage information."
        exit 1
        ;;
    *)
        if [ -z "$TARGET_DIR" ]; then
            TARGET_DIR="$1"
        else
            echo "Multiple target directories specified. Use --help for usage information."
            exit 1
        fi
        shift
        ;;
    esac
done

# Set default target directory if not specified
if [ -z "$TARGET_DIR" ]; then
    TARGET_DIR="."
fi

# Handle conflicting options
if [ "$FORCE_REGULAR" = "1" ] && [ "$FORCE_VULKAN" = "1" ]; then
    print_error "Cannot use both --force-regular and --vulkan options together"
    exit 1
fi

# Run main function
main "$TARGET_DIR"
