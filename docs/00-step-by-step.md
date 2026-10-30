# Пошаговое выполнение лабы

Все команды выполняются в твоём терминале. Работай только в своём тестовом проекте.

## Шаг 1. Установка инструментов

- Google Cloud CLI: https://cloud.google.com/sdk/docs/install
- Terraform: https://developer.hashicorp.com/terraform/install
- Git: https://git-scm.com/downloads
- Редактор кода (например, VS Code)

Проверка:

```bash
gcloud version
terraform version
git --version
```

## Шаг 2. Авторизация

```bash
gcloud auth login
gcloud auth application-default login   # учётные данные для Terraform
gcloud projects list
```

## Шаг 3. Отдельный проект и billing

```bash
export PROJECT_ID="sec-lab-$(date +%y%m%d)-xyz"     # ID глобально уникален, замени xyz
gcloud projects create "$PROJECT_ID" --name="Security Lab"

gcloud billing accounts list
gcloud billing projects link "$PROJECT_ID" --billing-account=XXXXXX-XXXXXX-XXXXXX

gcloud config set project "$PROJECT_ID"
gcloud services enable serviceusage.googleapis.com cloudresourcemanager.googleapis.com \
  cloudbilling.googleapis.com billingbudgets.googleapis.com
```

Выбери регион (в `terraform.tfvars`, по умолчанию `europe-central2`). Проверь, что сервисы доступны в регионе и сверь цены на странице Google Cloud Pricing.

## Шаг 4. Бюджет и уведомления (ДО развёртывания)

```bash
gcloud billing budgets create \
  --billing-account=XXXXXX-XXXXXX-XXXXXX \
  --display-name="sec-lab-budget" \
  --budget-amount=10USD \
  --filter-projects="projects/$PROJECT_ID" \
  --threshold-rule=percent=0.5 \
  --threshold-rule=percent=0.9 \
  --threshold-rule=percent=1.0
```

Если команда ругается на `--filter-projects`, укажи номер проекта (`gcloud projects describe "$PROJECT_ID" --format='value(projectNumber)'`) или создай бюджет в консоли (Billing → Budgets & alerts).

> Бюджет только уведомляет и **не останавливает расходы**. После работы выполни `terraform destroy` (шаг 11).

Сделай скриншот бюджета в `evidence/`.

## Шаг 5. Настрой переменные

```bash
cd terraform
cp terraform.tfvars.example terraform.tfvars
# отредактируй: project_id, alert_email, участники ролей
```

Для реального разделения обязанностей используй разные аккаунты (или Google Groups): Security Admin, Operator, Auditor. Если аккаунт один, оставь списки пустыми и добавь роли позже.

## Шаг 6. Развёртывание

```bash
terraform init
terraform fmt -recursive
terraform validate
terraform plan -out=tfplan
terraform apply tfplan
```

Прочитай `plan` до `apply`: проверь, что нет внешних IP, публичных привязок и `allUsers`.

Типичные проблемы:

- `API not enabled`: подожди 1-2 минуты после включения API и повтори `apply`.
- Ошибка с `billing_project`: убедись, что выполнены `gcloud services enable` из шага 3.
- Ошибка по Log Analytics или локации log bucket: смени `log_bucket_location` на `global`.
- Ошибка версии провайдера: проверь актуальную версию на registry.terraform.io и поправь `versions.tf`.

## Шаг 7. Проверка конфигурации

```bash
cd ..
export PROJECT_ID="твой-project-id"
bash scripts/verify.sh | tee evidence/verify-output.txt
```

Скрипт проверяет (в том числе разделение трёх ролей через `testIamPermissions`): UBLA, Public Access Prevention, анонимный доступ (ожидается 401/403), права `sa-app-reader` и `sa-no-access`, отсутствие default VPC, внешних IP и пользовательских ключей service accounts, наличие audit config.
Все проверки должны быть `PASS`. Любой `FAIL` разбери и отрази в отчёте.

Проверь вручную в консоли и сделай скриншоты: Logs Explorer (Admin Activity), Monitoring → Alerting, Cloud Storage → bucket → Permissions.

## Шаг 7б. Проверки Terraform и версионирования

```bash
cd terraform && terraform fmt -check -recursive && terraform validate && terraform plan -detailed-exitcode   # exit 0 = нет изменений
cd .. && bash scripts/test-versioning.sh
bash scripts/drift-check.sh
```

Вывод сохрани в `evidence/sanitized-logs/` (см. [terraform-ops.md](terraform-ops.md), [storage-security.md](storage-security.md)).

## Шаг 8. Симуляция инцидентов

По очереди выполни [IR-01 … IR-06](../incidents/). В каждом: симуляция, ожидание письма алерта (обычно 1–3 минуты), расследование по логам, возврат в исходное состояние.
Между симуляциями с одинаковым алертом выдерживай паузу не меньше 5 минут: лимит уведомлений объединяет события в одно письмо.
Правила:

- Только test-identity (`sa-no-access`, `sa-app-reader`) и свой bucket.
- **Не отключай аудит всего проекта.**
- Ключи service accounts не сохраняй в репозитории.

## Шаг 9. Доказательства

Скриншоты — в `evidence/screenshots/`, очищенные выдержки логов — в `evidence/sanitized-logs/` (очистка: `bash scripts/sanitize.sh`). Сырые выгрузки хранятся в `evidence/raw/` (в `.gitignore`).

## Шаг 10. Отчёты и матрица

Сверь `incidents/*.md`, `compliance/iso27001-control-matrix.csv`, `docs/*.md` и `reports/final-report.md` с реальными результатами твоего запуска.

## Шаг 11. Очистка

```bash
cd terraform
terraform destroy
```

Если destroy падает на объектах из-за retention policy, дождись окончания срока (по умолчанию 24 ч) или выставь `bucket_retention_seconds = 0` и повтори. Затем проверь в консоли, что ничего не осталось, и при необходимости удали проект: `gcloud projects delete "$PROJECT_ID"`.

## Шаг 12. Публикация на GitHub

См. [github-publish.md](github-publish.md).
