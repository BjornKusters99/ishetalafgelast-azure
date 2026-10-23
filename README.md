# IsHetAlAfgelast.nl — Azure testrepo

Parallelle bouwrepo voor Azure Container Apps. Bestaande productie-site en
GitHub Pages-repository blijven ongemoeid en live.

## Status

- App gekopieerd uit huidige site, inclusief lokale wijzigingen.
- Docker/nginx-container en Azure Container Apps Consumption-infra toegevoegd.
- Private ACR + system-assigned managed identity + `AcrPull` voorbereid.
- CI valideert generatie, E2E en container smoke tests.
- Testdeploy uitsluitend handmatig via GitHub Actions.
- Geen productie-DNS, custom domain, Pages-wijziging of automatische deploy.

## Lokaal testen

Vereist: Docker, Python 3 en Node.js 22.

```bash
npm ci
python3 tools/gen_pages.py
git diff --exit-code
docker build --tag ishetalafgelast:test .
npm run test:container
```

Browser-E2E vereist Chromium:

```bash
npx playwright install chromium
python3 -m http.server 8765
# tweede terminal
CHROME="$(node -e "console.log(require('playwright').chromium.executablePath())")" \
  BASE=http://127.0.0.1:8765 node tools/e2e.cjs
```

## Azure testomgeving handmatig aanmaken

Vereist: Azure CLI, Bicep, `jq`, Azure-subscription met voldoende rechten.
Dit maakt alleen aparte testresources; het wijzigt geen DNS.

```bash
az login
az account set --subscription '<SUBSCRIPTION_ID>'
export ACR_NAME='<globally-unique-lowercase-name>'
export RESOURCE_GROUP='rg-ishetalafgelast-test'
export LOCATION='westeurope'
./scripts/bootstrap-test.sh
```

Daarna bouwen en pushen:

```bash
az acr build \
  --registry "$ACR_NAME" \
  --image "ishetalafgelast:manual-test" \
  .

az containerapp update \
  --name 'ca-ishetalafgelast-test' \
  --resource-group "$RESOURCE_GROUP" \
  --image "$ACR_NAME.azurecr.io/ishetalafgelast:manual-test"
```

## Handmatige GitHub testdeploy

Maak GitHub Environment `azure-test` en configureer deze **variables**:

```text
AZURE_CLIENT_ID
AZURE_TENANT_ID
AZURE_SUBSCRIPTION_ID
AZURE_ACR_NAME
AZURE_RESOURCE_GROUP
AZURE_CONTAINER_APP=ca-ishetalafgelast-test
```

Configureer federated credentials voor GitHub OIDC. Geef identity alleen
minimale deploymentrechten. Workflow gebruikt geen statische Azure-JSON
credentials.

Benodigde scope: `AcrPush` op ACR en `Container Apps Contributor` op de test-
resource group. Geef de identity geen subscription-brede Owner-rol.

Start `.github/workflows/deploy-test.yml` handmatig op `main` met input
`deploy-test`. Workflow deployt commit-SHA naar tijdelijke ACA-app en print
test-URL. Push naar `main` deployt niet.

## Azure infrastructure

- `infra/main.bicep`: Log Analytics, private Basic ACR, ACA environment en web
  Container App met external HTTPS ingress, probes en scale-to-zero.
- `deploy/nginx.conf`: unprivileged nginx, security headers, `/healthz` en
  noindex-header voor testomgeving.
- `scripts/bootstrap-test.sh`: resource group + Bicep + managed identity pull
  permission.

Geen database in deze fase. PostgreSQL, API, Key Vault en jobs volgen pas na
concreet feature- en datamodelbesluit. Zie uitvoerplan in `docs/`.

## App

Browser-side app remains unchanged from source repo. Azure work is isolated to
container, infrastructure and deployment tooling. Productie blijft op huidige
hosting totdat aparte cutover wordt goedgekeurd.
