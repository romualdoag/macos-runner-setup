#!/bin/bash -e -o pipefail

download_with_retry() {
    url=$1
    download_path=$2

    if [ -z "$download_path" ]; then
        download_path="/tmp/$(basename "$url")"
    fi

    echo "Downloading package from $url to $download_path..." >&2

    interval=30
    download_start_time=$(date +%s)

    for ((retries=20; retries>0; retries--)); do
        attempt_start_time=$(date +%s)
        if http_code=$(curl -4sSLo "$download_path" "$url" -w '%{http_code}'); then
            attempt_seconds=$(($(date +%s) - attempt_start_time))
            if [ "$http_code" -eq 200 ]; then
                echo "Package downloaded in $attempt_seconds seconds" >&2
                break
            else
                echo "Received HTTP status code $http_code after $attempt_seconds seconds" >&2
            fi
        else
            attempt_seconds=$(($(date +%s) - attempt_start_time))
            echo "Package download failed in $attempt_seconds seconds" >&2
        fi

        if [ $retries -eq 0 ]; then
            total_seconds=$(($(date +%s) - download_start_time))
            echo "Package download failed after $total_seconds seconds" >&2
            exit 1
        fi

        echo "Waiting $interval seconds before retrying (retries left: $retries)..." >&2
        sleep $interval
    done

    echo "$download_path"
}

is_Arm64() {
    [ "$(arch)" = "arm64" ]
}

is_Sequoia() {
    [ "$OSTYPE" = "darwin24" ]
}

is_SequoiaArm64() {
    is_Sequoia && is_Arm64
}

is_SequoiaX64() {
    is_Sequoia && ! is_Arm64
}

is_Sonoma() {
    [ "$OSTYPE" = "darwin23" ]
}

is_SonomaArm64() {
    is_Sonoma && is_Arm64
}

is_SonomaX64() {
    is_Sonoma && ! is_Arm64
}

is_Ventura() {
    [ "$OSTYPE" = "darwin22" ]
}

is_VenturaArm64() {
    is_Ventura && is_Arm64
}

is_VenturaX64() {
    is_Ventura && ! is_Arm64
}

is_Monterey() {
    [ "$OSTYPE" = "darwin21" ]
}

configure_system_tccdb () {
    local values=$1
    local dbPath="/Library/Application Support/com.apple.TCC/TCC.db"
    local sqlQuery="INSERT OR IGNORE INTO access VALUES($values);"
    sudo sqlite3 "$dbPath" "$sqlQuery"
}

configure_user_tccdb () {
    local values=$1
    local dbPath="$HOME/Library/Application Support/com.apple.TCC/TCC.db"
    local sqlQuery="INSERT OR IGNORE INTO access VALUES($values);"
    sqlite3 "$dbPath" "$sqlQuery"
}

# Close all finder windows because they can interfere with UI tests
close_finder_window() {
    osascript -e 'tell application "Finder" to close windows'
}

get_arch() {
    arch=$(arch)
    if [[ $arch == "arm64" ]]; then
        echo "arm64"
    else
        echo "x64"
    fi
}

use_checksum_comparison() {
    local file_path=$1
    local checksum=$2
    local sha_type=${3:-"256"}

    echo "Performing checksum verification"

    if [[ ! -f "$file_path" ]]; then
        echo "File not found: $file_path"
        exit 1
    fi

    local_file_hash=$(shasum --algorithm "$sha_type" "$file_path" | awk '{print $1}')

    if [[ "$local_file_hash" != "$checksum" ]]; then
        echo "Checksum verification failed. Expected hash: $checksum; Actual hash: $local_file_hash."
        exit 1
    else
        echo "Checksum verification passed"
    fi
}

# brew provides package bottles for different macOS versions
# The 'brew install' command will fail if a package bottle does not exist
# Use the '--build-from-source' option to build from source in this case
brew_smart_install() {
    local tool_name=$1

    echo "Downloading $tool_name..."

    # get deps & cache em

    failed=true
    for i in {1..10}; do
        brew deps $tool_name > /tmp/$tool_name && failed=false || sleep 60
        [ "$failed" = false ] && break
    done

    if [ "$failed" = true ]; then
       echo "Failed: brew deps $tool_name"
       exit 1;
    fi

    for dep in $(cat /tmp/$tool_name) $tool_name; do

    failed=true
    for i in {1..10}; do
        brew --cache $dep >/dev/null && failed=false || sleep 60
        [ "$failed" = false ] && break
    done

    if [ "$failed" = true ]; then
       echo "Failed: brew --cache $dep"
       exit 1;
    fi
    done

    failed=true
    for i in {1..10}; do
        brew install $tool_name && failed=false || sleep 60
        [ "$failed" = false ] && break
    done

    if [ "$failed" = true ]; then
       echo "Failed: brew install $tool_name"
       exit 1;
    fi
}