# Incident 02 (IR-02). Риск публичного Cloud Storage (попытка выдать allUsers)

| Поле | Значение |
| --- | --- |
| Incident ID | INC-2026-10-02 (IR-02) |
| Severity | Высокая (ERROR); итог: попытка заблокирована, утечки нет |
| Угрозы | T-02 (публичный Cloud Storage), T-03 (утечка данных) |
| Детекция | D-02 `SEC \| Cloud Storage bucket policy/config changed`, D-01 |
| Runbook | [RB-001](../runbooks/public-storage.md) |
| Контроли ISO 27001 | 5.15, 5.26, 8.3, 8.12, 8.15, 8.16 |

## Сценарий и воспроизведение

Проверяем, обнаружит ли и заблокирует ли система небезопасную конфигурацию: попытка выдать `allUsers` роль `objectViewer` на bucket с данными INTERNAL/CONFIDENTIAL. Ожидание: Public Access Prevention отклоняет операцию, попытка остаётся в аудит-логах и вызывает алерт.

```bash
export PROJECT_ID=...; export BUCKET="${PROJECT_ID}-lab-data"
date -u +%FT%TZ
gcloud storage buckets add-iam-policy-binding "gs://${BUCKET}" --member=allUsers --role=roles/storage.objectViewer
curl -s -o /dev/null -w '%{http_code}\n' "https://storage.googleapis.com/${BUCKET}/internal/employee-directory-SYNTHETIC.csv"
```

## 1. Incident ID и severity

INC-2026-10-02, IR-02, severity: **Высокая (ERROR); итог: попытка заблокирована, утечки нет**.

## 2. Временная шкала (UTC)

| Время UTC | Событие | Источник |
| --- | --- | --- |
| 2026-10-29 22:57:47 | Начало симуляции | Терминал |
| 22:58:01 | `storage.setIamPermissions` от владельца лабы, отклонено (code 9) | Admin Activity |
| ≈22:59 | Письма `SEC \| IAM policy changed` и `SEC \| Cloud Storage bucket policy/config changed` (≈1 минута после события) | Gmail, Monitoring |

## 3. Подтверждённые события и источники

| Факт | Источник / поле | Значение |
| --- | --- | --- |
| Актор | `principalEmail` | Владелец лабы (скрыт) |
| Метод | `methodName` | `storage.setIamPermissions` |
| Источник | `callerIp`, user agent | Скрыт; `gcloud 591.0.0`, Linux, неинтерактивный режим |
| Результат | `status` | code 9: «The member bindings allUsers and allAuthenticatedUsers are not allowed since public access prevention is enforced.» (HTTP 412 в gcloud) |
| Анонимный доступ после попытки | `curl` по объекту | HTTP 403 |

## 4. Гипотезы и их проверка

| Гипотеза | Как проверена | Результат |
| --- | --- | --- |
| Bucket стал публичным | Ошибка 412 при записи, `get-iam-policy` без `allUsers`, `curl` = 403 | Опровергнута |
| Действие плановое | Лабораторная симуляция, время зафиксировано | Подтверждена (учебное) |

## 5. Оценка влияния

Утечки нет: операция отклонена превентивным контролем (Public Access Prevention), анонимный доступ невозможен (403). Под угрозой были бы объекты `internal/` и `confidential/` (синтетические).

## 6. Containment

Дополнительных действий не потребовалось: контроль сработал сам. Состояние проверено: PAP = enforced, `allUsers` в IAM отсутствует.

## 7. Root cause

Попытка стала возможной, потому что у принципала есть `storage.buckets.setIamPolicy` (владелец проекта). Предотвратил её Public Access Prevention; без него bucket стал бы публичным.

## 8. Remediation

Сохранить PAP как обязательный контроль; ограничить права `setIamPolicy`; в организации закрепить Organization Policy `storage.publicAccessPrevention`.

## 9. Проверка после исправления

`curl` по объекту — 403; `bash scripts/verify.sh`: UBLA, PAP и отсутствие `allUsers` — PASS.

## 10. Lessons learned

Превентивный контроль важнее детектива, но детекция нужна и для неудачных попыток: они показывают намерение. Алерт срабатывает и на отклонённые операции.

## Доказательства

- Текст ошибки и выдержка лога `setIamPermissions` (code 9): `evidence/sanitized-logs/`
- Письма алертов: `evidence/screenshots/19-email-alerts.png`
- Права и защита bucket: `evidence/screenshots/05-bucket-permissions.jpg`, `07-bucket-config.jpg`

<!-- screenshots:Скриншоты -->
## Скриншоты

![Письма алертов](../evidence/screenshots/19-email-alerts.png)

*Письма алертов*

![Bucket: права, Public Access Prevention, UBLA](../evidence/screenshots/05-bucket-permissions.jpg)

*Bucket: права, Public Access Prevention, UBLA*

![Bucket: метки, шифрование, lifecycle](../evidence/screenshots/07-bucket-config.jpg)

*Bucket: метки, шифрование, lifecycle*
