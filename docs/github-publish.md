# Публикация на GitHub пошагово

Имя репозитория: `gcp-security-hard-lab`. Сначала **Private**; Public — после проверки на секреты и очистки evidence.

## Шаг 1. Пустой репозиторий

github.com → **New repository** → `gcp-security-hard-lab`, **без** README/.gitignore/лицензии (они уже есть).

## Шаг 2. Git локально

```bash
cd gcp-security-hard-lab
git init -b main
git config user.name "Твоё Имя"
git config user.email "ID+LOGIN@users.noreply.github.com"      # GitHub → Settings → Emails
```

## Шаг 3. Очистка evidence и проверка секретов (обязательно)

```bash
export PROJECT_ID=...
# для каждого сырого файла: очистка и просмотр глазами
bash scripts/sanitize.sh evidence/raw/FILE > evidence/sanitized-logs/FILE.txt
grep -rniE 'gmail|@|[0-9]{1,3}(\.[0-9]{1,3}){3}|sec-lab-' evidence/sanitized-logs docs incidents reports | head -50   # остатки
bash scripts/pre-push-check.sh
```

Скриншоты содержат email, project ID и иногда сторонние проекты: закрой их (замазка/обрезка) до коммита. Никакого `terraform.tfvars` и `*.tfstate` в репозитории.

## Шаг 4. Коммиты по этапам

```bash
git add README.md .gitignore .github scripts docs/00-step-by-step.md docs/github-publish.md
git commit -m "chore: repository skeleton, CI and helper scripts"

git add terraform/versions.tf terraform/providers.tf terraform/variables.tf terraform/main.tf terraform/network.tf terraform/outputs.tf terraform/terraform.tfvars.example terraform/backend.tf.example terraform/.terraform.lock.hcl
git commit -m "feat(infra): custom VPC, required APIs, labels, outputs"

git add terraform/storage.tf docs/storage-security.md
git commit -m "feat(storage): hardened bucket (UBLA, PAP, versioning, lifecycle)"

git add terraform/iam.tf docs/iam-review.md
git commit -m "feat(iam): least-privilege roles via role-holder service accounts, no keys"

git add terraform/logging.tf terraform/monitoring.tf detections
git commit -m "feat(detection): audit configs, log bucket, seven log-based alerts, queries"

git add docs/architecture.md docs/asset-registry.md docs/threat-model.md docs/terraform-ops.md evidence/architecture.png evidence/data-flow.png
git commit -m "docs: architecture, asset registry, threat model, terraform operations"

git add incidents runbooks evidence/screenshots evidence/sanitized-logs evidence/README.md
git commit -m "docs(ir): six investigations, runbooks, tabletop, evidence"

git add compliance reports docs/lab-journal.md
git commit -m "docs: ISO 27001 matrix, final report, lab journal"
```

Перед каждым коммитом смотри `git status` и `git diff --staged`.

## Шаг 5. Push

HTTPS (нужен Personal Access Token с правом Contents: Read and write только для этого репозитория):

```bash
git remote add origin https://github.com/ЛОГИН/gcp-security-hard-lab.git
git push -u origin main
```

Или GitHub CLI: `gh auth login && gh repo create gcp-security-hard-lab --private --source=. --remote=origin --push`.

## Шаг 6. Настройки

Settings → Code security: **Secret scanning**, **Push protection**, Dependabot alerts. Settings → Branches: защита `main` (PR + статус-проверки `terraform`, `secrets`). Вкладка Actions: workflow `ci` зелёный.

## Шаг 7. Если секрет попал в историю

Немедленно **отозвать** секрет (ключ SA, токен); очистить историю (`git filter-repo`/BFG), force-push; описать как инцидент в отчёте.

## Шаг 8. Оформление

Описание: `GCP Cloud Security lab: Terraform, IAM, audit logging, detection, IR, ISO 27001`. Topics: `gcp`, `terraform`, `cloud-security`, `incident-response`, `iso27001`, `devsecops`. Перед Public: пройди все файлы и картинки глазами.
