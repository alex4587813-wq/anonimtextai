#!/bin/zsh

set -euo pipefail

project_dir=${0:A:h:h}
source_dir="$project_dir/Windows/LocalAnonymizer"
version=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$project_dir/Resources/Info.plist")
package_name="LocalAnonymizer-Windows"
zip_path="$project_dir/dist/LocalAnonymizer-Windows-$version.zip"
checksum_path="$zip_path.sha256"
staging_dir=$(mktemp -d "${TMPDIR%/}/local-anonymizer-windows.XXXXXX")
package_dir="$staging_dir/$package_name"

cleanup() {
    if [[ -n "$staging_dir" && "$staging_dir" == *"/local-anonymizer-windows."* && -d "$staging_dir" ]]; then
        rm -rf "$staging_dir"
    fi
}
trap cleanup EXIT

echo "[windows] Подготовка файлов"
mkdir -p "$package_dir"
ditto "$source_dir" "$package_dir"
cp "$project_dir/Resources/AppIcon.ico" "$package_dir/AppIcon.ico"

# Windows PowerShell 5.1 корректно читает UTF-8-скрипты с BOM.
for script_file in "$package_dir"/*.ps1 "$package_dir"/*.psm1; do
    perl -0777 -i -pe '
        $_ = "\xEF\xBB\xBF" . $_
            unless substr($_, 0, 3) eq "\xEF\xBB\xBF"
    ' "$script_file"
done

echo "[windows] Проверка XAML"
xmllint --noout "$package_dir/MainWindow.xaml"

echo "[windows] Создание ZIP"
rm -f "$zip_path"
(
    cd "$staging_dir"
    /usr/bin/zip -r -X -q "$zip_path" "$package_name"
)

echo "[windows] Проверка ZIP"
/usr/bin/unzip -t "$zip_path"
(
    cd "$project_dir/dist"
    shasum -a 256 "${zip_path:t}" > "${checksum_path:t}"
)

echo "[windows] Готово: $zip_path"
echo "[windows] Контрольная сумма: $checksum_path"
