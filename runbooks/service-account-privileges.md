# RB-004. Service account: избыточные права и управление SA

**Триггер:** `SEC | Service account or key management event` (D-03), `SEC | IAM policy changed` по SA. **Severity:** ERROR.

## 1. Triage

1. Кто создал/изменил SA (`principalEmail`, `resourceName`)? Есть ли тикет/PR?
2. Какие роли у SA сейчас:
```bash
gcloud projects get-iam-policy "$PROJECT_ID" --flatten='bindings[].members' \
  --filter="bindings.members:serviceAccount:SA_EMAIL" --format='table(bindings.role)'
gcloud storage buckets get-iam-policy "gs://${BUCKET}" --format=json | grep -B2 -A2 SA_EMAIL
```
3. Есть ли пользовательские ключи: `gcloud iam service-accounts keys list --iam-account=SA_EMAIL --managed-by=user` (ожидается пусто).
4. Кто может impersonate SA: `gcloud iam service-accounts get-iam-policy SA_EMAIL`.

## 2. Оценка влияния

Что может сделать компрометация SA: сколько разрешений даёт роль (`gcloud iam roles describe ROLE`), на какие ресурсы действует, можно ли читать/писать/удалять данные и менять IAM.

## 3. Containment

Отключить SA (`gcloud iam service-accounts disable`), снять лишнюю роль, удалить ключи (если есть).

## 4. Remediation и проверка

Выдать минимально необходимую роль на минимально возможном уровне (bucket вместо проекта), повторить проверку доступа через impersonation, `scripts/verify.sh`. Ключи для упражнений не создавать.
