variable "project_id" {
  description = "ID отдельного тестового GCP-проекта (только для лабы, не production)."
  type        = string
}

variable "region" {
  description = "Регион ресурсов. Проверь доступность сервисов и цены перед развёртыванием."
  type        = string
  default     = "europe-central2"
}

variable "subnet_cidr" {
  description = "CIDR единственной приватной подсети."
  type        = string
  default     = "10.10.0.0/24"
}

variable "owner_label" {
  description = "Значение label owner: строчные буквы, цифры, '-' и '_' (email в label нельзя)."
  type        = string
  default     = "student"

  validation {
    condition     = can(regex("^[a-z0-9_-]{1,63}$", var.owner_label))
    error_message = "owner_label: только a-z, 0-9, '-' и '_', до 63 символов."
  }
}

variable "extra_labels" {
  description = "Дополнительные labels для всех ресурсов, которые их поддерживают."
  type        = map(string)
  default     = {}
}

variable "alert_email" {
  description = "Email для оповещений Cloud Monitoring."
  type        = string
}

# --- IAM: члены ролей. Формат: "user:name@example.com" или "group:team@example.com" ---

variable "security_admin_members" {
  description = "Security Admin: управление логированием, алертами, политиками bucket."
  type        = list(string)
  default     = []

  validation {
    condition     = alltrue([for m in var.security_admin_members : can(regex("^(user|group|serviceAccount):", m))])
    error_message = "Каждый член должен начинаться с user:, group: или serviceAccount:."
  }
}

variable "operator_members" {
  description = "Operator: ограниченные операционные действия."
  type        = list(string)
  default     = []

  validation {
    condition     = alltrue([for m in var.operator_members : can(regex("^(user|group|serviceAccount):", m))])
    error_message = "Каждый член должен начинаться с user:, group: или serviceAccount:."
  }
}

variable "auditor_members" {
  description = "Auditor: чтение журналов и конфигурации, без доступа к данным."
  type        = list(string)
  default     = []

  validation {
    condition     = alltrue([for m in var.auditor_members : can(regex("^(user|group|serviceAccount):", m))])
    error_message = "Каждый член должен начинаться с user:, group: или serviceAccount:."
  }
}

variable "tester_members" {
  description = "Владелец лабы / тестировщик: может получать токены обоих тестовых SA (impersonation) для verify.sh и симуляций инцидентов. Отдельно от роли Operator."
  type        = list(string)
  default     = []

  validation {
    condition     = alltrue([for m in var.tester_members : can(regex("^(user|group|serviceAccount):", m))])
    error_message = "Каждый член должен начинаться с user:, group: или serviceAccount:."
  }
}

# --- Storage ---

variable "bucket_retention_seconds" {
  description = "Retention policy на объекты (0 = выключено). Не locked, чтобы лабу можно было удалить. 86400 = 24 ч; пока не истекло, terraform destroy объектов упадёт."
  type        = number
  default     = 86400
}

variable "noncurrent_version_retention_days" {
  description = "Через сколько дней удалять неактуальные версии объектов (экономия стоимости)."
  type        = number
  default     = 30
}

# --- Логирование ---

variable "log_bucket_location" {
  description = "Расположение log bucket (global или регион, поддерживаемый Cloud Logging)."
  type        = string
  default     = "global"
}

variable "log_retention_days" {
  description = "Срок хранения аудит-логов в security-audit bucket (в лабе 30 дней ради стоимости)."
  type        = number
  default     = 30
}

# --- Бюджет (опционально; основной путь — создать бюджет через gcloud до начала работ) ---

variable "billing_account" {
  description = "ID billing account (XXXXXX-XXXXXX-XXXXXX). Пусто = бюджет через Terraform не создаётся."
  type        = string
  default     = ""
}

variable "budget_usd" {
  description = "Сумма бюджета в USD. Уведомления НЕ останавливают расходы."
  type        = number
  default     = 10
}
