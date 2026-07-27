#!/bin/zsh

set -euo pipefail

project_dir=${0:A:h:h}
app_dir="$project_dir/dist/Локальный анонимизатор.app"
contents_dir="$app_dir/Contents"
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

echo "[build] Сборка release-версии"
swift build -c release \
    --disable-sandbox \
    --cache-path "$cache_dir/swiftpm-cache" \
    --config-path "$cache_dir/swiftpm-config" \
    --security-path "$cache_dir/swiftpm-security" \
    -Xcc "-fmodules-cache-path=$cache_dir/module-cache"

echo "[build] Формирование app bundle"
mkdir -p "$contents_dir/MacOS"
mkdir -p "$contents_dir/Resources"
cp "$project_dir/.build/release/LocalAnonymizer" "$contents_dir/MacOS/LocalAnonymizer"
cp "$project_dir/Resources/Info.plist" "$contents_dir/Info.plist"
cp "$project_dir/Resources/AppIcon.icns" "$contents_dir/Resources/AppIcon.icns"

echo "[build] Локальная ad-hoc подпись"
codesign --force --deep --sign - "$app_dir"

# Обновляем дату самого bundle, чтобы Finder перечитал Info.plist и иконку
# после повторной сборки приложения по тому же пути.
touch "$app_dir"

echo "[build] Готово: $app_dir"
