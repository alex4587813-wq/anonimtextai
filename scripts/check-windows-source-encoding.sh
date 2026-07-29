#!/bin/zsh

set -euo pipefail

project_dir=${0:A:h:h}
source_dir="$project_dir/Windows/LocalAnonymizer"
encoding_check_exit_code=0

for script_file in "$source_dir"/*.ps1 "$source_dir"/*.psm1; do
    signature=$(xxd -p -l 3 "$script_file")
    if [[ "$signature" != "efbbbf" ]]; then
        echo "[windows] ERROR: требуется UTF-8 BOM: ${script_file:t}"
        encoding_check_exit_code=1
    fi
done

if [[ "$encoding_check_exit_code" -ne 0 ]]; then
    exit "$encoding_check_exit_code"
fi

echo "[windows] Кодировка PowerShell-файлов: UTF-8 BOM"
