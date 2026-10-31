# Модель угроз

Метод: STRIDE + оценка «вероятность × влияние» (шкала 1–5). Оценки — мои исходные суждения для учебного проекта, пересмотри их по результатам расследований.

**Область:** тестовый проект GCP (bucket с синтетическими INTERNAL/CONFIDENTIAL, IAM, аудит, сеть). **Активы:** данные, IAM-политики, audit config и логи, service accounts, периметр, репозиторий. **Субъекты:** аноним, скомпрометированная identity (человек или SA), инсайдер.

## Реестр угроз

| ID | Угроза (STRIDE) | Сценарий | Вер. | Вл. | Риск до | Превентивные контроли | Детективные | Корректирующие | Риск после | Инцидент |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| T-01 | EoP: чрезмерные привилегии IAM | Лишняя роль на проект/bucket, Editor у служебных SA | 4 | 4 | 16 | Роли на уровне bucket, custom role, нет Owner/Editor в работе, три роли с разделением | D-01, D-03, ревью IAM | Удаление привязки, отключение SA, `terraform apply` | 6 | IR-01, IR-05 |
| T-02 | Information Disclosure: публичный Cloud Storage | Выдача `allUsers`, публичный bucket | 3 | 5 | 15 | Public Access Prevention, UBLA | D-02, D-01 | Вернуть политику, проверить 403 | 3 | IR-02 |
| T-03 | Information Disclosure: утечка данных | Чтение CONFIDENTIAL скомпрометированной/неположенной identity | 3 | 5 | 15 | IAM минимальных прав, нет прав у Auditor на данные | D-05, D-06, D-08 (ручной) | Отзыв доступа, оценка по Data Access | 8 | IR-03 |
| T-04 | Tampering/Repudiation: изменение логирования | Exempted members, отключение Data Access, правка sink | 2 | 5 | 10 | Ограничение `setIamPolicy`, аудит в отдельном log bucket | D-04, дрейф `terraform plan` | Возврат audit config из кода | 6 | IR-04 |
| T-05 | Spoofing: компрометация учётной записи | Кража сессии/пароля владельца, злоупотребление impersonation | 3 | 5 | 15 | MFA (проверить), TokenCreator только Operator и tester, нет ключей | D-06, D-01 | Отзыв сессий и ролей, смена кредов | 8 | IR-03, IR-05 |
| T-06 | Spoofing/EoP: небезопасное управление ключами | Долгоживущий ключ SA, ключ в Git | 3 | 4 | 12 | Нет пользовательских ключей (`verify.sh`), impersonation, gitleaks, push protection | D-03, `verify.sh` | Удаление ключа, отзыв, ротация | 4 | IR-05 |
| T-07 | Информация/Tampering: неожиданный внешний endpoint | Правило firewall из `0.0.0.0/0`, VM с внешним IP, внешний IP-адрес | 3 | 4 | 12 | Custom VPC, deny-all ingress, нет внешних IP, нет default VPC | D-07, `drift-check.sh` | Удаление ресурса, ревью кода | 6 | IR-06 |
| T-08 | Repudiation: недостаточный срок хранения журналов | Логи 30 дней, расследование позже окна | 3 | 3 | 9 | Отдельный log bucket, Log Analytics; срок задан явно | Мониторинг retention | Увеличить срок, lock bucket, экспорт в архив | 6 | — (finding F-06) |
| T-09 | DoS/Cost: неконтролируемые расходы | Лишние ресурсы, Data Access логи | 2 | 3 | 6 | Бюджет с порогами, нет VM/внешних IP, Data Access точечно | Уведомления бюджета | `terraform destroy` | 3 | — |
| T-10 | Information Disclosure: утечка секретов в репозиторий | tfstate/tfvars/ключ/токен в Git | 3 | 5 | 15 | `.gitignore`, `pre-push-check.sh`, gitleaks в CI, push protection | CI, секрет-сканирование | Отзыв секрета, очистка истории | 4 | — |
| T-11 | Repudiation: злоупотребление экстренным доступом | Постоянные права «на время» | 2 | 4 | 8 | Временные conditional bindings, пост-аудит | D-01 | Удаление привязки | 4 | — |
| T-12 | Tampering: потеря/порча Terraform state | Потеря локального state, ручные изменения | 3 | 3 | 9 | Бэкенд GCS с versioning (рекомендация), `.gitignore` | `drift-check.sh` | `import-existing.sh` | 4 | — (finding F-05, потеря state реально произошла) |

Риск = вероятность × влияние. Приоритеты: ≥15 — высокий, 8–14 — средний, <8 — низкий.

## Что не покрыто

- Организационные политики недоступны без организации (учебный аккаунт): запрет ключей SA, domain-restricted sharing.
- Security Command Center требует организации; вместо него — `verify.sh`, `drift-check.sh`, Cloud Asset Inventory.
- Нет внешних приложений (Cloud Run не разворачивался): угрозы приложений вне области.
