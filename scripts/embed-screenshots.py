#!/usr/bin/env python3
"""Вставляет скриншоты из evidence/screenshots/ в документы (идемпотентно). Запуск из корня репозитория."""
import re, pathlib

S = "evidence/screenshots/"
CAP = {
 "01-vpc-before-default.jpg": "До: default VPC (auto-mode, 42 подсети)",
 "02-firewall-before.jpg": "До: default-allow-ssh/rdp из интернета",
 "03-vpc-after-lab-vpc-only.jpg": "После: остался только lab-vpc",
 "04-bucket-objects.jpg": "Bucket: синтетические данные internal/ и confidential/",
 "05-bucket-permissions.jpg": "Bucket: права, Public Access Prevention, UBLA",
 "06-bucket-protection.jpg": "Bucket: versioning, soft delete, retention",
 "07-bucket-config.jpg": "Bucket: метки, шифрование, lifecycle",
 "08-alert-policies.jpg": "Alert policies (log-based)",
 "09-log-router.jpg": "Log Router: sink audit-to-security-bucket",
 "10-budget.png": "Бюджет 10 USD с порогами 50/90/100%",
 "11-iam-principals.png": "IAM: итоговые principals проекта",
 "12a-audit-storage.png": "Audit config: Cloud Storage",
 "12b-audit-iam.png": "Audit config: IAM API",
 "13-log-bucket-retention.png": "Log bucket security-audit: retention 30 дней",
 "19-email-alerts.png": "Письма алертов",
 "19-email-alerts-phone.png": "Уведомления алертов на телефоне",
}
root = pathlib.Path(".")

def img(name, rel):
    return f"![{CAP[name]}]({rel}{S}{name})\n\n*{CAP[name]}*\n"

def gallery(file, heading, names):
    p = root / file
    t = p.read_text(encoding="utf-8")
    marker = "<!-- screenshots:" + heading + " -->"
    if marker in t:
        return
    rel = "../" * (len(pathlib.Path(file).parts) - 1)
    body = "\n".join(img(n, rel) for n in names)
    p.write_text(t.rstrip("\n") + f"\n\n{marker}\n## {heading}\n\n{body}", encoding="utf-8")

# инциденты: картинки в раздел «Доказательства»
inc = {
 "incidents/incident-01.md": ["19-email-alerts.png", "19-email-alerts-phone.png"],
 "incidents/incident-02.md": ["19-email-alerts.png", "05-bucket-permissions.jpg", "07-bucket-config.jpg"],
 "incidents/incident-03.md": ["19-email-alerts.png"],
 "incidents/incident-04.md": ["19-email-alerts.png", "12a-audit-storage.png", "12b-audit-iam.png"],
 "incidents/incident-05.md": ["19-email-alerts.png", "11-iam-principals.png"],
 "incidents/incident-06.md": ["02-firewall-before.jpg"],
}
for f, names in inc.items():
    gallery(f, "Скриншоты", names)

gallery("docs/storage-security.md", "Скриншоты", ["04-bucket-objects.jpg", "05-bucket-permissions.jpg", "06-bucket-protection.jpg", "07-bucket-config.jpg"])
gallery("docs/iam-review.md", "Скриншоты", ["11-iam-principals.png"])
gallery("docs/lab-journal.md", "Скриншоты", ["01-vpc-before-default.jpg", "02-firewall-before.jpg", "03-vpc-after-lab-vpc-only.jpg", "09-log-router.jpg", "10-budget.png"])
gallery("reports/final-report.md", "Приложение A. Скриншоты", list(CAP))
gallery("README.md", "Скриншоты", ["03-vpc-after-lab-vpc-only.jpg", "07-bucket-config.jpg", "09-log-router.jpg", "19-email-alerts.png"])

# мелкие исправления
p = root / "docs/iam-review.md"
t = p.read_text(encoding="utf-8").replace("05-bucket-permissions.png", "05-bucket-permissions.jpg")
p.write_text(t, encoding="utf-8")
p = root / "evidence/screenshots/README.md"
t = p.read_text(encoding="utf-8")
t = re.sub(r"(?<!\\)`SEC \|`", r"`SEC \\|`", t).replace("`SEC |` log-based", "`SEC \\|` log-based")
p.write_text(t, encoding="utf-8")
print("Готово: скриншоты вставлены.")
