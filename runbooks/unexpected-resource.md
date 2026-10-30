# RB-006. Неожиданный ресурс или внешний endpoint

**Триггер:** `SEC | Unexpected network or compute resource change` (D-07), результат `scripts/drift-check.sh`, расхождение с `docs/asset-registry.md`. **Severity:** ERROR.

## 1. Triage

1. Кто создал (`principalEmail`), когда, что именно (`request`: источники, порты, сеть).
2. Есть ли ресурс в коде и в реестре? `terraform plan` **не покажет** ресурс, которого нет в конфигурации.
3. Инвентаризация:
```bash
gcloud asset search-all-resources --scope="projects/${PROJECT_ID}" \
  --asset-types='compute.googleapis.com/Firewall,compute.googleapis.com/Instance,compute.googleapis.com/Address,storage.googleapis.com/Bucket' \
  --format='table(assetType.basename(), displayName, createTime)'
gcloud compute firewall-rules list --format='table(name,network,direction,priority,sourceRanges.list(),allowed[].map().firewall_rule().list())'
```
4. Экспозиция: есть ли VM/внешние IP в этой сети (`gcloud compute instances list`, `gcloud compute addresses list`), открыты ли порты на `0.0.0.0/0`.

## 2. Containment

Отключить или удалить правило/ресурс (`gcloud compute firewall-rules update NAME --disabled` или `delete`), если он не нужен. Сначала сохрани описание ресурса в `evidence/raw/`.

## 3. Remediation

Закрепить причину: запрет на создание ресурсов вне Terraform (роли, Organization Policy), алерт D-07 уже действует. Любой нужный ресурс — через код и ревью.

## 4. Проверка после исправления

`scripts/drift-check.sh`, `scripts/verify.sh`, подтвердить отсутствие правила/ресурса в инвентаризации.
