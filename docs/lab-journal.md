# Журнал выполнения: как я это сделал

Заполняй по ходу работы: что сделал, команды, результат, проблемы и решения. Перед публикацией замени project ID, email и IP.

## Итог в двух словах

Развёрнута и проверена инфраструктура безопасности GCP (VPC, Cloud Storage, IAM, аудит и детекты), проведены шесть расследований, оформлены runbooks, матрица ISO 27001 и финальный отчёт. Бюджет 10 USD, расход на момент снимка $0.00 (`evidence/screenshots/10-budget.png`).

## Хронология

| Шаг | Что сделано | Проблемы и решения |
| --- | --- | --- |
| 1. Инструменты и вход | `gcloud`, `terraform`, `git`; `gcloud auth login`, ADC | ADC: «cloud-platform scope is required but not consented» — повторил вход и отметил все разрешения |
| 2. Проект и billing | Проект `sec-lab-…`, billing, регион `europe-central2` | Без проблем |
| 3. Бюджет до развёртывания | Бюджет 10 USD, пороги 50/90/100% (только уведомления) | Скриншот `10-budget.png` |
| 4. Terraform apply | `init/validate/plan/apply` | Три ошибки первого apply (мои баги в коде): custom role требует включённого IAM API → `depends_on`; аудит `iamcredentials` не настраивается отдельно → убрал, аудит через `iam.googleapis.com`; алерты метрик без `resource.type` → перешёл на log-based алерты |
| 5. `verify.sh` | Первый прогон FAIL=3 | default VPC создана автоматически Compute API → удалил; impersonation не работал → `tester_members` (TokenCreator); `verify.sh` ужесточён |
| 6. Смена компьютера | Новый ноутбук, локальный state не перенесён | Восстановление: `scripts/import-existing.sh`; log bucket требовал `ignore_changes = [project]` (иначе замена); объекты не импортируются |
| 7. Роли | Три SA-носителя ролей, проверка `testIamPermissions` в `verify.sh` | Разделение ролей по условию задания требовало отдельных identity; с одним аккаунтом это реализовано service accounts |
| 8. Расследования | IR-01…IR-06 | См. `incidents/` |
| 9. Находки | См. `reports/final-report.md`, раздел 11 | |
| 10. Очистка | `terraform destroy`, проверка Asset Inventory | `force_destroy` у bucket, retention не locked |

## Находки в процессе (самое ценное)

- Default VPC с открытыми SSH/RDP появляется при включении Compute API (F-09).
- Default compute SA получает Editor автоматически (F-10).
- Унаследованные legacy-роли на bucket (F-02).
- Аддитивный IAM не показывает ручные привязки в `terraform plan` (F-01).
- Terraform не видит ресурсы вне кода (IR-06) → добавил детект D-07.
- Первоначально IR-05 в моих шаблонах предполагал создание ключа SA; задание запрещает создавать ключи ради упражнения, сценарий заменён на избыточную роль SA.

## Что бы я сделал иначе

- Сразу вынес бы Terraform state в удалённый backend: потеря локального state при смене компьютера стоила нескольких часов.
- Удалил бы default VPC и Editor у default compute SA сразу после включения Compute API.
- Заранее добавил бы алерты на изменения сети и на успешное чтение CONFIDENTIAL.
- Сделал бы снимки IAM-политик до каждого изменения для сравнения до/после.
