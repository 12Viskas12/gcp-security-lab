# Incident 03 (IR-03). Подозрительный доступ к объектам (Data Access)

| Поле | Значение |
| --- | --- |
| Incident ID | INC-2026-10-03 (IR-03) |
| Severity | Средняя (WARNING); повышается при чтении CONFIDENTIAL |
| Угрозы | T-03 (утечка), T-05 (компрометация учётной записи) |
| Детекция | D-05, D-06, ручная D-08 |
| Runbook | [RB-002](../runbooks/unusual-data-access.md) |
| Контроли ISO 27001 | 5.15, 5.18, 5.25, 8.3, 8.15, 8.16 |

## Сценарий и воспроизведение

Тестовая identity выполняет несколько чтений синтетических объектов; нужно проверить наличие Data Access логов, установить principal, время, объект и результат, оценить достаточность телеметрии. Массового скачивания нет.

```bash
export PROJECT_ID=...; export BUCKET="${PROJECT_ID}-lab-data"
SA_NONE="sa-no-access@${PROJECT_ID}.iam.gserviceaccount.com"; SA_READER="sa-app-reader@${PROJECT_ID}.iam.gserviceaccount.com"
date -u +%FT%TZ
for o in internal/employee-directory-SYNTHETIC.csv confidential/finance-report-SYNTHETIC.csv; do
  gcloud storage cat "gs://${BUCKET}/${o}" --impersonate-service-account="$SA_READER" >/dev/null
done
for i in 1 2 3 4 5; do   # отказы для identity без прав
  gcloud storage cat "gs://${BUCKET}/confidential/finance-report-SYNTHETIC.csv" --impersonate-service-account="$SA_NONE" >/dev/null 2>&1
done
```

## 1. Incident ID и severity

INC-2026-10-03, IR-03, severity: **Средняя (WARNING); повышается при чтении CONFIDENTIAL**.

## 2. Временная шкала (UTC)

| Время UTC | Событие | Источник |
| --- | --- | --- |
| ≈23:28 | Выпуск токена `sa-app-reader` и `sa-no-access` (impersonation) | `iamcredentials`, Data Access |
| ≈23:28 | Успешные `storage.objects.get` (чтение объектов) и `PERMISSION_DENIED` для identity без прав | Data Access |
| ≈23:28–23:29 | Письма `SEC \| Service account token generated (impersonation)` и `SEC \| Cloud Storage PERMISSION_DENIED` | Gmail, Monitoring |

## 3. Подтверждённые события и источники

| Факт | Источник / поле | Значение |
| --- | --- | --- |
| Principal | `principalEmail` | Тестовый service account |
| Кто стоит за impersonation | `serviceAccountDelegationInfo` | Аккаунт владельца лабы |
| Объект, IP, время, результат | `resourceName`, `requestMetadata`, `timestamp`, `status.code` | Присутствуют в логе |
| Алерт на успешное чтение CONFIDENTIAL | Наличие письма | Нет: такого детекта нет (D-08) |

## 4. Гипотезы и их проверка

| Гипотеза | Как проверена | Результат |
| --- | --- | --- |
| Чтение штатное (разрешено ролью objectViewer) | Роль `sa-app-reader` на bucket | Да, но чтение CONFIDENTIAL не алертится |
| Разведка identity без прав | Серия отказов от `sa-no-access` | Алерт D-05 сработал |
| Достаточно ли телеметрии | Есть principal, delegation, объект, IP, время, код | Достаточно для атрибуции; нет содержимого и объёма |

## 5. Оценка влияния

Чтения выполнены синтетической identity с легитимной ролью; утечки нет. В реальной среде успешное чтение CONFIDENTIAL без алерта — слепое пятно.

## 6. Containment

В учебном случае не требуется. В реальном: отозвать `serviceAccountTokenCreator` у принципала, выпускавшего токен, отключить SA (`gcloud iam service-accounts disable`).

## 7. Root cause

Детекция построена на отказах и на выпуске токенов, а не на успешном доступе к CONFIDENTIAL; Data Access включён только для Storage и IAM.

## 8. Remediation

Добавить алерт/метрику на чтение `confidential/` неожиданной identity и пороговое правило по частоте; хранить логи дольше 30 дней; расширять Data Access по оценке риска.

## 9. Проверка после исправления

Запрос по логам возвращает события; `bash scripts/verify.sh` выполняется без ошибок.

## 10. Lessons learned

Data Access логи дают атрибуцию (кто, что, когда, откуда), включая человека за impersonation, но не содержимое. Алерт на отказ — разведка видна; успешный доступ виден только при ручном анализе.

## Доказательства

- Выдержка Data Access (успех и отказ) и `GenerateAccessToken`: `evidence/sanitized-logs/`
- Письма алертов: `evidence/screenshots/19-email-alerts.png`
