#!/usr/bin/env bash
set -uo pipefail
: "${PROJECT_ID:?Задай PROJECT_ID}"

echo "== terraform plan (дрейф управляемых ресурсов) =="
( cd terraform && terraform plan -detailed-exitcode -input=false -lock=false >/dev/null 2>&1 ); rc=$?
case $rc in
  0) echo "[ OK ] Дрейфа управляемых ресурсов нет" ;;
  2) echo "[DRIFT] terraform plan показывает изменения: запусти 'cd terraform && terraform plan'" ;;
  *) echo "[ERR ] terraform plan завершился с ошибкой (код $rc)" ;;
esac

echo
echo "== Cloud Asset Inventory: ресурсы проекта (тип, имя) =="
gcloud asset search-all-resources --scope="projects/${PROJECT_ID}" \
  --format='table(assetType.basename(), displayName, location)' \
  --asset-types='compute.googleapis.com/Firewall,compute.googleapis.com/Network,compute.googleapis.com/Subnetwork,compute.googleapis.com/Instance,compute.googleapis.com/Address,storage.googleapis.com/Bucket,iam.googleapis.com/ServiceAccount' 2>&1

echo
echo "Ожидаемые ресурсы: см. docs/asset-registry.md. Всё, чего там нет, расследуется по runbooks/unexpected-resource.md."
