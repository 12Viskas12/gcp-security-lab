# Общий процесс реагирования (SOC L1/L2, Cloud Security Engineer)

Применяется ко всем алертам. Специфика конкретных детектов: RB-001 … RB-006 в этой папке.

## Уровни серьёзности и ожидаемое время

| Severity | Пример | Начать triage | Containment |
| --- | --- | --- | --- |
| CRITICAL | Изменён audit config, публичный bucket | немедленно (≤15 мин) | ≤1 час |
| ERROR | Лишняя IAM-привязка, неожиданный firewall/VM | ≤1 час | ≤4 часа |
| WARNING | Серия отказов, impersonation | ≤1 рабочий день | по результатам triage |

## 1. Triage (SOC L1)

1. Открой письмо/инцидент в Monitoring → Alerting. Запиши время алерта и время события в логе (UTC).
2. Выполни запрос детекта из [detections/queries.md](../detections/queries.md). Определи: **кто** (`principalEmail`, `serviceAccountDelegationInfo`), **что**, **на чём**, **успешно ли** (`status.code`), **откуда** (`callerIp`, user agent).
3. Это плановое изменение? Сверь с Git/PR/Terraform/тикетом/окном экстренного доступа.
4. Решение: *ложное срабатывание* (закрыть с записью) / *подозрительно* (эскалация L2, см. [tabletop.md](tabletop.md)).

## 2. Сохранение доказательств (до любых исправлений)

```bash
mkdir -p evidence/raw
gcloud logging read '<запрос детекта> AND timestamp>="<UTC>"' --project="$PROJECT_ID" --format=json \
  > evidence/raw/<id>-log.json
sha256sum evidence/raw/<id>-log.json | tee -a evidence/raw/hashes.txt     # целостность
gcloud projects get-iam-policy "$PROJECT_ID" --format=json > evidence/raw/<id>-iam-before.json
bash scripts/sanitize.sh evidence/raw/<id>-log.json > evidence/sanitized-logs/<id>-log.txt
```

Скриншоты: письмо алерта, инцидент в Monitoring, запись в Logs Explorer. Не меняй состояние до фиксации.

## 3. Containment (L2 / Cloud Security Engineer)

Минимально необходимое действие, обратимое и записанное: отозвать лишнюю привязку, отключить SA (`gcloud iam service-accounts disable`), удалить подозрительное правило, вернуть политику bucket. Не удаляй логи и не отключай аудит.

## 4. Устранение причины (Eradication)

Найди, **почему** это стало возможным: лишняя роль у принципала, отсутствие ограничения, слепое пятно детекта. Исправь причину (Terraform/IAM), а не только симптом.

## 5. Восстановление (Recovery)

Верни целевое состояние из кода: `terraform plan` (ожидается «No changes»), `terraform apply` при дрейфе. Реши, кто принимает решение о возврате в штатный режим: владелец сервиса (в лабе — владелец проекта).

## 6. Проверка работоспособности

```bash
export PROJECT_ID=...
bash scripts/verify.sh | tee evidence/sanitized-logs/verify-after-<id>.txt     # ожидается FAIL=0
bash scripts/drift-check.sh
```

## 7. Коммуникации

| Кому | Когда | Что |
| --- | --- | --- |
| Владелец сервиса | При ERROR/CRITICAL | Что случилось, затронутые ресурсы, что сделано, что нужно от него |
| Incident Commander | CRITICAL или подтверждённая утечка | Краткий статус каждые 30–60 минут |
| Руководство/Compliance | Подтверждённая утечка данных | По процедуре организации; решение об уведомлениях принимает IC |

Шаблон сообщения: `[SEV] <что> | время UTC | затронуто: <ресурсы> | статус: <triage/containment/recovered> | следующий шаг и время обновления`.

## 8. Закрытие

Заполни `incidents/incident-0X.md` (10 пунктов), добавь находки в `reports/final-report.md`, обнови модель угроз и детекты, если выявлено слепое пятно.
