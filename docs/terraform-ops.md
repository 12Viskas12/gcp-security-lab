# Terraform: проверки, state, дрейф, удаление

## Версии и проверки

Версии зафиксированы в `terraform/versions.tf` (Terraform и провайдер `hashicorp/google ~> 6.0`, lock-файл `.terraform.lock.hcl` коммитится).

```bash
cd terraform
terraform fmt -check -recursive      | tee ../evidence/sanitized-logs/terraform-fmt.txt
terraform init
terraform validate                   | tee ../evidence/sanitized-logs/terraform-validate.txt
terraform plan -out=tfplan           | bash ../scripts/sanitize.sh > ../evidence/sanitized-logs/terraform-plan.txt
```

CI (`.github/workflows/ci.yml`) повторяет `fmt -check`, `init -backend=false`, `validate` и сканирование секретов.

## Повторный запуск (идемпотентность)

После `terraform apply` повторный `terraform plan` должен показать **«No changes»** (`-detailed-exitcode` = 0). Это доказывает воспроизводимость. Вывод сохрани в `evidence/sanitized-logs/terraform-plan-no-changes.txt`.

## Обнаружение дрейфа

| Тип дрейфа | Как обнаружить | Ограничение |
| --- | --- | --- |
| Изменение управляемого ресурса (audit config, labels) | `terraform plan -detailed-exitcode` (exit 2) | Подтверждено в IR-04 |
| Лишняя ручная IAM-привязка | Ревью `get-iam-policy`, Policy Analyzer | **Не видна** `terraform plan` (аддитивные ресурсы; IR-01) |
| Ресурс вне кода (firewall, VM) | Cloud Asset Inventory, алерт D-07, `scripts/drift-check.sh` | **Не виден** `terraform plan` (IR-06) |

Порядок: `bash scripts/drift-check.sh` → при дрейфе разобрать → `terraform apply` возвращает управляемые ресурсы к коду; лишние неуправляемые ресурсы удаляются вручную или импортируются в код через PR.

## Безопасное хранение state

В лабе state лежит **локально** (`terraform/terraform.tfstate`) и исключён через `.gitignore` и `pre-push-check.sh`. State содержит чувствительные данные (идентификаторы, иногда секреты), поэтому:

- не коммитить и не пересылать в открытом виде;
- для работы вдвоём/на нескольких машинах и для production использовать удалённый backend (`terraform/backend.tf.example`: GCS bucket с versioning, UBLA, PAP, права только исполнителям Terraform и блокировка state).

**Реальный случай:** при смене компьютера потерялся локальный state, и его пришлось восстанавливать импортом (`import-existing.sh`). Выводы: нужен remote backend; `google_storage_bucket_object` не импортируется (пересоздаётся); после импорта проверять `plan` на `must be replaced` (log bucket потребовал `ignore_changes = [project]`). Находка F-05.

## Порядок удаления инфраструктуры

```bash
cd terraform
terraform destroy              # force_destroy=true у bucket очищает объекты; retention, если задан и не истёк, блокирует удаление объектов
```

Если destroy падает из-за retention: дождись срока или выставь `bucket_retention_seconds = 0` и повтори. Log bucket `security-audit` удаляется со своими логами; имя после удаления резервируется на время. Затем:

1. Проверь консоль: Storage, Compute (сети, firewall), IAM (SA), Logging, Monitoring.
2. `gcloud asset search-all-resources --scope=projects/$PROJECT_ID` — ничего лишнего.
3. Проверь расходы: Billing → Reports за период работ; зафиксируй сумму в отчёте.
4. При необходимости удали проект: `gcloud projects delete $PROJECT_ID` (30 дней восстановления), отзови бюджет.
5. Убедись, что публичного доступа не осталось.
