#!/bin/zsh

set -euo pipefail

project_dir=${0:A:h:h}
version=$(
    /usr/libexec/PlistBuddy \
        -c "Print :CFBundleShortVersionString" \
        "$project_dir/Resources/Info.plist"
)
source_dir="$project_dir/dist"
distribution_dir="$project_dir/Дистрибутивы"
macos_dir="$distribution_dir/macOS"
windows_dir="$distribution_dir/Windows"
macos_source="$source_dir/Локальный анонимизатор-$version-macOS.dmg"
windows_source="$source_dir/LocalAnonymizer-Windows-$version.zip"
macos_name="LocalAnonymizer-macOS-$version.dmg"
windows_name="LocalAnonymizer-Windows-$version.zip"

if [[ ! -f "$macos_source" ]]; then
    echo "[distributions] Не найден DMG: $macos_source" >&2
    exit 1
fi

if [[ ! -f "$windows_source" ]]; then
    echo "[distributions] Не найден ZIP: $windows_source" >&2
    exit 1
fi

mkdir -p "$macos_dir"
mkdir -p "$windows_dir"

echo "[distributions] Копирование macOS $version"
cp "$macos_source" "$macos_dir/$macos_name"
(
    cd "$macos_dir"
    shasum -a 256 "$macos_name" > "$macos_name.sha256"
)

echo "[distributions] Копирование Windows $version"
cp "$windows_source" "$windows_dir/$windows_name"
(
    cd "$windows_dir"
    shasum -a 256 "$windows_name" > "$windows_name.sha256"
)

echo "[distributions] Готово: $distribution_dir"
