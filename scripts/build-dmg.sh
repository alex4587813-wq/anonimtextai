#!/bin/zsh

set -euo pipefail

project_dir=${0:A:h:h}
app_name="Локальный анонимизатор"
app_dir="$project_dir/dist/$app_name.app"
version=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$project_dir/Resources/Info.plist")
dmg_path="$project_dir/dist/$app_name-$version-macOS.dmg"
checksum_path="$dmg_path.sha256"
staging_dir=$(mktemp -d "${TMPDIR%/}/local-anonymizer-dmg.XXXXXX")

cleanup() {
    if [[ -n "$staging_dir" && "$staging_dir" == *"/local-anonymizer-dmg."* && -d "$staging_dir" ]]; then
        rm -rf "$staging_dir"
    fi
}
trap cleanup EXIT

echo "[dmg] Сборка приложения"
"$project_dir/scripts/build-app.sh"

echo "[dmg] Подготовка содержимого образа"
ditto "$app_dir" "$staging_dir/$app_name.app"
ln -s /Applications "$staging_dir/Applications"
cp "$project_dir/Resources/Установка macOS.txt" "$staging_dir/Установка.txt"

echo "[dmg] Создание установочного образа"
hdiutil create \
    -volname "$app_name" \
    -srcfolder "$staging_dir" \
    -ov \
    -format UDZO \
    "$dmg_path"

echo "[dmg] Проверка образа"
hdiutil verify "$dmg_path"
(
    cd "$project_dir/dist"
    shasum -a 256 "${dmg_path:t}" > "${checksum_path:t}"
)

echo "[dmg] Готово: $dmg_path"
echo "[dmg] Контрольная сумма: $checksum_path"
