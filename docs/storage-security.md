# Безопасность Cloud Storage

Bucket `PROJECT_ID-lab-data` (регион `europe-central2`), синтетические объекты `internal/…` (INTERNAL) и `confidential/…` (CONFIDENTIAL). Реализация: `terraform/storage.tf`.

## Конфигурация: по умолчанию и после hardening

«По умолчанию» — типичные значения нового bucket без дополнительных настроек (сверь с документацией Google Cloud на момент выполнения).

| Параметр | По умолчанию | После hardening | Проверка |
| --- | --- | --- | --- |
| Модель доступа | Fine-grained (ACL допускаются) | Uniform bucket-level access | `gcloud storage buckets describe … --format='value(uniform_bucket_level_access)'` |
| Публичный доступ | Не ограничен (можно выдать `allUsers`) | Public Access Prevention = enforced | `… value(public_access_prevention)`; попытка выдать `allUsers` → 412 (IR-02) |
| Версионирование | Выкл. | Вкл. | `… value(versioning_enabled)`; `scripts/test-versioning.sh` |
| Soft delete | 7 дней | 0 (выключен ради стоимости, восстановление через versioning) | консоль → Protection |
| Retention | Нет | Не задан (`Bucket retention policy: None`, `evidence/screenshots/07-bucket-config.jpg`); параметр `bucket_retention_seconds`, не locked | консоль → Protection |
| Lifecycle | Нет | 3 правила: удаление noncurrent через 30 дней, NEARLINE через 90 дней, прерванные multipart через 7 дней | консоль → Lifecycle |
| Шифрование | Google-managed | Google-managed (CMEK не используется; F-08) | консоль → Configuration |
| Метки | Нет | `data_classification`, `environment`, `managed_by`, `owner`, `project` | консоль → Configuration |

## Проверка анонимного доступа и доступа тестовых identity

```bash
curl -s -o /dev/null -w '%{http_code}\n' "https://storage.googleapis.com/${BUCKET}/internal/employee-directory-SYNTHETIC.csv"   # 401/403
bash scripts/verify.sh      # sa-app-reader читает, не пишет; sa-no-access не читает; Auditor не читает; Operator не удаляет
```

Результат: последний полный прогон `verify.sh` — PASS=31, FAIL=0 (анонимный доступ 403; `sa-app-reader` читает, но не пишет; `sa-no-access` не читает).

## Кто может удалять и изменять объекты

```bash
gcloud storage buckets get-iam-policy "gs://${BUCKET}" --format='table(bindings.role, bindings.members.flatten())'
```

| Кто | Право | Может удалять/менять объекты? |
| --- | --- | --- |
| Владелец проекта (Owner) | `storage.legacyBucketOwner` и basic-роль | Да |
| `lab-security-admin` | `storage.admin` | Да (и менять IAM bucket) |
| `lab-operator` | custom `labOperator` | Создавать — да; **удалять нет** (перезапись создаёт новую версию) |
| `lab-auditor`, `sa-no-access` | — | Нет |
| `sa-app-reader` | `objectViewer` | Нет |
| Legacy-группы проекта (`projectEditor`, `projectViewer`) | Унаследованы при создании bucket | **Editors могут менять объекты; Viewers читают CONFIDENTIAL** — находка F-02 |

### Находка F-02: унаследованные legacy-роли

При создании bucket GCP добавляет `projectOwner/Editor/Viewer` с Storage Legacy ролями. Это противоречит минимальным привилегиям: CONFIDENTIAL читают и меняют те, кому он не нужен.

Исправление (после завершения симуляций, чтобы не смешивать со следами IR-01…IR-06):

```bash
gcloud storage buckets get-iam-policy "gs://${BUCKET}" --format=json > evidence/raw/bucket-iam-before.json
# осторожно: убедись, что владелец проекта сохраняет доступ через basic-роль Owner
gcloud storage buckets remove-iam-policy-binding "gs://${BUCKET}" --member="projectViewer:${PROJECT_ID}" --role=roles/storage.legacyBucketReader
gcloud storage buckets remove-iam-policy-binding "gs://${BUCKET}" --member="projectViewer:${PROJECT_ID}" --role=roles/storage.legacyObjectReader
gcloud storage buckets remove-iam-policy-binding "gs://${BUCKET}" --member="projectEditor:${PROJECT_ID}" --role=roles/storage.legacyBucketOwner
gcloud storage buckets remove-iam-policy-binding "gs://${BUCKET}" --member="projectEditor:${PROJECT_ID}" --role=roles/storage.legacyObjectOwner
gcloud storage buckets get-iam-policy "gs://${BUCKET}" --format=json > evidence/raw/bucket-iam-after.json
```

Состав привязок сверь по `get-iam-policy`: удаляй только то, что там действительно есть. Перепроверь доступ через `verify.sh`.

## Оценка versioning, lifecycle и retention

- **Versioning:** нужен для восстановления после перезаписи/удаления. Это не полноценный backup (версии в том же bucket, регионе и проекте). Стоимость ограничена lifecycle (noncurrent удаляются через 30 дней).
- **Lifecycle:** NEARLINE через 90 дней экономит хранение при редком доступе; для лабы объём ничтожен, правило показывает подход.
- **Retention:** защищает от удаления/перезаписи на заданный срок. В лабе не locked (иначе `terraform destroy` невозможен); в production для критичных данных retention блокируют. В этом запуске retention не задан.
- **Soft delete:** выключен; без него восстановление удалённых объектов возможно только из версий.

## Проверка восстановления после перезаписи

```bash
bash scripts/test-versioning.sh | bash scripts/sanitize.sh > evidence/sanitized-logs/versioning-test.txt
```

Скрипт на отдельном объекте: создаёт версию 1, перезаписывает, показывает версии, восстанавливает версию 1 по generation, проверяет содержимое и удаляет тестовый объект.

## Ограничения

UBLA можно отключить в течение 90 дней после включения; PAP снимает любой с `storage.buckets.update`, поэтому детект D-02 обязателен. На уровне организации это закрепляют политики `storage.publicAccessPrevention` и `storage.uniformBucketLevelAccess`.

<!-- screenshots:Скриншоты -->
## Скриншоты

![Bucket: синтетические данные internal/ и confidential/](../evidence/screenshots/04-bucket-objects.jpg)

*Bucket: синтетические данные internal/ и confidential/*

![Bucket: права, Public Access Prevention, UBLA](../evidence/screenshots/05-bucket-permissions.jpg)

*Bucket: права, Public Access Prevention, UBLA*

![Bucket: versioning, soft delete, retention](../evidence/screenshots/06-bucket-protection.jpg)

*Bucket: versioning, soft delete, retention*

![Bucket: метки, шифрование, lifecycle](../evidence/screenshots/07-bucket-config.jpg)

*Bucket: метки, шифрование, lifecycle*
