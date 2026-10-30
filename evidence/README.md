# Evidence

| Путь | Что |
| --- | --- |
| `architecture.png`, `data-flow.png` | Схема архитектуры и диаграмма потоков данных (из `docs/architecture.md`) |
| `screenshots/` | Скриншоты консоли и писем алертов, нумерованы; таблица «что доказывает» ниже или в `screenshots/README.md` |
| `sanitized-logs/` | Очищенные выдержки логов и выводов команд (`scripts/sanitize.sh`) |
| `raw/` | Сырые выгрузки, **не коммитятся** (`.gitignore`) |

Правила:

1. Сырые данные только в `evidence/raw/`.
2. В публикуемые файлы попадает только вывод `scripts/sanitize.sh`, после просмотра глазами.
3. На скриншотах закрой email, project ID, billing account и сторонние проекты.
4. Никаких ключей, токенов и содержимого `terraform.tfstate`.

Ожидаемые файлы в `sanitized-logs/`: `verify-output.txt`, `terraform-fmt.txt`, `terraform-validate.txt`, `terraform-plan*.txt`, `versioning-test.txt`, `iam-basic-roles-after.txt`, `log-bucket-retention.txt`, `ir-0X-*.txt`.
