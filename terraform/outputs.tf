output "bucket_name" {
  description = "Имя lab bucket."
  value       = google_storage_bucket.data.name
}

output "sa_app_reader_email" {
  description = "Service account с правом чтения объектов."
  value       = google_service_account.app_reader.email
}

output "sa_no_access_email" {
  description = "Service account без прав на данные (негативные тесты)."
  value       = google_service_account.no_access.email
}

output "log_bucket" {
  description = "Log bucket с аудит-логами."
  value       = google_logging_project_bucket_config.security.id
}

output "alert_policies" {
  description = "Созданные алерты."
  value       = [for p in google_monitoring_alert_policy.detections : p.display_name]
}
