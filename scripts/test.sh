#!/bin/zsh

set -euo pipefail

project_dir=${0:A:h:h}
cache_dir="$project_dir/.build/local-cache"
sdk_path="/Library/Developer/CommandLineTools/SDKs/MacOSX15.5.sdk"

if [[ ! -d "$sdk_path" ]]; then
    sdk_path=$(xcrun --sdk macosx --show-sdk-path)
fi

mkdir -p "$cache_dir/module-cache"
mkdir -p "$cache_dir/swiftpm-cache"
mkdir -p "$cache_dir/swiftpm-config"
mkdir -p "$cache_dir/swiftpm-security"

export SDKROOT="$sdk_path"
export CLANG_MODULE_CACHE_PATH="$cache_dir/module-cache"

cd "$project_dir"

swift run \
    --disable-sandbox \
    --cache-path "$cache_dir/swiftpm-cache" \
    --config-path "$cache_dir/swiftpm-config" \
    --security-path "$cache_dir/swiftpm-security" \
    -Xcc "-fmodules-cache-path=$cache_dir/module-cache" \
    LocalAnonymizerSelfTest
