#!/usr/bin/env bash
# Проверка восстановления объекта после перезаписи (versioning). Работает на ОТДЕЛЬНОМ тестовом объекте.
# Использование: PROJECT_ID=... bash scripts/test-versioning.sh | tee evidence/sanitized-logs/versioning-test.txt
set -uo pipefail
: "${PROJECT_ID:?Задай PROJECT_ID}"
B="gs://${PROJECT_ID}-lab-data"
O="${B}/versioning-test/restore-me.txt"
W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT

echo "== 1. Версия 1 =="
echo "version-1 $(date -u +%FT%TZ)" > "$W/v1.txt"
gcloud storage cp "$W/v1.txt" "$O" --quiet
echo "== 2. Перезапись (версия 2) =="
echo "version-2 OVERWRITTEN $(date -u +%FT%TZ)" > "$W/v2.txt"
gcloud storage cp "$W/v2.txt" "$O" --quiet
echo "== 3. Список версий =="
gcloud storage ls -a --long "$O"
OLD_GEN=$(gcloud storage ls -a "$O" | grep '#' | head -1 | sed 's/.*#//')
echo "== 4. Восстановление первой версии (generation ${OLD_GEN}) =="
gcloud storage cp "${O}#${OLD_GEN}" "$O" --quiet
echo "== 5. Проверка содержимого =="
RESULT=$(gcloud storage cat "$O")
echo "$RESULT"
if echo "$RESULT" | grep -q '^version-1'; then echo "[PASS] версия 1 восстановлена"; else echo "[FAIL] восстановление не удалось"; fi
echo "== 6. Очистка (удаление всех версий тестового объекта) =="
gcloud storage rm -a "$O" --quiet
