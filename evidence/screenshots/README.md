# Evidence: screenshots

| File | What it proves | Reproducible check |
|---|---|---|
| 01-vpc-before-default.jpg | Before hardening: `default` auto-mode VPC (42 subnets) exists | `gcloud compute networks list` |
| 02-firewall-before.jpg | Before hardening: default-allow-ssh (22) / rdp (3389) from internet; `lab-deny-all-ingress` on lab-vpc | `gcloud compute firewall-rules list` |
| 03-vpc-after-lab-vpc-only.jpg | After: only `lab-vpc` (custom mode) remains | `scripts/verify.sh` (Network section) |
| 04-bucket-objects.jpg | Bucket holds `internal/` and `confidential/` synthetic data | `gcloud storage ls gs://$BUCKET/**` |
| 05-bucket-permissions.jpg | Public access prevented; UBLA; sa-app-reader = objectViewer; legacy project roles inherited (finding) | `gcloud storage buckets get-iam-policy gs://$BUCKET` |
| 06-bucket-protection.jpg | Versioning on, soft delete off, no retention policy | `gcloud storage buckets describe gs://$BUCKET` |
| 07-bucket-config.jpg | Labels, UBLA, PAP enforced, Google-managed encryption, 3 lifecycle rules | `scripts/verify.sh` (Storage section) |
| 08-alert-policies.jpg | 6 `SEC |` log-based alert policies enabled | `terraform/monitoring.tf` |
| 09-log-router.jpg | Sink `audit-to-security-bucket` routes audit logs to `security-audit` | `gcloud logging sinks list` |
| 10-budget.png | Budget `sec-lab-budget` (monthly, thresholds 50/90/100%); alerts only, no spend cap | Billing > Budgets & caps |
| 11-iam-principals.png | Only the lab owner has a basic role; Editor removed from default compute SA | `evidence/sanitized-logs/iam-basic-roles-after.txt` |
| 12a-audit-storage.png | Storage: Admin read / Data read / Data write enabled, 0 exempted principals | `gcloud projects get-iam-policy --format="json(auditConfigs)"` |
| 12b-audit-iam.png | IAM API: Admin read / Data read / Data write enabled, 0 exempted principals | same as above |
| 13-log-bucket-retention.png | `security-audit` retention = 30 days | `evidence/sanitized-logs/log-bucket-retention.txt` |
| 19-email-alerts.png | Alert emails fired for IR scenarios (Gmail times are UTC+2) | Monitoring > Alerting > Incidents |
| 19-email-alerts-phone.png | Same alerts as phone notifications (backup) | same |

