resource "google_monitoring_notification_channel" "email" {
  project      = var.project_id
  display_name = "Lab security email"
  type         = "email"

  labels = {
    email_address = var.alert_email
  }

  depends_on = [google_project_service.apis]
}

locals {
  detections = {
    iam_policy_change = {
      title    = "IAM policy changed"
      severity = "ERROR"
      runbook  = "RB-003"
      filter   = "logName:\"cloudaudit.googleapis.com%2Factivity\" AND protoPayload.methodName=~\"(?i)setiampolic|setiampermissions\""
    }
    gcs_policy_change = {
      title    = "Cloud Storage bucket policy/config changed"
      severity = "ERROR"
      runbook  = "RB-001"
      filter   = "resource.type=\"gcs_bucket\" AND logName:\"cloudaudit.googleapis.com%2Factivity\" AND protoPayload.methodName=~\"(?i)setiampermissions|buckets.(update|patch|delete)\""
    }
    sa_management = {
      title    = "Service account or key management event"
      severity = "ERROR"
      runbook  = "RB-004"
      filter   = "protoPayload.serviceName=\"iam.googleapis.com\" AND protoPayload.methodName=~\"(?i)(create|delete|disable|enable|undelete|upload|patch|update)serviceaccount\""
    }
    audit_config_change = {
      title    = "Audit configuration changed"
      severity = "CRITICAL"
      runbook  = "RB-005"
      filter   = "protoPayload.serviceName=\"cloudresourcemanager.googleapis.com\" AND protoPayload.methodName=\"SetIamPolicy\" AND protoPayload.serviceData.policyDelta.auditConfigDeltas:*"
    }
    gcs_denied_access = {
      title    = "Cloud Storage PERMISSION_DENIED"
      severity = "WARNING"
      runbook  = "RB-002"
      filter   = "resource.type=\"gcs_bucket\" AND protoPayload.status.code=7"
    }
    sa_impersonation = {
      title    = "Service account token generated (impersonation)"
      severity = "WARNING"
      runbook  = "RB-002"
      filter   = "protoPayload.serviceName=\"iamcredentials.googleapis.com\" AND protoPayload.methodName=~\"GenerateAccessToken|GenerateIdToken|SignBlob|SignJwt\""
    }
    unexpected_compute_change = {
      title    = "Unexpected network or compute resource change"
      severity = "ERROR"
      runbook  = "RB-006"
      filter   = "protoPayload.serviceName=\"compute.googleapis.com\" AND logName:\"cloudaudit.googleapis.com%2Factivity\" AND protoPayload.methodName=~\"(?i)compute.(firewalls|networks|subnetworks|routes|addresses|instances).(insert|patch|update|delete)\""
    }
  }
}

resource "google_monitoring_alert_policy" "detections" {
  for_each = local.detections

  project      = var.project_id
  display_name = "SEC | ${each.value.title}"
  combiner     = "OR"
  severity     = each.value.severity

  conditions {
    display_name = each.value.title

    condition_matched_log {
      filter = each.value.filter
    }
  }

  notification_channels = [google_monitoring_notification_channel.email.id]

  alert_strategy {
    notification_rate_limit {
      period = "300s"
    }
    auto_close = "1800s"
  }

  documentation {
    mime_type = "text/markdown"
    content   = "Сработала детекция **${each.value.title}**. Следуй runbook **${each.value.runbook}** (папка runbooks/ в репозитории). Сначала проверь, не ваши ли это лабораторные действия."
  }

  depends_on = [google_project_service.apis]
}

resource "google_billing_budget" "lab" {
  count = var.billing_account == "" ? 0 : 1

  billing_account = var.billing_account
  display_name    = "gcp-security-lab budget"

  budget_filter {
    projects = ["projects/${data.google_project.this.number}"]
  }

  amount {
    specified_amount {
      currency_code = "USD"
      units         = tostring(var.budget_usd)
    }
  }

  threshold_rules {
    threshold_percent = 0.5
  }
  threshold_rules {
    threshold_percent = 0.9
  }
  threshold_rules {
    threshold_percent = 1.0
  }

  all_updates_rule {
    monitoring_notification_channels = [google_monitoring_notification_channel.email.id]
  }
}
