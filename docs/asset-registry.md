# Реестр активов

Классификация данных: `INTERNAL`, `CONFIDENTIAL`. Владелец: значение `owner_label` из `terraform.tfvars`.
Labels на всех ресурсах, которые их поддерживают: `environment=lab`, `managed_by=terraform`, `project=gcp-security-lab`, `owner=<owner_label>`.

| ID | Ресурс | Тип | Имя | Классификация | Ключевые контроли | Файл Terraform |
| --- | --- | --- | --- | --- | --- | --- |
| R-01 | GCP project | Project | `PROJECT_ID` | n/a | Отдельный проект, budget alerts, создан вручную (gcloud) | вне TF |
| R-02 | Google Cloud APIs | Service | compute, iam, iamcredentials, cloudresourcemanager, serviceusage, logging, monitoring, storage, billingbudgets, cloudbilling, cloudasset | n/a | Только необходимые API | `main.tf` |
| R-03 | VPC | Network | `lab-vpc` | n/a | Custom mode, нет default-сети | `network.tf` |
| R-04 | Subnet | Subnetwork | `lab-private-<region>` | n/a | Private Google Access, Flow Logs | `network.tf` |
| R-05 | Firewall rule | Firewall | `lab-deny-all-ingress` | n/a | Deny-all ingress, логирование | `network.tf` |
| R-06 | Bucket | Cloud Storage | `PROJECT_ID-lab-data` | CONFIDENTIAL (высший из хранимых) | UBLA, PAP enforced, versioning, lifecycle, retention (не locked) | `storage.tf` |
| R-07 | Object | GCS object | `internal/employee-directory-SYNTHETIC.csv` | INTERNAL | Синтетические данные, metadata `classification` | `storage.tf` |
| R-08 | Object | GCS object | `confidential/finance-report-SYNTHETIC.csv` | CONFIDENTIAL | Синтетические данные, metadata `classification` | `storage.tf` |
| R-09 | Service account | IAM | `sa-app-reader` | n/a | `objectViewer` только на bucket, без ключей | `iam.tf` |
| R-10 | Service account | IAM | `sa-no-access` | n/a | Нет прав на данные, для негативных тестов | `iam.tf` |
| R-11 | Custom role | IAM | `labOperator` | n/a | 4 разрешения: get bucket, get/list/create objects | `iam.tf` |
| R-12 | Audit configs | IAM audit | storage, iam | n/a | Data Access: ADMIN_READ/DATA_READ/DATA_WRITE | `logging.tf` |
| R-13 | Log bucket | Cloud Logging | `security-audit` | CONFIDENTIAL (логи содержат identity) | 30 дней, Log Analytics | `logging.tf` |
| R-14 | Log sink | Cloud Logging | `audit-to-security-bucket` | n/a | Все `cloudaudit.googleapis.com` | `logging.tf` |
| R-15 | Log-based alert conditions | Monitoring | 7 условий `condition_matched_log` | n/a | Детекции IAM/GCS/SA/audit/denied/impersonation/compute | `monitoring.tf` |
| R-16 | Alert policies | Monitoring | `SEC \| ...` (7 шт.) | n/a | Email, ссылки на runbooks | `monitoring.tf` |
| R-17 | Notification channel | Monitoring | `Lab security email` | n/a | Email | `monitoring.tf` |
| R-19 | Budget | Billing | `sec-lab-budget` | n/a | 50/90/100%, уведомления (не останавливает расходы) | gcloud / опц. `monitoring.tf` |
| R-18 | Service accounts ролей | IAM | `lab-security-admin`, `lab-operator`, `lab-auditor` | n/a | Носители ролей, без ключей, impersonation | `iam.tf` |

## Identities (кто что может)

| Identity | Тип | Роли (кратко) | Ключи | Владелец |
| --- | --- | --- | --- | --- |
| Лаборант (аккаунт владельца проекта) | Человек | Owner (Legacy), TokenCreator на тестовые SA | Нет | `owner_label` |
| `lab-security-admin` | SA | см. [iam-review.md](iam-review.md) | Нет | `owner_label` |
| `lab-operator` | SA | custom `labOperator`, monitoring.viewer | Нет | `owner_label` |
| `lab-auditor` | SA | securityReviewer, privateLogViewer, monitoring.viewer, networkViewer | Нет | `owner_label` |
| `sa-app-reader` | SA | objectViewer на bucket | Нет | `owner_label` |
| `sa-no-access` | SA | нет | Нет | `owner_label` |

## Приложения и внешние endpoint

Приложений (Cloud Run, VM) нет; внешних endpoint нет; публичных IP нет. Любое появление — инцидент (см. IR-06).

## Журналы

| Журнал | Срок хранения | Кто может читать |
| --- | --- | --- |
| Admin Activity (`_Required`) | 400 дней, не отключается | Auditor (`privateLogViewer`), Security Admin (`logging.viewer`), Owner |
| Data Access (`_Default`) | 30 дней | Auditor (`privateLogViewer`), Owner |
| `security-audit` (все audit-логи через sink) | 30 дней (`log_retention_days`), Log Analytics | Auditor, Security Admin, Owner |

Реестр нужно держать актуальным: после `terraform apply` сверь с выводом `gcloud asset`/консоли и добавь ресурсы, созданные вне Terraform (если есть).
