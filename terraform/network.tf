resource "google_compute_network" "lab" {
  project                 = var.project_id
  name                    = "lab-vpc"
  auto_create_subnetworks = false
  routing_mode            = "REGIONAL"
  description             = "Security lab VPC (custom mode)"

  depends_on = [google_project_service.apis]
}

resource "google_compute_subnetwork" "private" {
  project                  = var.project_id
  name                     = "lab-private-${var.region}"
  region                   = var.region
  network                  = google_compute_network.lab.id
  ip_cidr_range            = var.subnet_cidr
  private_ip_google_access = true

  log_config {
    aggregation_interval = "INTERVAL_10_MIN"
    flow_sampling        = 0.1
    metadata             = "INCLUDE_ALL_METADATA"
  }
}

resource "google_compute_firewall" "deny_all_ingress" {
  project     = var.project_id
  name        = "lab-deny-all-ingress"
  network     = google_compute_network.lab.id
  direction   = "INGRESS"
  priority    = 65000
  description = "Explicit deny-all ingress with logging"

  deny {
    protocol = "all"
  }

  source_ranges = ["0.0.0.0/0"]

  log_config {
    metadata = "INCLUDE_ALL_METADATA"
  }
}
