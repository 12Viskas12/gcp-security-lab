# RB-005. Изменение настроек аудита

**Триггер:** `SEC | Audit configuration changed` (D-04). **Severity:** CRITICAL.

## 1. Triage

1. Запрос: `protoPayload.serviceName="cloudresourcemanager.googleapis.com" protoPayload.methodName="SetIamPolicy" protoPayload.serviceData.policyDelta.auditConfigDeltas:*`.
2. Кто, какой сервис и logType изменён, какой exempted member добавлен/убран.
3. Плановое ли изменение (`terraform apply`)?

## 2. Containment

Немедленно вернуть auditConfig (Terraform: `terraform apply`; или `gcloud projects set-iam-policy` с сохранённой копией), ограничить принципала.

## 3. Оценка окна «слепоты»

Время от изменения до возврата. Всё, что сделала exempted identity в этом окне, считать непроверяемым по Data Access; искать по Admin Activity, `iamcredentials`, сетевым логам, Cloud Asset history.

## 4. Eradication

Выяснить, почему принципал мог менять IAM-политику проекта; убрать лишнюю роль.

## 5. Recovery и проверка

```bash
gcloud projects get-iam-policy "$PROJECT_ID" --format='json(auditConfigs)'
bash scripts/verify.sh
cd terraform && terraform plan      # должен показать «No changes» после возврата
```

## 6. Защита логов (улучшения)

Отдельный log project и organization-level sink; блокировка (lock) log bucket; ограничение `resourcemanager.projects.setIamPolicy`; Cloud Asset history как второй источник.
