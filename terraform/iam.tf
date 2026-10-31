# ---------- Service accounts (без ключей: ключи не создаются) ----------

resource "google_service_account" "app_reader" {
  project      = var.project_id
  account_id   = "sa-app-reader"
  display_name = "Lab: read-only access to lab bucket"
  description  = "Тестовая identity с единственным правом читать объекты lab bucket."

  depends_on = [google_project_service.apis]
}

resource "google_service_account" "no_access" {
  project      = var.project_id
  account_id   = "sa-no-access"
  display_name = "Lab: identity without data permissions"
  description  = "Негативные тесты и симуляции инцидентов. Прав на данные нет."

  depends_on = [google_project_service.apis]
}

resource "google_storage_bucket_iam_member" "app_reader_objects" {
  bucket = google_storage_bucket.data.name
  role   = "roles/storage.objectViewer"
  member = "serviceAccount:${google_service_account.app_reader.email}"
}

# ---------- Кастомная роль Operator: читать/создавать объекты, без удаления и без IAM ----------

resource "google_project_iam_custom_role" "lab_operator" {
  project     = var.project_id
  role_id     = "labOperator"
  title       = "Lab Operator"
  description = "Чтение/создание объектов и просмотр метаданных bucket. Без delete, без IAM."
  permissions = [
    "storage.buckets.get",
    "storage.objects.get",
    "storage.objects.list",
    "storage.objects.create",
  ]

  depends_on = [google_project_service.apis]
}

# ---------- Привязки по ролям ----------

# Три роли лабы реализованы отдельными service accounts (без ключей). Люди/группы из tfvars
# добавляются к ним. Лаборант действует от их имени через impersonation (tester_members).
locals {
  role_holder_sas = {
    security_admin = "lab-security-admin"
    operator       = "lab-operator"
    auditor        = "lab-auditor"
  }

  # Email задаётся строкой, а не атрибутом ресурса: так ключи for_each известны на этапе plan.
  role_holder_members = {
    for k, v in local.role_holder_sas : k => "serviceAccount:${v}@${var.project_id}.iam.gserviceaccount.com"
  }

  security_admin_all = concat(var.security_admin_members, [local.role_holder_members["security_admin"]])
  operator_all       = concat(var.operator_members, [local.role_holder_members["operator"]])
  auditor_all        = concat(var.auditor_members, [local.role_holder_members["auditor"]])
}

resource "google_service_account" "role_holders" {
  for_each = local.role_holder_sas

  project      = var.project_id
  account_id   = each.value
  display_name = "Lab role holder: ${each.key}"
  description  = "Носитель роли ${each.key}. Ключей нет, доступ только через impersonation."

  depends_on = [google_project_service.apis]
}

locals {
  # Уровень проекта: только то, что нельзя выдать уже на уровне ресурса.
  project_roles = {
    security_admin = {
      members = local.security_admin_all
      roles = [
        "roles/iam.securityReviewer",
        "roles/logging.configWriter",
        "roles/logging.viewer",
        "roles/monitoring.alertPolicyEditor",
        "roles/monitoring.viewer",
      ]
    }
    operator = {
      members = local.operator_all
      roles   = ["roles/monitoring.viewer"]
    }
    auditor = {
      members = local.auditor_all
      roles = [
        "roles/iam.securityReviewer",
        "roles/logging.privateLogViewer",
        "roles/monitoring.viewer",
        "roles/compute.networkViewer",
      ]
    }
  }

  project_bindings = merge([
    for group, cfg in local.project_roles : {
      for pair in setproduct(cfg.members, cfg.roles) :
      "${group}|${pair[0]}|${pair[1]}" => { member = pair[0], role = pair[1] }
    }
  ]...)

  # Уровень bucket: права на данные выдаются только здесь. У Auditor прав на данные нет.
  bucket_roles = {
    security_admin = {
      members = local.security_admin_all
      roles   = ["roles/storage.admin"]
    }
    operator = {
      members = local.operator_all
      roles   = ["projects/${var.project_id}/roles/labOperator"]
    }
  }

  bucket_bindings = merge([
    for group, cfg in local.bucket_roles : {
      for pair in setproduct(cfg.members, cfg.roles) :
      "${group}|${pair[0]}|${pair[1]}" => { member = pair[0], role = pair[1] }
    }
  ]...)
}

resource "google_project_iam_member" "role_bindings" {
  for_each = local.project_bindings

  project = var.project_id
  role    = each.value.role
  member  = each.value.member

  depends_on = [google_service_account.role_holders]
}

resource "google_storage_bucket_iam_member" "role_bindings" {
  for_each = local.bucket_bindings

  bucket = google_storage_bucket.data.name
  role   = each.value.role
  member = each.value.member

  depends_on = [google_service_account.role_holders, google_project_iam_custom_role.lab_operator]
}

# Operator может получать токен ТОЛЬКО для sa-app-reader (impersonation вместо ключей).
resource "google_service_account_iam_member" "operator_impersonates_reader" {
  for_each = toset(local.operator_all)

  service_account_id = google_service_account.app_reader.name
  role               = "roles/iam.serviceAccountTokenCreator"
  member             = each.value

  depends_on = [google_service_account.role_holders]
}

# ---------- Тестовый стенд ----------
# Лаборант (владелец лабы) получает TokenCreator на ОБА тестовых SA: без этого нельзя ни
# выполнить scripts/verify.sh, ни симулировать IR-03 от имени sa-no-access.
# Basic-роль Owner сама по себе не даёт права выпускать токены SA.

locals {
  test_sas = {
    app_reader     = google_service_account.app_reader.name
    no_access      = google_service_account.no_access.name
    security_admin = google_service_account.role_holders["security_admin"].name
    operator       = google_service_account.role_holders["operator"].name
    auditor        = google_service_account.role_holders["auditor"].name
  }

  tester_bindings = {
    for pair in setproduct(keys(local.test_sas), var.tester_members) :
    "${pair[0]}|${pair[1]}" => { sa = local.test_sas[pair[0]], member = pair[1] }
  }
}

resource "google_service_account_iam_member" "tester_token_creator" {
  for_each = local.tester_bindings

  service_account_id = each.value.sa
  role               = "roles/iam.serviceAccountTokenCreator"
  member             = each.value.member
}
