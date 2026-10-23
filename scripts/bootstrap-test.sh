#!/usr/bin/env bash
set -euo pipefail

RESOURCE_GROUP="${RESOURCE_GROUP:-rg-ishetalafgelast-test}"
LOCATION="${LOCATION:-westeurope}"
APP_NAME="${APP_NAME:-ca-ishetalafgelast-test}"
ENVIRONMENT_NAME="${ENVIRONMENT_NAME:-cae-ishetalafgelast-test}"

if [[ -z "${ACR_NAME:-}" ]]; then
  echo "Set ACR_NAME to a globally unique lowercase registry name." >&2
  exit 1
fi

if [[ ! "${ACR_NAME}" =~ ^[a-z0-9]{5,50}$ ]]; then
  echo "ACR_NAME must contain 5-50 lowercase letters or digits." >&2
  exit 1
fi

az account show >/dev/null
az bicep version >/dev/null

az group create \
  --name "${RESOURCE_GROUP}" \
  --location "${LOCATION}" \
  --output none

deployment=$(az deployment group create \
  --resource-group "${RESOURCE_GROUP}" \
  --name ishetalafgelast-bootstrap \
  --template-file infra/main.bicep \
  --parameters \
    location="${LOCATION}" \
    registryName="${ACR_NAME}" \
    appName="${APP_NAME}" \
    environmentName="${ENVIRONMENT_NAME}" \
  --output json)

principal_id=$(jq -r '.properties.outputs.appPrincipalId.value' <<<"${deployment}")
registry_id=$(jq -r '.properties.outputs.registryId.value' <<<"${deployment}")
login_server=$(jq -r '.properties.outputs.registryLoginServer.value' <<<"${deployment}")

assignment_count=$(az role assignment list \
  --assignee "${principal_id}" \
  --scope "${registry_id}" \
  --role AcrPull \
  --query 'length(@)' \
  --output tsv)

if [[ "${assignment_count}" == "0" ]]; then
  az role assignment create \
    --assignee "${principal_id}" \
    --assignee-principal-type ServicePrincipal \
    --role AcrPull \
    --scope "${registry_id}" \
    --output none
fi

az containerapp registry set \
  --name "${APP_NAME}" \
  --resource-group "${RESOURCE_GROUP}" \
  --server "${login_server}" \
  --identity system \
  --output none

fqdn=$(jq -r '.properties.outputs.appFqdn.value' <<<"${deployment}")
printf 'Test app bootstrap complete: https://%s\n' "${fqdn}"
printf 'Next: configure GitHub OIDC and run Deploy test environment manually.\n'
