provider "google" {
  project = var.project_id
  region  = var.region

  # Нужно для API бюджетов/мониторинга: квота и биллинг запросов идут на лаб-проект.
  user_project_override = true
  billing_project       = var.project_id
}
