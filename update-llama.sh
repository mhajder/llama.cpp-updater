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

# Warnings and errors go to stderr so they stay visible when a function is
# called from a command substitution, and never end up in its captured value.
print_warning() {
    echo -e "${YELLOW}[WARN]${NC} $1" >&2
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
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

    # For Ubuntu, check for Vulkan support if not explicitly disabled
    if [ "$os" = "ubuntu" ] && [ "$FORCE_REGULAR" != "1" ]; then
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

# Function to check whether a path exists, counting dangling symlinks
path_exists() {
    [ -e "$1" ] || [ -L "$1" ]
}

# Cached result of check_vulkan_support ("yes" or "no"), as vulkaninfo can be slow
VULKAN_SUPPORT=""

# Function to check if Vulkan is available on the system
check_vulkan_support() {
    if [ -z "$VULKAN_SUPPORT" ]; then
        VULKAN_SUPPORT="no"
        if detect_vulkan; then
            VULKAN_SUPPORT="yes"
        fi
    fi
    [ "$VULKAN_SUPPORT" = "yes" ]
}

# Function to detect whether Vulkan is usable on the system
#
# When vulkan-utils is installed, the devices vulkaninfo lists are
# authoritative: the loader library alone says nothing about whether a usable
# driver is present. Its exit status is not used, because older versions fail
# when they cannot create window surfaces (e.g. over SSH) even though the GPU
# works. Software rasterisers such as llvmpipe report a CPU device and do not
# count.
detect_vulkan() {
    if command -v vulkaninfo >/dev/null 2>&1; then
        # A broken driver can hang vulkaninfo, so limit its run time if possible
        local output timeout_cmd=()
        if command -v timeout >/dev/null 2>&1; then
            timeout_cmd=(timeout 20)
        fi
        # --summary skips the surface queries but older versions lack it
        output=$("${timeout_cmd[@]}" vulkaninfo --summary 2>&1 ||
            "${timeout_cmd[@]}" vulkaninfo 2>&1 || true)
        echo "$output" | grep -qE 'PHYSICAL_DEVICE_TYPE_(DISCRETE|INTEGRATED|VIRTUAL)_GPU'
        return
    fi

    # Check for Vulkan loader library
    if ls /usr/lib/*-linux-gnu/libvulkan.so.1 >/dev/null 2>&1 ||
        [ -f "/usr/lib/libvulkan.so.1" ] ||
        ldconfig -p 2>/dev/null | grep -q "libvulkan.so"; then
        return 0
    fi

    return 1
}

# Function to check that the Vulkan backend can be built
check_vulkan_build_deps() {
    command -v glslc >/dev/null 2>&1 &&
        { pkg-config --exists vulkan 2>/dev/null || [ -f "/usr/include/vulkan/vulkan.h" ]; } &&
        { [ -d "/usr/include/spirv" ] || [ -d "/usr/local/include/spirv" ]; }
}

# Function to locate nvcc, which the CUDA toolkit installs outside PATH
find_nvcc() {
    local candidate
    for candidate in "$(command -v nvcc 2>/dev/null)" \
        "${CUDA_HOME:+$CUDA_HOME/bin/nvcc}" "${CUDA_PATH:+$CUDA_PATH/bin/nvcc}" \
        /usr/local/cuda/bin/nvcc; do
        if [ -n "$candidate" ] && [ -x "$candidate" ]; then
            echo "$candidate"
            return 0
        fi
    done
    return 1
}

# Download tool (curl or wget). It is chosen once, in the main shell, so a
# missing tool is reported as such rather than as a failed request.
DOWNLOADER=""

select_downloader() {
    if command -v curl >/dev/null 2>&1; then
        DOWNLOADER="curl"
    elif command -v wget >/dev/null 2>&1; then
        DOWNLOADER="wget"
    else
        print_error "Neither curl nor wget is available. Please install one of them."
        exit 1
    fi
}

# Function to fetch a URL into a file ("-" for stdout)
#
# Usage: http_fetch URL OUTPUT [quiet] [TOKEN] [TIMEOUT]
# Without --fail an HTTP error page is written out as if it were the
# requested data. A token goes through stdin or a private config file inside
# TEMP_DIR, never the command line, where other users could see it in ps.
# TIMEOUT (seconds) also limits wget to a single attempt.
http_fetch() {
    local url="$1" output="$2" quiet="$3" token="$4" timeout="$5"
    local args=()

    if [ "$DOWNLOADER" = "curl" ]; then
        args=(-fL -o "$output")
        if [ -n "$quiet" ]; then
            args+=(-sS)
        fi
        if [ -n "$timeout" ]; then
            args+=(--max-time "$timeout")
        fi
        if [ -n "$token" ]; then
            printf 'Authorization: Bearer %s\n' "$token" | curl "${args[@]}" -H @- "$url"
        else
            curl "${args[@]}" "$url"
        fi
    else
        args=(-O "$output")
        if [ -n "$quiet" ]; then
            args+=(-q)
        fi
        if [ -n "$timeout" ]; then
            args+=(--timeout="$timeout" --tries=1)
        fi
        if [ -n "$token" ]; then
            # WGETRC replaces the user's config file, so carry its settings
            # (proxies, CA certificates) over into the temporary one
            local wgetrc status=0
            wgetrc=$(mktemp "$TEMP_DIR/wgetrc.XXXXXX")
            cat "${WGETRC:-$HOME/.wgetrc}" >"$wgetrc" 2>/dev/null || true
            printf '\nheader = Authorization: Bearer %s\n' "$token" >>"$wgetrc"
            # wget sends custom headers on to wherever a redirect points
            # (curl drops them when the host changes), so do not follow any
            WGETRC="$wgetrc" wget --max-redirect=0 "${args[@]}" "$url" || status=$?
            rm -f "$wgetrc"
            return "$status"
        else
            wget "${args[@]}" "$url"
        fi
    fi
}

# Function to fetch data from GitHub API
#
# GITHUB_TOKEN (or GH_TOKEN) is sent when set, which raises the API rate limit
# from 60 to 5000 requests per hour. The repository is public, so if the token
# is rejected (e.g. expired) the request is retried without it.
github_get() {
    local api_url="$1"
    local token="${GITHUB_TOKEN:-$GH_TOKEN}"
    local response

    if [ -n "$token" ]; then
        # Buffered, so a failed attempt cannot leave partial output behind
        if response=$(http_fetch "$api_url" - quiet "$token"); then
            printf '%s\n' "$response"
            return 0
        fi
        print_warning "GitHub API request with GITHUB_TOKEN failed, retrying without it (is the token expired?)"
    fi
    http_fetch "$api_url" - quiet
}

# Hint printed when the GitHub API cannot be queried
API_FAILURE_HINT="Check your network connection; if GitHub's API rate limit was hit, set a valid GITHUB_TOKEN"

# Function to fetch the latest llama.cpp releases
#
# The list response already holds every asset of each release, including its
# sha256 digest, so this one request is all a binary install needs.
get_releases() {
    github_get "https://api.github.com/repos/ggml-org/llama.cpp/releases?per_page=10"
}

# Function to list the tags of the bleeding-edge releases, newest first
#
# llama.cpp bleeding-edge releases use the b[NUM] tag format and are all
# published as prereleases, so the prerelease flag is deliberately ignored.
# The GitHub releases API lists releases newest first (drafts are not visible
# without authentication). Older tags are kept so the caller can fall back to
# them while the newest release is still having its assets uploaded.
list_release_tags() {
    local releases_data="$1"

    echo "$releases_data" |
        grep -oE '"tag_name": *"b[0-9]+"' |
        sed 's/.*"\(b[0-9]*\)"/\1/'
}

# Function to list the assets of all fetched releases as "TAG URL DIGEST" lines
#
# GitHub emits each asset's digest before its browser_download_url, so the two
# are paired by document order, and the tag is taken from the URL path
# (.../releases/download/TAG/NAME). Each token is matched individually, so
# this works whether the API returns pretty-printed or single-line JSON.
# DIGEST is "null" for assets uploaded before GitHub recorded digests.
list_assets() {
    local releases_data="$1"

    echo "$releases_data" |
        grep -oE '"(digest|browser_download_url)": *("[^"]*"|null)' |
        sed -E 's/^"([a-z_]+)": *"?([^"]*)"?$/\1 \2/' |
        awk -v prefix="https://github.com/ggml-org/llama.cpp/releases/download/" '
            $1 == "digest" { digest = $2; next }
            {
                if (index($2, prefix) == 1) {
                    rest = substr($2, length(prefix) + 1)
                    slash = index(rest, "/")
                    if (slash > 1) print substr(rest, 1, slash - 1), $2, (digest == "" ? "null" : digest)
                }
                digest = ""
            }'
}

# Function to print the asset name patterns for a system, most preferred first
asset_patterns() {
    case "$1" in
    "ubuntu-x64")
        # Use tar.gz format for Linux releases
        echo 'llama-[^/]*-bin-ubuntu-x64\.tar\.gz'
        ;;
    "ubuntu-vulkan-x64")
        echo 'llama-[^/]*-bin-ubuntu-vulkan-x64\.tar\.gz'
        # Fall back to the regular build, unless --vulkan insists on Vulkan
        if [ "$FORCE_VULKAN" != "1" ]; then
            echo 'llama-[^/]*-bin-ubuntu-x64\.tar\.gz'
        fi
        ;;
    "ubuntu-arm64")
        echo 'llama-[^/]*-bin-ubuntu-arm64\.tar\.gz'
        ;;
    "ubuntu-vulkan-arm64")
        echo 'llama-[^/]*-bin-ubuntu-vulkan-arm64\.tar\.gz'
        if [ "$FORCE_VULKAN" != "1" ]; then
            echo 'llama-[^/]*-bin-ubuntu-arm64\.tar\.gz'
        fi
        ;;
    "macos-x64") echo 'llama-[^/]*-bin-macos-x64\.(tar\.gz|zip)' ;;
    "macos-arm64") echo 'llama-[^/]*-bin-macos-arm64\.(tar\.gz|zip)' ;;
    *) return 1 ;;
    esac
}

# Function to find the newest release with an asset matching a pattern
#
# Prints the matching "TAG URL DIGEST" line. A release becomes visible before
# CI has uploaded all of its assets, so the newest release can briefly lack
# the one this system needs.
find_asset() {
    local assets="$1"
    local tags="$2"
    local pattern="$3"
    local tag match

    for tag in $tags; do
        match=$(echo "$assets" | grep -E "^$tag [^ ]*/${pattern} " | head -n1)
        if [ -n "$match" ]; then
            echo "$match"
            return 0
        fi
    done
    return 1
}

# Function to download file
download_file() {
    local url="$1"
    local output="$2"

    print_info "Downloading from: $url"
    if ! http_fetch "$url" "$output"; then
        print_error "Download failed: $url"
        exit 1
    fi
}

# Function to verify a download against the sha256 digest GitHub recorded
verify_checksum() {
    local file="$1"
    local digest="$2"

    if [[ $digest != sha256:* ]]; then
        print_warning "No sha256 digest published for this asset, skipping checksum verification"
        return 0
    fi

    local actual
    if command -v sha256sum >/dev/null 2>&1; then
        actual=$(sha256sum "$file" | cut -d' ' -f1)
    elif command -v shasum >/dev/null 2>&1; then
        actual=$(shasum -a 256 "$file" | cut -d' ' -f1)
    else
        print_warning "Neither sha256sum nor shasum is available, skipping checksum verification"
        return 0
    fi

    if [ "$actual" != "${digest#sha256:}" ]; then
        print_error "Checksum mismatch for the downloaded archive"
        print_error "  expected: ${digest#sha256:}"
        print_error "  actual:   $actual"
        exit 1
    fi
    print_info "Checksum verified (sha256)"
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

# File in the target directory recording what the last run installed: a
# "#installed ID" line naming the asset (or source tag), then one file name
# per line. It lets the next run skip an unchanged release and remove its own
# stale files without touching anything else.
MANIFEST_NAME=".llama-cpp-updater-manifest"

# Install state, shared with the EXIT trap
#
# New files are staged in a directory inside the target, so putting them in
# place is a same-filesystem rename. Every file they replace, and every stale
# file, is parked in a backup directory until the swap has completed, so a
# failure at any point rolls back to the previous installation. A lock
# directory keeps two runs from updating the same target at once.
INSTALL_TARGET=""
LOCK_DIR=""
STAGE_DIR=""
BACKUP_DIR=""
INSTALLED_FILES=() # names staged for installation
SWAPPED_IN=()      # names moved (or about to be moved) from STAGE_DIR into the target
BACKED_UP=()       # names moved (or about to be moved) from the target into BACKUP_DIR
INSTALL_DONE=""

# Marks a target whose llama-server still has to be restarted onto the new
# binaries, so a restart that timed out or failed is retried by the next run
RESTART_MARKER_NAME=".llama-cpp-updater.restart-pending"

# Function to check whether a name is among the remaining arguments
contains() {
    local needle="$1" item
    shift
    for item in "$@"; do
        if [ "$item" = "$needle" ]; then
            return 0
        fi
    done
    return 1
}

# Function to lock the target directory against concurrent updates
acquire_lock() {
    local lock="$INSTALL_TARGET/.llama-cpp-updater.lock" pid

    if ! mkdir "$lock" 2>/dev/null; then
        if [ ! -d "$lock" ]; then
            print_error "Cannot write to $INSTALL_TARGET"
            exit 1
        fi
        pid=$(cat "$lock/pid" 2>/dev/null || true)
        # A lock without a PID may belong to a run that is just starting
        if { [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; } ||
            { [ -z "$pid" ] && [ -z "$(find "$lock" -maxdepth 0 -mmin +1 2>/dev/null)" ]; }; then
            print_error "Another update is already running in $INSTALL_TARGET"
            exit 1
        fi
        print_warning "Removing the stale lock of an interrupted update"
        rm -rf "$lock"
        mkdir "$lock"
    fi
    LOCK_DIR="$lock"
    echo "$$" >"$lock/pid"
}

# Function to prepare the target directory for an update
#
# Called before anything is downloaded or built, so an unwritable target
# fails fast instead of after a long build.
begin_install() {
    INSTALL_TARGET="$1"
    acquire_lock

    # A staging directory left by an interrupted run holds only new files and
    # can go. A leftover backup directory may hold the previous installation,
    # so it is only removed when empty.
    local dir
    for dir in "$INSTALL_TARGET"/.llama-cpp-updater.new.*; do
        if [ -d "$dir" ]; then
            rm -rf "$dir"
        fi
    done
    for dir in "$INSTALL_TARGET"/.llama-cpp-updater.old.*; do
        if [ -d "$dir" ] && ! rmdir "$dir" 2>/dev/null; then
            print_warning "Files from an interrupted update are kept in $dir; restore or delete them"
        fi
    done

    STAGE_DIR=$(mktemp -d "$INSTALL_TARGET/.llama-cpp-updater.new.XXXXXX")
    BACKUP_DIR=$(mktemp -d "$INSTALL_TARGET/.llama-cpp-updater.old.XXXXXX")
}

# Function to print the file names the previous run recorded in its manifest
read_manifest() {
    local manifest="$INSTALL_TARGET/$MANIFEST_NAME" name
    if [ ! -f "$manifest" ]; then
        return 0
    fi

    while IFS= read -r name || [ -n "$name" ]; do
        # Only plain names of files directly inside the target are trusted
        case "$name" in
        "" | "#"* | . | .. | */* | .llama-cpp-updater*) continue ;;
        esac
        echo "$name"
    done <"$manifest"
}

# Function to check whether the given asset or source tag is already installed
is_installed() {
    local install_id="$1"
    local manifest="$INSTALL_TARGET/$MANIFEST_NAME" name

    if [ ! -f "$manifest" ] ||
        [ "$(sed -n 's/^#installed //p' "$manifest" | head -n1)" != "$install_id" ]; then
        return 1
    fi

    # Every recorded file must still be present
    while IFS= read -r name; do
        if ! path_exists "$INSTALL_TARGET/$name"; then
            return 1
        fi
    done < <(read_manifest)
}

# Function to swap the staged files into the target directory
commit_install() {
    local install_id="$1"
    local target_dir="$INSTALL_TARGET" name
    local previous=() have_manifest="" replaced=0

    if [ -f "$target_dir/$MANIFEST_NAME" ]; then
        have_manifest=1
    fi
    while IFS= read -r name; do
        previous+=("$name")
    done < <(read_manifest)

    print_info "Installing files into $target_dir"

    # The new manifest is swapped in last, together with the files, so an
    # interrupted update restores the old manifest along with the old files
    {
        echo "#installed $install_id"
        printf '%s\n' "${INSTALLED_FILES[@]}"
    } >"$STAGE_DIR/$MANIFEST_NAME"

    # Each name is recorded before its mv, so an interrupt between the two can
    # never leave a moved file unknown to rollback_install
    for name in "${INSTALLED_FILES[@]}" "$MANIFEST_NAME"; do
        if path_exists "$target_dir/$name"; then
            if [ "$name" = "$MANIFEST_NAME" ]; then
                :
            elif [ -z "$have_manifest" ]; then
                replaced=$((replaced + 1))
            elif ! contains "$name" "${previous[@]}"; then
                print_warning "Overwriting existing file: $name"
            fi
            BACKED_UP+=("$name")
            mv "$target_dir/$name" "$BACKUP_DIR/"
        fi
        SWAPPED_IN+=("$name")
        mv "$STAGE_DIR/$name" "$target_dir/"
    done

    # Remove files the previous run installed that this release no longer has
    for name in "${previous[@]}"; do
        if ! contains "$name" "${INSTALLED_FILES[@]}" && path_exists "$target_dir/$name"; then
            BACKED_UP+=("$name")
            mv "$target_dir/$name" "$BACKUP_DIR/"
            print_info "Removed stale file: $name"
        fi
    done

    INSTALL_DONE=1

    if [ -n "$RESTART_CMD" ]; then
        : >"$target_dir/$RESTART_MARKER_NAME" ||
            print_warning "Cannot record the pending restart; an interrupted restart will not be retried"
    fi

    # Without a manifest (a first run, or a directory filled by an older
    # version of this script) nothing is known about the existing files, so
    # they are summarised instead of warned about one by one
    if [ -z "$have_manifest" ]; then
        if [ "$replaced" -gt 0 ]; then
            print_warning "Replaced $replaced existing files (no earlier install by this script is recorded here)"
        fi
        report_leftovers
    fi
}

# Function to list files that look like leftovers of an earlier llama.cpp
# install which no manifest accounts for. They are reported, not removed, as
# they may not have come from this script.
report_leftovers() {
    local file name leftovers=()
    for file in "$INSTALL_TARGET"/*; do
        name=$(basename "$file")
        case "$name" in
        llama-* | libllama* | libggml* | libmtmd* | ggml-* | rpc-server | LICENSE*)
            if path_exists "$file" && ! contains "$name" "${INSTALLED_FILES[@]}"; then
                leftovers+=("$name")
            fi
            ;;
        esac
    done

    if [ ${#leftovers[@]} -gt 0 ]; then
        print_warning "These files look like leftovers of an earlier llama.cpp install and were kept:"
        printf '  %s\n' "${leftovers[@]}" >&2
    fi
}

# Function to restore the previous installation after a failed update
#
# A name may have been recorded just before its mv was interrupted, so every
# step checks what is actually there. Returns non-zero if a parked file could
# not be moved back, in which case the backup directory is kept.
rollback_install() {
    if [ ${#SWAPPED_IN[@]} -eq 0 ] && [ ${#BACKED_UP[@]} -eq 0 ]; then
        return 0
    fi

    print_warning "Update failed, restoring the previous installation"
    local name failed=0
    for name in "${SWAPPED_IN[@]}"; do
        rm -rf "${INSTALL_TARGET:?}/${name:?}" || failed=1
    done
    for name in "${BACKED_UP[@]}"; do
        if path_exists "$BACKUP_DIR/$name"; then
            mv "$BACKUP_DIR/$name" "$INSTALL_TARGET/" || failed=1
        fi
    done

    if [ "$failed" = "1" ]; then
        print_error "Could not fully restore the previous installation"
        print_error "The replaced files are kept in $BACKUP_DIR"
        return 1
    fi
}

# Function to stage the extracted release payload for installation
#
# Current archives hold a single llama-b[NUM] directory with the binaries and
# their shared libraries side by side. Older archives nested the payload under
# bin/ or build/bin, so those layouts are still recognised.
stage_binaries() {
    local extract_dir="$1"

    # Locate the directory holding the payload
    local version_folder source_dir
    version_folder=$(find "$extract_dir" -maxdepth 1 -type d -name "llama-*" | head -n1)

    if [ -n "$version_folder" ] && [ -d "$version_folder/bin" ]; then
        source_dir="$version_folder/bin"
    elif [ -n "$version_folder" ]; then
        source_dir="$version_folder"
    elif [ -d "$extract_dir/build/bin" ]; then
        source_dir="$extract_dir/build/bin"
    else
        source_dir="$extract_dir"
    fi

    print_info "Staging files from $source_dir"

    local file filename
    for file in "$source_dir"/*; do
        # Dangling symlinks count too, as their target may come later
        if path_exists "$file"; then
            filename=$(basename "$file")
            mv "$file" "$STAGE_DIR/"
            INSTALLED_FILES+=("$filename")
        fi
    done

    if [ ${#INSTALLED_FILES[@]} -eq 0 ]; then
        print_error "The archive contained no files to install"
        exit 1
    fi
}

# Function to check whether a file is a native binary or a script
#
# Detected by magic number: ELF, Mach-O (32/64-bit in either byte order, or
# universal) or a #! line, so LICENSE files and other data are left alone.
is_executable_file() {
    local magic
    magic=$(od -An -tx1 -N4 "$1" 2>/dev/null | tr -d ' \n')
    case "$magic" in
    7f454c46 | feedface | feedfacf | cefaedfe | cffaedfe | cafebabe | 2321*) return 0 ;;
    *) return 1 ;;
    esac
}

# Function to make the staged binaries executable
make_executable() {
    print_info "Making binaries executable"
    local filename file
    for filename in "${INSTALLED_FILES[@]}"; do
        file="$STAGE_DIR/$filename"
        if [ -f "$file" ] && [ ! -L "$file" ] && is_executable_file "$file"; then
            chmod +x "$file"
        fi
    done
}

# Function to stage a built file for installation
#
# Symlinks are copied as symlinks so versioned library names stay links instead
# of full copies.
stage_built_file() {
    local file="$1"
    local filename
    filename=$(basename "$file")

    # bin/ and lib/ can both hold the same library; the first copy wins
    if path_exists "$STAGE_DIR/$filename"; then
        return 0
    fi
    cp -P "$file" "$STAGE_DIR/"
    INSTALLED_FILES+=("$filename")
}

# Function to build from source and install the result
build_from_source() {
    local temp_dir="$1"

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

    # The test suite is not installed, so skip building it
    local cmake_args=("-DLLAMA_BUILD_TESTS=OFF")

    # Check for other optional dependencies
    if [ "$(uname -s)" = "Linux" ]; then
        # Check for additional Linux dependencies
        if ! pkg-config --exists zlib 2>/dev/null && ! [ -f "/usr/include/zlib.h" ]; then
            print_warning "zlib development libraries recommended for better compression"
            print_info "Install with: sudo apt-get install zlib1g-dev"
        fi
        # llama.cpp downloads models over HTTPS through OpenSSL
        if ! pkg-config --exists openssl 2>/dev/null && ! [ -f "/usr/include/openssl/ssl.h" ]; then
            print_warning "OpenSSL development libraries not found, llama.cpp will be built without HTTPS model downloads"
            print_info "Install with: sudo apt-get install libssl-dev"
        fi
    fi

    # Build the newest published b[NUM] release. Its tag is pushed before the
    # release CI finishes (and the release is never published if CI fails), so
    # the newest git tag is only a fallback for when the API is unreachable.
    local repo_url="https://github.com/ggml-org/llama.cpp.git"
    local latest_tag releases_data
    releases_data=$(get_releases) || true
    latest_tag=$(list_release_tags "$releases_data" | head -n1)
    if [ -z "$latest_tag" ]; then
        print_warning "Could not query published releases, using the newest b[NUM] git tag instead"
        print_info "$API_FAILURE_HINT"
        # Sorted numerically here, as ls-remote --sort needs git 2.18 or newer
        latest_tag=$(git ls-remote --tags --refs "$repo_url" 'refs/tags/b*' |
            sed -n 's#.*refs/tags/\(b[0-9][0-9]*\)$#\1#p' | sort -t b -k2 -n | tail -n1)
    fi
    if [ -z "$latest_tag" ]; then
        print_error "Failed to determine the latest llama.cpp release tag"
        exit 1
    fi

    local install_id="source $latest_tag"
    if [ "$FORCE_INSTALL" != "1" ] && is_installed "$install_id"; then
        print_info "Already up to date: $latest_tag is installed from source (use --force to rebuild)"
        return 0
    fi

    # Shallow clone of just that release
    local repo_dir="$temp_dir/llama.cpp"
    print_info "Cloning llama.cpp release $latest_tag..."
    if ! git clone --depth 1 --branch "$latest_tag" "$repo_url" "$repo_dir"; then
        print_error "Failed to clone repository"
        exit 1
    fi

    local orig_dir="$PWD"
    cd "$repo_dir"

    # Create build directory
    mkdir -p build
    cd build

    # Detect and configure GPU support
    local nvcc_path
    if [ "$(uname -s)" = "Linux" ]; then
        # --vulkan forces the Vulkan backend, --force-regular rules it out
        if [ "$FORCE_VULKAN" = "1" ]; then
            if ! check_vulkan_build_deps; then
                print_error "Vulkan was requested but its build dependencies are missing"
                print_error "Install with: sudo apt-get install libvulkan-dev glslc spirv-headers"
                exit 1
            fi
            print_info "Forcing Vulkan support as requested"
            cmake_args+=("-DGGML_VULKAN=ON")
        # Check for CUDA (nvcc is passed explicitly, as it may not be on PATH)
        elif nvcc_path=$(find_nvcc); then
            print_info "CUDA detected ($nvcc_path), enabling CUDA support"
            cmake_args+=("-DGGML_CUDA=ON" "-DCMAKE_CUDA_COMPILER=$nvcc_path")
        # Check for Vulkan (the backend needs glslc, Vulkan and SPIR-V headers)
        elif [ "$FORCE_REGULAR" != "1" ] && check_vulkan_support && check_vulkan_build_deps; then
            print_info "Vulkan detected, enabling Vulkan support"
            cmake_args+=("-DGGML_VULKAN=ON")
        # Check for OpenCL (the backend needs the OpenCL headers, Python 3 and
        # the unversioned libOpenCL.so development link CMake searches for)
        elif [ -f "/usr/include/CL/cl.h" ] && command -v python3 >/dev/null 2>&1 &&
            { ls /usr/lib/*-linux-gnu/libOpenCL.so >/dev/null 2>&1 || [ -e "/usr/lib/libOpenCL.so" ]; }; then
            print_info "OpenCL detected, enabling OpenCL support"
            cmake_args+=("-DGGML_OPENCL=ON")
        elif [ "$FORCE_REGULAR" != "1" ] && check_vulkan_support; then
            print_warning "Vulkan runtime found but build dependencies are missing, building without Vulkan"
            print_info "Install with: sudo apt-get install libvulkan-dev glslc spirv-headers"
        fi
        # Let installed binaries find their shared libraries next to them
        # shellcheck disable=SC2016 # $ORIGIN is expanded by the dynamic loader
        cmake_args+=("-DCMAKE_BUILD_WITH_INSTALL_RPATH=ON" '-DCMAKE_INSTALL_RPATH=$ORIGIN')
    elif [ "$(uname -s)" = "Darwin" ]; then
        # On macOS, enable Metal support
        print_info "macOS detected, enabling Metal support"
        cmake_args+=("-DGGML_METAL=ON")
        # Let installed binaries find their shared libraries next to them
        cmake_args+=("-DCMAKE_BUILD_WITH_INSTALL_RPATH=ON" "-DCMAKE_INSTALL_RPATH=@loader_path")
    fi

    # Configure with CMake
    print_info "Configuring build with CMake..."
    if ! cmake .. "${cmake_args[@]}"; then
        print_error "CMake configuration failed"
        print_error "Check the CMake output above for the missing dependency"
        exit 1
    fi

    # Build
    print_info "Building llama.cpp (this may take several minutes)..."
    local cpu_count
    cpu_count=$(nproc 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo "4")
    if ! cmake --build . --parallel "$cpu_count"; then
        print_error "Build failed"
        exit 1
    fi

    # Copy all executables (and the shared libraries built next to them)
    if [ -d "bin" ]; then
        for file in bin/*; do
            if [ -f "$file" ] && [ -x "$file" ]; then
                stage_built_file "$file"
            fi
        done
    fi

    # Also copy any dynamic libraries if they exist
    if [ -d "lib" ]; then
        for file in lib/*.so lib/*.so.* lib/*.dylib; do
            if [ -f "$file" ]; then
                stage_built_file "$file"
            fi
        done
    fi

    if [ ${#INSTALLED_FILES[@]} -eq 0 ]; then
        print_error "The build produced no files to install"
        exit 1
    fi

    cd "$orig_dir"
    print_info "Build completed successfully!"

    commit_install "$install_id"
    print_info "Successfully built and installed llama.cpp $latest_tag from source"
}

# Restarting llama-server after an update (--restart-cmd, --wait-idle)
#
# A running llama-server keeps the binaries it started with, so an update
# never disturbs it; it only runs the new release once restarted. With
# --wait-idle the restart waits until the server has handled no request for
# --idle-seconds. The server is watched through endpoints that leave it alone:
# GET /props reports sleep without waking it, and GET /metrics neither wakes
# it nor resets its --sleep-idle-seconds timer. GET /slots does both, so it is
# only a fallback for servers started without --metrics.
POLL_INTERVAL=5   # seconds between two looks at the server
SERVER_TIMEOUT=30 # seconds a single request to the server may take
SERVER_STATE=""   # set by server_activity: idle, busy, down or error
SERVER_DETAIL=""  # what made SERVER_STATE what it is
SLOTS_WARNED=""
COUNTERS_SEEN="" # "LABEL<TAB>COUNTERS" lines kept by counters_changed

# Function to percent-encode a string for use in a URL query
url_encode() {
    local LC_ALL=C
    local str="$1" out="" c i
    for ((i = 0; i < ${#str}; i++)); do
        c="${str:i:1}"
        case "$c" in
        [A-Za-z0-9._~-]) out+="$c" ;;
        *) out+=$(printf '%%%02X' "'$c") ;;
        esac
    done
    printf '%s' "$out"
}

# Function to send a GET request to the server given by --wait-idle
#
# Usage: server_get PATH
# Prints the response body. Returns 0 for a successful response, 2 when the
# server cannot be reached at all and 1 for any other failure (an HTTP error
# status, a timeout). LLAMA_API_KEY is sent as the bearer token, the same
# variable llama-server reads its --api-key from (which may list several
# comma-separated keys, any one of which is accepted).
server_get() {
    local status=0 messages="" key="${LLAMA_API_KEY:-}"
    key="${key%%,*}"

    if [ "$DOWNLOADER" = "curl" ]; then
        http_fetch "$WAIT_IDLE_URL$1" - quiet "$key" "$SERVER_TIMEOUT" 2>/dev/null || status=$?
        case "$status" in
        0) return 0 ;;
        6 | 7) return 2 ;; # unresolvable host, connection refused
        *) return 1 ;;
        esac
    fi

    # wget exits with 4 both when nothing answers and when a busy server is
    # too slow to, so its (untranslated) messages tell the two apart
    { messages=$(LC_ALL=C http_fetch "$WAIT_IDLE_URL$1" - "" "$key" "$SERVER_TIMEOUT" 2>&1 >&3); } 3>&1 || status=$?
    if [ "$status" -eq 0 ]; then
        return 0
    elif [ "$status" -eq 4 ] &&
        echo "$messages" | grep -qE 'Connection refused|unable to resolve host|No route to host'; then
        return 2
    fi
    return 1
}

# Function to list the models of a router-mode server as "STATUS ID" lines
#
# Each model object in GET /models holds its "id" ahead of its
# "status": {"value": ...}, so the two are paired by document order.
list_router_models() {
    echo "$1" |
        grep -oE '"(id|value)": *"[^"]*"' |
        sed -E 's/^"([a-z]+)": *"(.*)"$/\1 \2/' |
        awk '$1 == "id" { id = substr($0, 4); next }
             id != "" { print $2, id; id = "" }'
}

# Function to check whether one model is handling requests
#
# Usage: probe_model [MODEL]
# MODEL selects a model of a router-mode server; autoload=false keeps the
# query from loading a model that is not loaded. Sets SERVER_STATE.
probe_model() {
    local model="$1" query="" body label="llama-server"

    if [ -n "$model" ]; then
        query="?model=$(url_encode "$model")&autoload=false"
        label="model $model"
    fi

    # Prints "BUSY COUNTERS": BUSY is 1 while requests are being processed or
    # queued, COUNTERS the totals that every request advances
    local summary busy counters
    if body=$(server_get "/metrics$query") &&
        summary=$(echo "$body" | awk '
            /^llamacpp:requests_(processing|deferred) / { n += $2; found = 1 }
            /^llamacpp:(n_decode_total|prompt_tokens_total|tokens_predicted_total) / { c = c "," $2 }
            END { if (!found) exit 1; print (n > 0), c }'); then
        read -r busy counters <<<"$summary"
    elif body=$(server_get "/slots$query"); then
        if [ -z "$SLOTS_WARNED" ]; then
            print_warning "GET /metrics is not available, falling back to GET /slots, which keeps the model from sleeping while the restart waits; start llama-server with --metrics to avoid this"
            SLOTS_WARNED=1
        fi
        busy=0
        if echo "$body" | grep -qE '"is_processing": *true'; then
            busy=1
        fi
        counters=$(echo "$body" | grep -oE '"(id_task|n_decoded)": *-?[0-9]+' | tr -d ' \n')
    else
        SERVER_STATE="error"
        SERVER_DETAIL="neither GET /metrics nor GET /slots answered for $label"
        return 0
    fi

    # A request that starts and ends between two looks is never seen being
    # processed, but it does move the counters
    if counters_changed "$label" "$counters" || [ "$busy" = "1" ]; then
        SERVER_STATE="busy"
        SERVER_DETAIL="$label is handling requests"
    else
        SERVER_STATE="idle"
    fi
}

# Function to remember a model's activity counters
#
# Usage: counters_changed LABEL COUNTERS
# Returns 0 if COUNTERS differ from what the previous look at LABEL saw.
counters_changed() {
    local label="$1" counters="$2" tab=$'\t' line seen="" rest=""
    while IFS= read -r line; do
        if [ "${line%%"$tab"*}" = "$label" ]; then
            seen="${line#*"$tab"}"
        elif [ -n "$line" ]; then
            rest+="$line"$'\n'
        fi
    done <<<"$COUNTERS_SEEN"
    COUNTERS_SEEN="$rest$label$tab$counters"
    [ -n "$seen" ] && [ "$seen" != "$counters" ]
}

# Function to take one look at the server and set SERVER_STATE
#
# down: not reachable, so there is nothing to interrupt
# busy: loading a model or handling a request
# idle: handling nothing (a sleeping server counts as idle)
# error: reachable, but its activity cannot be read (e.g. a wrong API key)
server_activity() {
    local status=0 body models state id

    SERVER_DETAIL=""
    # /health needs no API key and answers 503 while a model is loading
    server_get /health >/dev/null || status=$?
    if [ "$status" -eq 2 ]; then
        SERVER_STATE="down"
        return 0
    elif [ "$status" -ne 0 ]; then
        SERVER_STATE="busy"
        SERVER_DETAIL="GET /health is not OK (loading a model?)"
        return 0
    fi

    if ! body=$(server_get /props); then
        SERVER_STATE="error"
        SERVER_DETAIL="GET /props failed (if the server uses --api-key, set LLAMA_API_KEY)"
        return 0
    fi

    if ! echo "$body" | grep -qE '"role": *"router"'; then
        if echo "$body" | grep -qE '"is_sleeping": *true'; then
            SERVER_STATE="idle"
        else
            probe_model ""
        fi
        return 0
    fi

    # Router mode: only a loaded model can be handling a request
    if ! body=$(server_get /models); then
        SERVER_STATE="error"
        SERVER_DETAIL="GET /models failed"
        return 0
    fi
    models=$(list_router_models "$body")
    SERVER_STATE="idle"
    while read -r state id; do
        case "$state" in
        loading | downloading)
            SERVER_STATE="busy"
            SERVER_DETAIL="model $id is $state"
            return 0
            ;;
        loaded)
            probe_model "$id"
            if [ "$SERVER_STATE" != "idle" ]; then
                return 0
            fi
            ;;
        esac
    done <<<"$models"
}

# Function to wait until the server has been idle for IDLE_SECONDS
#
# Returns non-zero if the server stayed busy past IDLE_TIMEOUT or its
# activity could not be read three times in a row.
wait_until_idle() {
    local start=$SECONDS idle_since="" last_report="" errors=0 waited

    print_info "Waiting until llama-server at $WAIT_IDLE_URL has been idle for ${IDLE_SECONDS}s"
    while true; do
        server_activity
        case "$SERVER_STATE" in
        down)
            print_warning "llama-server at $WAIT_IDLE_URL is not reachable, so there is nothing to interrupt"
            return 0
            ;;
        error)
            errors=$((errors + 1))
            if [ "$errors" -ge 3 ]; then
                print_error "Cannot tell whether llama-server is idle: $SERVER_DETAIL"
                return 1
            fi
            ;;
        busy)
            errors=0
            idle_since=""
            ;;
        idle)
            errors=0
            if [ -z "$idle_since" ]; then
                idle_since=$SECONDS
            fi
            if [ $((SECONDS - idle_since)) -ge "$IDLE_SECONDS" ]; then
                return 0
            fi
            ;;
        esac

        waited=$((SECONDS - start))
        if [ "$IDLE_TIMEOUT" -gt 0 ] && [ "$waited" -ge "$IDLE_TIMEOUT" ]; then
            print_warning "llama-server has not been idle for ${IDLE_SECONDS}s within --idle-timeout ${IDLE_TIMEOUT}s"
            return 1
        fi
        if [ "$SERVER_STATE" = "busy" ] &&
            { [ -z "$last_report" ] || [ $((SECONDS - last_report)) -ge 60 ]; }; then
            print_info "Still waiting after ${waited}s: ${SERVER_DETAIL:-llama-server is busy}"
            last_report=$SECONDS
        fi
        sleep "$POLL_INTERVAL"
    done
}

# Function to restart llama-server after an update, or after an earlier
# update whose restart is still pending
restart_server() {
    local marker="$INSTALL_TARGET/$RESTART_MARKER_NAME"

    if [ "$INSTALL_DONE" != "1" ]; then
        if [ ! -e "$marker" ]; then
            return 0
        fi
        print_info "The restart after an earlier update is still pending"
    fi

    if [ -n "$WAIT_IDLE_URL" ]; then
        # The wait can take hours, so free the space held by the download, the
        # build tree and the replaced files first (TEMP_DIR itself is still
        # needed for request configs). After main has returned nothing is
        # left to roll back.
        rm -rf "$STAGE_DIR" "$BACKUP_DIR" "${TEMP_DIR:?}"/*
        STAGE_DIR=""
        BACKUP_DIR=""
    fi

    if [ -n "$WAIT_IDLE_URL" ] && ! wait_until_idle; then
        print_warning "llama-server was not restarted; the next run with --restart-cmd will try again"
        exit 1
    fi

    print_info "Restarting llama-server: $RESTART_CMD"
    if ! sh -c "$RESTART_CMD"; then
        print_error "The restart command failed; the next run with --restart-cmd will try again"
        exit 1
    fi
    rm -f "$marker"
    print_info "llama-server restarted"
}

# Temporary directory removed by the EXIT trap. It is global because the trap
# runs after main has returned, when main's local variables no longer exist.
TEMP_DIR=""

# Function to clean up temporary files, rolling back an unfinished install
cleanup() {
    # A second Ctrl-C must not cut the rollback short
    trap '' INT TERM HUP

    local keep_backup=""
    if [ -n "$INSTALL_TARGET" ] && [ "$INSTALL_DONE" != "1" ]; then
        rollback_install || keep_backup=1
    fi
    if [ -n "$STAGE_DIR" ]; then
        rm -rf "$STAGE_DIR"
    fi
    if [ -n "$BACKUP_DIR" ] && [ -z "$keep_backup" ]; then
        rm -rf "$BACKUP_DIR"
    fi
    if [ -n "$LOCK_DIR" ]; then
        rm -rf "$LOCK_DIR"
    fi

    if [ -n "$TEMP_DIR" ] && [ -d "$TEMP_DIR" ]; then
        rm -rf "$TEMP_DIR"
        print_info "Cleaned up temporary files"
    fi
}

# Main function
main() {
    local target_dir="${1:-.}" # Use current directory if no parameter provided

    # Create the target directory if needed and convert it to an absolute path
    # (CDPATH is cleared so cd cannot print the directory into the result)
    mkdir -p "$target_dir"
    target_dir=$(CDPATH='' cd -- "$target_dir" && pwd)

    print_info "llama.cpp Updater Script"
    print_info "Target directory: $target_dir"

    select_downloader

    # Create the temporary directory and make sure it is removed on exit
    # (signals exit through the EXIT trap, so an interrupted update rolls back)
    TEMP_DIR=$(mktemp -d)
    trap cleanup EXIT
    trap 'exit 130' INT
    trap 'exit 143' TERM
    trap 'exit 129' HUP

    begin_install "$target_dir"

    # Check if build from source is requested
    if [ "$BUILD_FROM_SOURCE" = "1" ]; then
        build_from_source "$TEMP_DIR"
        return 0
    fi

    # Detect system and architecture
    local system_arch patterns
    system_arch=$(detect_system)
    if [ "$FORCE_VULKAN" = "1" ] && [[ $system_arch == *"vulkan"* ]]; then
        print_info "Forcing Vulkan build as requested"
    elif [[ $system_arch == *"vulkan"* ]]; then
        print_info "Vulkan support detected on system"
    fi
    print_info "Detected system: $system_arch"

    if ! patterns=$(asset_patterns "$system_arch"); then
        print_error "No pattern defined for system: $system_arch"
        exit 1
    fi

    # Get latest bleeding-edge release
    print_info "Fetching latest bleeding-edge release information..."
    local releases_data
    releases_data=$(get_releases) || true

    if [ -z "$releases_data" ]; then
        print_error "Failed to fetch llama.cpp releases"
        print_error "$API_FAILURE_HINT"
        exit 1
    fi

    # The b[NUM] tag doubles as the version
    local tags newest_tag assets
    tags=$(list_release_tags "$releases_data")
    newest_tag=$(echo "$tags" | head -n1)
    if [ -z "$newest_tag" ]; then
        print_error "No b[NUM] release found among the latest llama.cpp releases"
        exit 1
    fi
    assets=$(list_assets "$releases_data")

    # Each pattern is tried across all releases before the next one, so a
    # Vulkan system takes an older Vulkan build over the newest regular one
    local pattern selected=""
    while IFS= read -r pattern; do
        if selected=$(find_asset "$assets" "$tags" "$pattern"); then
            break
        fi
    done <<<"$patterns"

    if [ -z "$selected" ]; then
        if [ "$FORCE_VULKAN" = "1" ]; then
            print_error "No Vulkan asset for $system_arch in the latest releases"
            print_error "Run without --vulkan to install the regular build, or use --build-from-source"
        else
            print_error "No suitable binary found for $system_arch"
        fi
        print_error "Archives in the newest release ($newest_tag):"
        echo "$assets" | awk -v tag="$newest_tag" '$1 == tag { print $2 }' |
            sed 's#.*/##' | grep -E '\.(zip|tar\.gz)$' >&2 || true
        exit 1
    fi

    local version download_url digest asset_name
    read -r version download_url digest <<<"$selected"
    asset_name="${download_url##*/}"
    if [ "$version" != "$newest_tag" ]; then
        print_warning "Release $newest_tag has no matching asset (yet), using $version"
    fi
    if [[ $system_arch == *"vulkan"* ]] && [[ $asset_name != *"-vulkan-"* ]]; then
        print_warning "No Vulkan asset found in the latest releases, installing the regular build instead"
    fi
    print_info "Selected version: $version"

    if [ "$FORCE_INSTALL" != "1" ] && is_installed "$asset_name"; then
        print_info "Already up to date: $asset_name is installed (use --force to reinstall)"
        return 0
    fi

    print_info "Download URL: $download_url"

    local archive_file="$TEMP_DIR/llama-cpp.archive"
    local extract_dir="$TEMP_DIR/extract"

    # Download the file
    download_file "$download_url" "$archive_file"
    verify_checksum "$archive_file" "$digest"

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

    # Stage the payload, then swap it into the target directory in one step
    stage_binaries "$extract_dir"
    make_executable
    commit_install "$asset_name"

    print_info "Successfully updated llama.cpp to version $version"
    print_info "Binaries are available in: $target_dir"

    # List the installed files
    print_info "Installed files:"
    local filename file size
    for filename in "${INSTALLED_FILES[@]}"; do
        file="$target_dir/$filename"
        # Symlinks are skipped so each library is listed once, at its real size
        if [ -f "$file" ] && [ ! -L "$file" ]; then
            size=$(stat -c%s "$file" 2>/dev/null || stat -f%z "$file" 2>/dev/null || echo "unknown")
            echo "  $filename ($size bytes)"
        fi
    done
}

# Function to print the usage message
print_usage() {
    echo "llama.cpp Updater & Builder Script"
    echo ""
    echo "Usage: $0 [OPTIONS] [target_directory]"
    echo ""
    echo "Downloads and installs the latest llama.cpp binaries for your system."
    echo ""
    echo "Options:"
    echo "  --build-from-source    Build from source instead of downloading binaries"
    echo "  --force-regular        Force regular Ubuntu build (disable Vulkan auto-detection)"
    echo "  --vulkan              Force Vulkan build for Ubuntu (fails if none is available)"
    echo "  --force               Reinstall even if the latest release is already installed"
    echo "  -h, --help            Show this help message"
    echo ""
    echo "Restarting llama-server after an update:"
    echo "  --restart-cmd CMD     Run CMD (through sh -c) after a successful update"
    echo "  --wait-idle URL       Before restarting, wait until the llama-server at URL is idle"
    echo "  --idle-seconds N      Idle time --wait-idle requires (default: 300)"
    echo "  --idle-timeout N      Stop waiting after N seconds and skip the restart (default: 0, wait forever)"
    echo "                        A skipped or failed restart is retried by the next run with --restart-cmd"
    echo ""
    echo "Arguments:"
    echo "  target_directory  Directory to install binaries (default: current directory)"
    echo ""
    echo "Environment:"
    echo "  GITHUB_TOKEN      GitHub token for API requests (raises the rate limit; GH_TOKEN also works)"
    echo "  LLAMA_API_KEY     API key for --wait-idle, if llama-server was started with --api-key"
    echo ""
    echo "Examples:"
    echo "  $0                              # Download latest bleeding-edge release in current directory"
    echo "  $0 ./llama-bin                  # Download latest bleeding-edge release in ./llama-bin"
    echo "  $0 --build-from-source          # Build from source in current directory"
    echo "  $0 --build-from-source ./bin    # Build from source and install in ./bin"
    echo "  $0 --vulkan ./bin               # Force Vulkan build for Ubuntu"
    echo "  $0 --force-regular ./bin        # Force regular Ubuntu build (no Vulkan)"
    echo "  $0 --restart-cmd 'systemctl restart llama-server' \\"
    echo "     --wait-idle http://127.0.0.1:8080 --idle-seconds 1800 ./bin"
    echo "                                  # Update, then restart once idle for 30 minutes"
}

# Parse command line arguments
BUILD_FROM_SOURCE=""
FORCE_REGULAR=""
FORCE_VULKAN=""
FORCE_INSTALL=""
TARGET_DIR=""
RESTART_CMD=""
WAIT_IDLE_URL=""
IDLE_SECONDS=""
IDLE_TIMEOUT=""

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
    --force)
        FORCE_INSTALL="1"
        shift
        ;;
    --restart-cmd | --wait-idle | --idle-seconds | --idle-timeout)
        if [ $# -lt 2 ] || [ -z "$2" ]; then
            echo "Option $1 needs a value. Use --help for usage information." >&2
            exit 1
        fi
        case $1 in
        --restart-cmd) RESTART_CMD="$2" ;;
        --wait-idle) WAIT_IDLE_URL="${2%/}" ;;
        --idle-seconds) IDLE_SECONDS="$2" ;;
        --idle-timeout) IDLE_TIMEOUT="$2" ;;
        esac
        shift 2
        ;;
    -h | --help)
        print_usage
        exit 0
        ;;
    -*)
        echo "Unknown option: $1" >&2
        echo "Use --help for usage information." >&2
        exit 1
        ;;
    *)
        if [ -z "$TARGET_DIR" ]; then
            TARGET_DIR="$1"
        else
            echo "Multiple target directories specified. Use --help for usage information." >&2
            exit 1
        fi
        shift
        ;;
    esac
