#!/usr/bin/env bash
# Проверка перед публикацией на GitHub. Запускать из корня репозитория.
set -uo pipefail

fail=0
bad() { echo "[FAIL] $1"; fail=1; }
ok()  { echo "[ OK ] $1"; }

# Список файлов, которые попадут в репозиторий (tracked + untracked, не игнорируемые)
if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  files=$(git ls-files --cached --others --exclude-standard)
else
  files=$(find . -type f -not -path './.git/*' -not -path '*/.terraform/*')
fi

# 1. Запрещённые файлы
if echo "$files" | grep -E '(\.tfstate|\.tfvars$|\.pem$|\.key$|\.p12$|credentials)' | grep -v 'terraform.tfvars.example' | grep -q .; then
  bad "Найдены запрещённые файлы:"
  echo "$files" | grep -E '(\.tfstate|\.tfvars$|\.pem$|\.key$|\.p12$|credentials)' | grep -v 'terraform.tfvars.example'
else
  ok "Нет tfstate/tfvars/ключей/credentials"
fi

# 2. JSON-файлы (возможные ключи service accounts)
if echo "$files" | grep -E '\.json$' | grep -q .; then
  bad "Найдены .json файлы (возможны ключи service accounts):"
  echo "$files" | grep -E '\.json$'
else
  ok "Нет .json файлов"
fi

# 3. Паттерны секретов в содержимом
patterns='-----BEGIN (RSA |EC |OPENSSH |)PRIVATE KEY-----|"private_key"|AIza[0-9A-Za-z_-]{35}|ya29\.[0-9A-Za-z_-]{20,}|ghp_[0-9A-Za-z]{36}|github_pat_[0-9A-Za-z_]{20,}|AKIA[0-9A-Z]{16}|client_secret'
hits=""
while IFS= read -r f; do
  [[ -f "$f" ]] || continue
  [[ "$f" == "scripts/pre-push-check.sh" ]] && continue
  if grep -I -n -E "$patterns" "$f" >/dev/null 2>&1; then
    hits+="$f"$'\n'
  fi
done <<< "$files"
if [[ -n "$hits" ]]; then
  bad "Похоже на секреты в файлах:"
  echo "$hits"
else
  ok "Паттерны секретов не найдены"
fi

# 4. Реальные project ID / email в доках (напоминание)
echo "[INFO] Вручную проверь evidence/ и incidents/: замени реальные email, project ID и IP на REDACTED, если репозиторий будет публичным."

if [[ $fail -ne 0 ]]; then
  echo "Проверка НЕ пройдена."
  exit 1
fi
echo "Проверка пройдена."
