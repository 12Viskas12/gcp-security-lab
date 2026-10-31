# IAM review и hardening

## Принципы

- Owner/Editor не используются для повседневных операций; у лаборанта Owner только как владельца проекта.
- Права на **данные** выдаются на уровне **bucket**; на проект — только просмотр/настройка наблюдаемости.
- Три роли реализованы отдельными service accounts без ключей: `lab-security-admin`, `lab-operator`, `lab-auditor`. Дополнительно к ним в tfvars можно добавить людей/группы.
- Лаборант действует от их имени через impersonation (`roles/iam.serviceAccountTokenCreator`, переменная `tester_members`); это компромисс тестового стенда (см. ниже).

## Матрица доступа

| Principal | Ресурс | Действие (роли) | Обоснование | Срок |
| --- | --- | --- | --- | --- |
| `lab-security-admin` | Проект | `iam.securityReviewer`, `logging.configWriter`, `logging.viewer`, `monitoring.alertPolicyEditor`, `monitoring.viewer` | Видеть IAM, управлять sink/аудитом, настраивать алерты | По необходимости (лаборатория) |
| `lab-security-admin` | Bucket | `storage.admin` | Управлять политиками bucket (IAM, retention, lifecycle) | По необходимости |
| `lab-operator` | Bucket | custom `labOperator`: `storage.buckets.get`, `storage.objects.get/list/create` | Просмотр и загрузка объектов; **без delete** и без IAM | Постоянно в рамках лабы |
| `lab-operator` | Проект | `monitoring.viewer` | Видеть метрики и алерты | Постоянно |
| `lab-operator` | `sa-app-reader` | `serviceAccountTokenCreator` | Проверять доступ через impersonation без ключей | Постоянно |
| `lab-auditor` | Проект | `iam.securityReviewer`, `logging.privateLogViewer`, `monitoring.viewer`, `compute.networkViewer` | Чтение логов (включая Data Access) и конфигурации | Постоянно |
| `sa-app-reader` | Bucket | `storage.objectViewer` | Эталон «приложение читает данные» | Постоянно |
| `sa-no-access` | — | Нет | Негативные тесты | — |
| Лаборант (owner проекта) | Проект | Owner (Legacy) | Владелец проекта; экстренные действия по процедуре | Постоянно (риск, см. F-04) |
| Лаборант | Тестовые SA | `serviceAccountTokenCreator` (`tester_members`) | Запуск `verify.sh` и симуляций | На время лабы |

## Почему именно эти разрешения

- **Security Admin** не получает `iam.securityAdmin`/`owner`: они позволяют выдать себе любую роль (эскалация). Изменение IAM идёт через Terraform/PR или экстренный доступ.
- **Operator** имеет `objects.create`, но не `delete`: перезапись сохраняется в версиях (versioning), удаление данных оператором невозможно.
- **Auditor** читает логи (`privateLogViewer` нужен для Data Access), но не имеет прав на содержимое объектов: аудитор не должен получать CONFIDENTIAL.

## Проверка service accounts и impersonation

```bash
SA="sa-app-reader@${PROJECT_ID}.iam.gserviceaccount.com"
gcloud iam service-accounts get-iam-policy "$SA"                      # кто может действовать от имени SA
gcloud projects get-iam-policy "$PROJECT_ID" --flatten='bindings[].members' \
  --filter='bindings.role:(roles/owner OR roles/editor OR roles/iam.serviceAccountTokenCreator OR roles/iam.serviceAccountUser OR roles/iam.serviceAccountKeyAdmin OR roles/iam.serviceAccountAdmin)' \
  --format='table(bindings.role, bindings.members)'
gcloud iam service-accounts keys list --iam-account="$SA" --managed-by=user     # ожидается пусто
```

Разделение ролей проверяется автоматически `scripts/verify.sh` (раздел «Разделение ролей»): `testIamPermissions` от имени каждой SA ничего не изменяет.

## Сравнение IAM до и после hardening

| Что | До | После | Доказательство |
| --- | --- | --- | --- |
| Default VPC с открытыми SSH/RDP | Есть (auto-mode, 42 подсети) | Удалена, только `lab-vpc` | `evidence/screenshots/01…03` |
| Editor у default compute SA | Есть (автовыдача при включении Compute API) | Снята (IR-05) | `evidence/screenshots/11-iam-principals.png`, `evidence/sanitized-logs/iam-basic-roles-after.txt` |
| Избыточная SA `sa-overprivileged` (`storage.admin` на проект) | Создана в симуляции | Роль снята, SA удалена | IR-05 |
| Legacy-роли проектных групп на bucket (`storage.legacyBucketOwner/Reader`, `legacyObjectOwner`) | Унаследованы при создании | Открытая находка F-02 (процедура снятия: `docs/storage-security.md`) | `evidence/screenshots/05-bucket-permissions.jpg` |
| Разделение ролей | Нет отдельных носителей | Три SA, `verify.sh` PASS | `evidence/sanitized-logs/verify-*.txt` |

Снимки политик «до/после» сохраняй командами:

```bash
gcloud projects get-iam-policy "$PROJECT_ID" --format=json > evidence/raw/iam-project-before.json    # до изменения
# ... исправление ...
gcloud projects get-iam-policy "$PROJECT_ID" --format=json > evidence/raw/iam-project-after.json
diff <(jq -S . evidence/raw/iam-project-before.json) <(jq -S . evidence/raw/iam-project-after.json) | bash scripts/sanitize.sh > evidence/sanitized-logs/iam-project-diff.txt
```

## Известный компромисс: аддитивные привязки и дрейф

`*_iam_member` управляет только своими привязками, поэтому `terraform plan` не видит лишних ручных (подтверждено в IR-01). Компенсация: алерт D-01, периодический аудит политики, Policy Analyzer. Усиление: `*_iam_binding`/`*_iam_policy`.

## Тестовый стенд (`tester_members`)

Лаборант получает `serviceAccountTokenCreator` на все тестовые SA и носители ролей: Owner сам по себе токены SA выпускать не может. В production так нельзя без контроля, потому что через эту роль можно действовать от имени любой роли. Здесь это компромисс стенда.

## Экстренный доступ

[runbooks/emergency-access.md](../runbooks/emergency-access.md): временная привязка с условием по времени, запись в инцидент, пост-аудит.

## Повторная проверка после исправлений

`bash scripts/verify.sh` (ожидается `FAIL=0`) и `bash scripts/drift-check.sh`.

<!-- screenshots:Скриншоты -->
## Скриншоты

![IAM: итоговые principals проекта](../evidence/screenshots/11-iam-principals.png)

*IAM: итоговые principals проекта*
