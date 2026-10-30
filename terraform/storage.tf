resource "google_storage_bucket" "data" {
  project  = var.project_id
  name     = "${var.project_id}-lab-data"
  location = upper(var.region)

  storage_class               = "STANDARD"
  uniform_bucket_level_access = true
  public_access_prevention    = "enforced"
  force_destroy               = true # только для лабы, чтобы destroy очищал bucket

  versioning {
    enabled = true
  }

  # Soft delete выключен ради стоимости: восстановление обеспечивает versioning.
  soft_delete_policy {
    retention_duration_seconds = 0
  }

  dynamic "retention_policy" {
    for_each = var.bucket_retention_seconds > 0 ? [1] : []
    content {
      retention_period = var.bucket_retention_seconds
      is_locked        = false # осознанно: locked-политику нельзя снять
    }
  }

  # Стоимость: старые версии удаляются, редко читаемые данные уходят в NEARLINE.
  lifecycle_rule {
    condition {
      days_since_noncurrent_time = var.noncurrent_version_retention_days
    }
    action {
      type = "Delete"
    }
  }

  lifecycle_rule {
    condition {
      age                   = 90
      matches_storage_class = ["STANDARD"]
    }
    action {
      type          = "SetStorageClass"
      storage_class = "NEARLINE"
    }
  }

  lifecycle_rule {
    condition {
      age = 7
    }
    action {
      type = "AbortIncompleteMultipartUpload"
    }
  }

  labels = merge(local.common_labels, {
    data_classification = "confidential" # bucket содержит и internal, и confidential: берём высший уровень
  })

  depends_on = [google_project_service.apis]
}

# Синтетические данные. Никаких реальных персональных данных.
resource "google_storage_bucket_object" "internal_sample" {
  bucket       = google_storage_bucket.data.name
  name         = "internal/employee-directory-SYNTHETIC.csv"
  content_type = "text/csv"
  content      = <<-EOT
    id,name,department
    1,Test User A,IT
    2,Test User B,Finance
    3,Test User C,Support
  EOT

  metadata = {
    classification = "INTERNAL"
    synthetic      = "true"
  }
}

resource "google_storage_bucket_object" "confidential_sample" {
  bucket       = google_storage_bucket.data.name
  name         = "confidential/finance-report-SYNTHETIC.csv"
  content_type = "text/csv"
  content      = <<-EOT
    quarter,revenue_fake,note
    Q1,100000,SYNTHETIC DATA - NOT REAL
    Q2,120000,SYNTHETIC DATA - NOT REAL
  EOT

  metadata = {
    classification = "CONFIDENTIAL"
    synthetic      = "true"
  }
}
