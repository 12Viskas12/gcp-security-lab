locals {
  # Единая система маркировки. Классификация данных задаётся на ресурсе отдельно.
  common_labels = merge(
    {
      environment = "lab"
      managed_by  = "terraform"
      project     = "gcp-security-lab"
      owner       = var.owner_label
    },
    var.extra_labels
  )

  required_apis = toset([
    "compute.googleapis.com",
    "iam.googleapis.com",
    "iamcredentials.googleapis.com",
    "cloudresourcemanager.googleapis.com",
    "serviceusage.googleapis.com",
    "logging.googleapis.com",
    "monitoring.googleapis.com",
    "storage.googleapis.com",
    "billingbudgets.googleapis.com",
    "cloudbilling.googleapis.com",
    "cloudasset.googleapis.com",
  ])
}

data "google_project" "this" {
  project_id = var.project_id
}

resource "google_project_service" "apis" {
  for_each = local.required_apis

  project            = var.project_id
  service            = each.value
  disable_on_destroy = false
}
