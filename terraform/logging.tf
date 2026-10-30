# Admin Activity логи включены всегда и не отключаются.
# Data Access логи включаем точечно, по нужным сервисам (не allServices: ради стоимости).
#
# Важно: iamcredentials.googleapis.com не поддерживает настройку аудита на уровне сервиса.
# Аудит IAM Service Account Credentials API (GenerateAccessToken и др.) настраивается
# через iam.googleapis.com, поэтому отдельной записи для iamcredentials здесь нет.

locals {
  data_access_audit = {
    "storage.googleapis.com" = ["ADMIN_READ", "DATA_READ", "DATA_WRITE"]
    "iam.googleapis.com"     = ["ADMIN_READ", "DATA_READ", "DATA_WRITE"]
  }
}

resource "google_project_iam_audit_config" "services" {
  for_each = local.data_access_audit

  project = var.project_id
  service = each.key

  dynamic "audit_log_config" {
    for_each = toset(each.value)
    content {
      log_type = audit_log_config.value
    }
  }

  depends_on = [google_project_service.apis]
}

# Отдельный log bucket для аудита + Log Analytics (SQL по логам).
resource "google_logging_project_bucket_config" "security" {
  project          = var.project_id
  location         = var.log_bucket_location
  bucket_id        = "security-audit"
  retention_days   = var.log_retention_days
  enable_analytics = true
  description      = "Централизованные аудит-логи лаборатории"

  # После terraform import провайдер хранит project как "projects/<id>" и требует замены ресурса
  # (ForceNew). Удалять и пересоздавать log bucket нельзя: имя блокируется после удаления.
  lifecycle {
    ignore_changes = [project]
  }

  depends_on = [google_project_service.apis]
}

resource "google_logging_project_sink" "audit" {
  project                = var.project_id
  name                   = "audit-to-security-bucket"
  destination            = "logging.googleapis.com/${google_logging_project_bucket_config.security.id}"
  filter                 = "logName:\"cloudaudit.googleapis.com\""
  unique_writer_identity = true
  description            = "Все Cloud Audit Logs в security-audit bucket"
}
