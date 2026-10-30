# Экстренный доступ (break-glass) и последующий аудит

Назначение: срочно получить повышенные права, когда обычных ролей недостаточно (например, исправить IAM при инциденте), без постоянных привилегий.

## Принципы

- Нет постоянных Owner/Editor. Повышенные права выдаются **на ограниченное время** через условную привязку IAM.
- Каждое использование сопровождается записью (тикет/инцидент) и пост-аудитом.
- Выдаёт доступ второе лицо (в лабе: владелец проекта), выданные права не больше, чем нужно.

## 1. Запрос

Запиши: кто просит, зачем, какая роль, на сколько, ссылка на инцидент (<инцидент>).

## 2. Выдача на ограниченный срок

Пример: `roles/iam.securityAdmin` на 1 час для исправления политики. Время в UTC.

```bash
EXPIRY=$(date -u -d '+1 hour' +%FT%TZ)    # на macOS: date -u -v+1H +%FT%TZ
gcloud projects add-iam-policy-binding "$PROJECT_ID" \
  --member="user:ENGINEER@example.com" \
  --role="roles/iam.securityAdmin" \
  --condition="expression=request.time < timestamp('${EXPIRY}'),title=break-glass-<инцидент>,description=Emergency access for <инцидент>"
```

Условие по времени не отзывает уже выданные токены мгновенно, поэтому срок делай коротким.

## 3. Использование

- Работай только над целью запроса.
- Фиксируй выполненные команды (`script`/история) для пост-аудита.

## 4. Закрытие

Привязка исчезает по истечению условия, но **удали её явно** (чтобы не копился мусор в политике):

```bash
gcloud projects remove-iam-policy-binding "$PROJECT_ID" \
  --member="user:ENGINEER@example.com" --role="roles/iam.securityAdmin" \
  --condition="expression=request.time < timestamp('${EXPIRY}'),title=break-glass-<инцидент>,description=Emergency access for <инцидент>"
```

## 5. Пост-аудит (в течение 24 часов)

```bash
gcloud logging read 'protoPayload.authenticationInfo.principalEmail="ENGINEER@example.com"' \
  --project="$PROJECT_ID" --freshness=1d \
  --format='table(timestamp, protoPayload.methodName, protoPayload.resourceName, protoPayload.status.code)'
```

Проверить:

- [ ] Все действия соответствуют цели запроса
- [ ] Привязка удалена, нет остаточных прав
- [ ] Алерт `IAM policy changed` связан с этим запросом (не «потерялся»)
- [ ] Изменения отражены в Terraform/Git (нет дрейфа)
- [ ] Запись в журнале: кто одобрил, когда, результат

## 6. Анти-паттерны

Постоянный Owner «на всякий случай», общие аккаунты, выдача без срока, отсутствие тикета, отсутствие пост-аудита.
