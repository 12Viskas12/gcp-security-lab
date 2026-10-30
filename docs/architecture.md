# 01. Архитектура

## Схема

```mermaid
flowchart LR
  subgraph ADM["Люди и identity"]
    SA_ADMIN["Security Admin"]
    OPER["Operator"]
    AUD["Auditor"]
  end

  subgraph PRJ["GCP project: PROJECT_ID (лаборатория)"]
    subgraph NET["VPC lab-vpc (custom mode)"]
      SUBNET["Subnet lab-private\nPrivate Google Access\nFlow Logs 10%"]
      FW["Firewall: deny-all ingress\n(logging on)"]
    end

    GCS[("Cloud Storage\nPROJECT_ID-lab-data\nUBLA + PAP enforced\nversioning + lifecycle")]
    SAR["SA: sa-app-reader\n(objectViewer на bucket)"]
    ROLES["SA ролей: lab-security-admin,\nlab-operator, lab-auditor"]
    SAN["SA: sa-no-access\n(нет прав на данные)"]

    subgraph OBS["Наблюдаемость"]
      AL["Cloud Audit Logs\nAdmin Activity + Data Access"]
      LB[("Log bucket security-audit\nLog Analytics, 30 дней")]
      LM["Log-match conditions (7)"]
      AP["Alert policies (7)"]
      NC["Email channel"]
    end
  end

  SA_ADMIN -->|политики, логи, алерты| PRJ
  SA_ADMIN -.->|impersonation от лица ролей| ROLES
  OPER -->|get/list/create объектов| GCS
  OPER -.->|TokenCreator| SAR
  AUD -->|чтение логов и конфигурации| AL
  SAR -->|read| GCS
  SAN -.->|PERMISSION_DENIED| GCS
  GCS --> AL
  PRJ --> AL
  AL -->|sink| LB
  AL --> LM --> AP --> NC
```

## Диаграмма потоков данных

```mermaid
flowchart LR
  USR["Лаборант / роли\n(через impersonation)"] -->|1 gcloud/API, HTTPS| GCS[("Bucket\nINTERNAL + CONFIDENTIAL")]
  ANON["Аноним"] -.->|2 запрос: 401/403| GCS
  GCS -->|3 Admin Activity + Data Access| AL["Cloud Audit Logs"]
  USR -->|4 SetIamPolicy, настройки| IAM["IAM / Resource Manager"]
  IAM -->|5 Admin Activity| AL
  AL -->|6 sink| LB[("security-audit\nLog Analytics, 30 дн.")]
  AL -->|7 log-match| MON["Monitoring\nalert policies (7)"]
  MON -->|8 email| SOC["SOC L1/L2"]
  SOC -->|9 запросы, расследование| LB
  TF["Terraform (локально)"] -->|10 apply/plan| IAM
  TF -.->|state: локальный файл, вне Git| DISK[("tfstate")]
```

Границы доверия: интернет ↔ проект GCP (Public Access Prevention, deny-all ingress); человек ↔ роли (impersonation, нет ключей); проект ↔ репозиторий (секреты и state не передаются).

## Принципы

1. **Отдельный проект** для лаборатории, никаких production-ресурсов и реальных данных.
2. **Нет публичной поверхности**: нет внешних IP, нет VM, bucket с Public Access Prevention.
3. **Минимальные привилегии**: права на данные выдаются только на уровне bucket, без Owner/Editor.
4. **Нет долгоживущих ключей**: доступ тестовых identity через impersonation.
5. **Всё наблюдаемо**: Admin Activity + выборочные Data Access, отдельный log bucket, детекции с алертами.
6. **Воспроизводимость**: вся инфраструктура в Terraform, ручные изменения считаются дрейфом.

## Поток данных и логов

- Запрос к bucket → Cloud Storage → запись в Cloud Audit Logs (Data Access) → sink → `security-audit` bucket.
- Изменение IAM/политик → Admin Activity log (всегда включён) → sink + log-based metric → alert policy → email.

## Границы и допущения

- Один проект: логи хранятся в том же проекте, где работают ресурсы (в production лучше отдельный log project).
- Шифрование: Google-managed keys (CMEK не используется, см. отчёт).
- Организационных политик (Organization Policy) в лабе нет, если у тебя нет организации. Рекомендация в отчёте.