done

# Handle conflicting options
if [ "$FORCE_REGULAR" = "1" ] && [ "$FORCE_VULKAN" = "1" ]; then
    print_error "Cannot use both --force-regular and --vulkan options together"
    exit 1
fi

if [ -n "$WAIT_IDLE_URL" ] || [ -n "$IDLE_SECONDS" ] || [ -n "$IDLE_TIMEOUT" ]; then
    if [ -z "$RESTART_CMD" ]; then
        print_error "--wait-idle, --idle-seconds and --idle-timeout need --restart-cmd"
        exit 1
    fi
    if [ -z "$WAIT_IDLE_URL" ]; then
        print_error "--idle-seconds and --idle-timeout need --wait-idle"
        exit 1
    fi
fi
if [ -n "$WAIT_IDLE_URL" ] && [[ ! $WAIT_IDLE_URL =~ ^https?:// ]]; then
    print_error "--wait-idle needs an http:// or https:// URL, e.g. http://127.0.0.1:8080"
    exit 1
fi
for value in "${IDLE_SECONDS:-300}" "${IDLE_TIMEOUT:-0}"; do
    # At most 9 digits, so the arithmetic below cannot overflow
    if [[ ! $value =~ ^0*[0-9]{1,9}$ ]]; then
        print_error "--idle-seconds and --idle-timeout need a whole number of seconds (at most 999999999), got: $value"
        exit 1
    fi
done
# 10# keeps a leading zero from being read as octal
IDLE_SECONDS=$((10#${IDLE_SECONDS:-300}))
IDLE_TIMEOUT=$((10#${IDLE_TIMEOUT:-0}))
# Idle time is only counted from the first look, so a shorter timeout could
# never let a running server qualify
if [ "$IDLE_TIMEOUT" -gt 0 ] && [ "$IDLE_TIMEOUT" -lt "$IDLE_SECONDS" ]; then
    print_error "--idle-timeout ($IDLE_TIMEOUT) must not be shorter than --idle-seconds ($IDLE_SECONDS)"
    exit 1
fi

# Run main function
main "$TARGET_DIR"

if [ -n "$RESTART_CMD" ]; then
    restart_server
fi
