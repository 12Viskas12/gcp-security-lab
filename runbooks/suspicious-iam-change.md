# RB-003. Подозрительное изменение IAM

**Триггер:** `SEC | IAM policy changed` (D-01). **Severity:** ERROR (CRITICAL при `owner`/`editor`/`*.admin` или внешнем субъекте).

## 1. Triage

1. Событие: `logName:"cloudaudit.googleapis.com%2Factivity" protoPayload.methodName=~"(?i)setiampolic|setiampermissions"`.
2. Разбери `serviceData.policyDelta.bindingDeltas`: действие (ADD/REMOVE), member, role, на каком ресурсе.
3. Кто изменил, был ли тикет/PR/`terraform apply`, использовала ли identity новые права (Data Access логи после изменения).

## 2. Containment

Удалить лишнюю привязку (`remove-iam-policy-binding`, для проекта/bucket/SA соответственно). При компрометации исполнителя — отозвать его сессии/креды.

## 3. Eradication

Выяснить, почему у исполнителя была возможность менять IAM, и убрать лишнюю роль. Для экстренных случаев используй [emergency-access.md](emergency-access.md).

## 4. Recovery и проверка

```bash
gcloud projects get-iam-policy "$PROJECT_ID" --format=json > evidence/raw/iam-after.json
bash scripts/verify.sh
cd terraform && terraform plan      # дрейф управляемых привязок
```

Важно: привязки в Terraform аддитивные (`*_iam_member`), лишняя **ручная** привязка в `terraform plan` не видна. Сверяй политику вручную или используй Policy Analyzer/Asset Inventory.
