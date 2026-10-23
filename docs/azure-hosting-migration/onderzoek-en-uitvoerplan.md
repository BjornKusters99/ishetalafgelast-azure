# IsHetAlAfgelast.nl: hosting op Azure Containers

**Onderzoeksdatum:** 23 oktober 2026  
**Scope:** huidige statische site migreren van GitHub Pages naar
containerhosting op Azure, met veilig groeipad naar backend, jobs en database.

## 1. Kort advies

Kies **Azure Container Apps (ACA), Consumption-plan, West Europe**, met één
publieke nginx-container als eerste productie-workload.

Dit voldoet aan de containerwens zonder Kubernetes, VM-beheer of permanent
draaiende server. ACA ondersteunt HTTPS/TCP-ingress, managed secrets, managed
identities, health probes, revisions, traffic splitting en autoscaling. Normale
apps kunnen naar nul replicas schalen.

**Belangrijk:** de huidige site heeft technisch geen container nodig. De app
draait volledig in de browser: geocoding en weer komen van Open-Meteo, het model
draait in `js/model.js`/`js/engine.js`, en er is geen backend of database. Dat
staat in `README.md`. Containerhosting is dus strategische keuze voor
eigenaarschap, CI/CD en toekomstige serverfunctionaliteit, geen directe
performance- of kostenoptimalisatie.

Start klein:

```text
GitHub repo -> GitHub Actions (OIDC) -> private ACR -> ACA web container
                                                     |
                                                     +-> managed TLS + domain
                                                     +-> Log Analytics
```

Voeg pas later toe:

```text
ACA web -> ACA API -> PostgreSQL Flexible Server
                    -> Key Vault / Storage / queues / scheduled jobs
```

Geen Azure Front Door, Application Gateway, AKS of database in fase 1.

## 2. Wat repo nu doet

| Onderdeel | Huidige toestand | Gevolg |
|---|---|---|
| Frontend | Plain HTML, CSS, vanilla JavaScript | Geen framework-build nodig |
| Routing | `/`, `/plaatsen/`, statische HTML | Nginx moet bestaande bestanden direct serveren |
| Data | Browser-call naar Open-Meteo | CSP en CORS blijven controleren |
| Model | Client-side JavaScript | Geen server-runtime nodig |
| Assets | Fonts, WebP/PNG/JPG, manifest, service worker | Alles in image opnemen |
| Generatie | `tools/gen_pages.py` | CI moet gegenereerde pagina's controleren |
| Tests | `tools/e2e.cjs` | In CI draaien vóór image push |
| Backend | Geen | Niet toevoegen zonder concrete feature |
| Domein | `ishetalafgelast.nl` / `www` via GitHub Pages-DNS | Gecontroleerde DNS-cutover nodig |

Huidige lokale wijzigingen zijn buiten scope. Deze documentatie wijzigt geen
appcode en overschrijft bestaand werk niet.

## 3. Hostingopties

### 3.1 Azure Container Apps — aanbevolen

Past bij één webcontainer nu, API/worker later, lage of wisselende belasting,
revisions en eenvoudige blue/green of canary releases.

Sterk: serverless containers, scale-to-zero, revisions, HTTP ingress, internal
ingress voor backend, secrets, managed identity, health probes en Log
Analytics. ACA-environments delen netwerk en logbestemming voor gerelateerde
apps.

Zwak: cold start na scale-to-zero, extra containerconfiguratie en extra
operationele discipline ten opzichte van static hosting.

### 3.2 Azure Static Web Apps

Technisch waarschijnlijk eenvoudigste en goedkoopste keuze voor huidige static
site. Microsoft biedt Free en Standard-plannen en custom domains. Niet gekozen
als primaire route omdat opdracht expliciet containerhosting en een
container-native groeipad vraagt.

### 3.3 Storage Static Website + CDN

Goedkoop en robuust voor immutable assets, maar geen container-runtime. Niet
gekozen voor deze opdracht.

### 3.4 App Service for Containers

Goed voor een altijd-aan webapp met traditionele App Service-operatie. Minder
passend bij scale-to-zero en meerdere kleine workloads.

### 3.5 Container Instances

Geschikt voor korte, eenvoudige container-runs; minder geschikt als primaire
productiewebhosting met revisions, ingress en observability.

### 3.6 AKS

Overkill. Clusterbeheer en vaste infrastructuurkosten leveren nu geen waarde.

## 4. Doelarchitectuur

### Fase 1: containerized static web

1. GitHub blijft broncode-host en CI/CD-trigger; GitHub Pages wordt niet meer
   de runtime-host.
2. GitHub Actions voert generator, tests en Docker build uit.
3. Image krijgt immutable tag `${GITHUB_SHA}`, niet `latest`.
4. Image gaat naar private Azure Container Registry (ACR).
5. ACA trekt image via system-assigned managed identity met alleen `AcrPull`.
6. Nginx serveert `/app` op poort 8080.
7. ACA externe HTTP-ingress ontvangt verkeer.
8. Het domein wijst naar ACA; ACA levert gratis managed certificate onder de
   DNS-validatievoorwaarden.
9. Environment stuurt logs naar Log Analytics.

Containerimage minimaal:

```dockerfile
FROM nginx:alpine
COPY . /usr/share/nginx/html
COPY deploy/nginx.conf /etc/nginx/conf.d/default.conf
EXPOSE 8080
```

Nginx moet `index.html`, `404.html`, `/plaatsen/`, fonts, images, JavaScript,
manifest en service worker correct serveren. Voeg security headers toe via
nginx; behoud en corrigeer CSP in `index.html` en `tools/gen_pages.py`.

### Fase 2: server-side API

Voeg een tweede ACA-app toe: `ishetalafgelast-api` met internal ingress. Begin
met één use case, bijvoorbeeld server-side weather caching, admin data of
feedback. ACA adviseert internal ingress voor apps die alleen door andere
Container Apps worden aangeroepen:
<https://learn.microsoft.com/en-us/azure/container-apps/ingress-overview>.

### Fase 3: data en jobs

Gebruik **Azure Database for PostgreSQL Flexible Server** wanneer data
server-side moet blijven, bijvoorbeeld clubs, locaties, wedstrijdmeldingen,
moderatie of historische modeluitkomsten. Gebruik voor geplande imports of
modelupdates een ACA Job of aparte worker, niet een cronproces in nginx.

### Fase 4: zwaardere perimeter

Voeg Azure Front Door Premium met WAF alleen toe bij concrete behoefte aan
globale edge-routing, botbescherming, WAF-regels, meerdere origins of private
origin. Voor deze kleine site zijn kosten en complexiteit in fase 1 niet
gerechtvaardigd.

## 5. Stapsgewijze uitvoering

### Stap 0 — voorbereiding

- [ ] Azure-subscription en billing owner bevestigen.
- [ ] Regio kiezen: `westeurope`, tenzij beleid anders vereist.
- [ ] Namen vastleggen: `rg-ishetalafgelast-prod`,
  `cae-ishetalafgelast-prod`, `ca-ishetalafgelast-web`, unieke registry.
- [ ] Tags instellen: `application`, `environment`, `owner`, `costCenter`.
- [ ] DNS-provider en huidige TTL noteren.
- [ ] Geen secrets in repo, image of logs zetten.

### Stap 1 — lokaal reproduceerbare container

- [ ] `Dockerfile` toevoegen.
- [ ] `.dockerignore` toevoegen voor `.git`, lokale dependencies, test-output
  en niet-publieke bronbestanden.
- [ ] Nginx config toevoegen met poort 8080, security headers en error page.
- [ ] Test met `docker build` en `docker run -p 8080:8080`.
- [ ] Controleer homepage, plaatsindex, deep links, service worker, manifest,
  fonts, Open-Meteo calls en share-links.
- [ ] `tools/e2e.cjs` in CI uitvoeren.

### Stap 2 — Azure basisresources

Gebruik Bicep of Terraform, niet losse portal-clicks als enige bron van waarheid.
Minimaal:

```text
Resource group
Container Apps environment (Consumption workload profile)
Log Analytics workspace
Azure Container Registry (private, Basic voor start)
Container App
Budget + cost alerts
```

Gebruik aparte resource groups of minimaal aparte environments voor `dev` en
`prod`. ACA ondersteunt ARM/YAML/Bicep; gebruik actuele API-versies.

### Stap 3 — identity en registry

- [ ] System-assigned identity op ACA-app activeren.
- [ ] Alleen `AcrPull` op ACR geven.
- [ ] ACR admin user uit laten.
- [ ] Registry pull via managed identity configureren.

Managed identity voorkomt registry-wachtwoorden in app-config. Bronnen:
<https://learn.microsoft.com/en-us/azure/container-apps/managed-identity> en
<https://learn.microsoft.com/en-us/azure/container-registry/container-registry-authentication-managed-identity>.

### Stap 4 — eerste image handmatig deployen

Doel: infrastructuur valideren vóór CI/CD.

```bash
az login
az account set --subscription '<SUBSCRIPTION_ID>'
az extension add --name containerapp --upgrade

az acr build \
  --registry '<ACR_NAME>' \
  --image 'ishetalafgelast:<GIT_SHA>' \
  .

az containerapp show \
  --name 'ca-ishetalafgelast-web' \
  --resource-group 'rg-ishetalafgelast-prod'
```

Deploy alleen image-tags die naar commit-SHA verwijzen. Controleer revision,
readiness, HTTP-statussen, logs en browsergedrag.

### Stap 5 — CI/CD met GitHub OIDC

Gebruik federated identity/OIDC, niet langlevende JSON
service-principal-credentials. Azure Login ondersteunt OIDC met
`AZURE_CLIENT_ID`, `AZURE_TENANT_ID` en `AZURE_SUBSCRIPTION_ID`; workflow heeft
`id-token: write` nodig:
<https://learn.microsoft.com/en-us/azure/developer/github/connect-from-azure-openid-connect>.

Workflow:

```text
push main
 -> checkout
 -> generator / lint / E2E
 -> docker build
 -> vulnerability scan
 -> login Azure via OIDC
 -> push ACR:<commit-sha>
 -> deploy ACA revision
 -> smoke test ACA URL
 -> optioneel production approval
```

ACA heeft een officiële GitHub Action. Gebruik unieke SHA-tags boven `latest`:
<https://learn.microsoft.com/en-us/azure/container-apps/github-actions>.

Beperk workflow permissions tot `contents: read` en `id-token: write`. Gebruik
GitHub Environment `production` met reviewer approval.

### Stap 6 — domein migreren met rollback

1. Test via tijdelijke `*.azurecontainerapps.io`-URL.
2. Custom domain en DNS-validatie voorbereiden.
3. TTL 24–48 uur vóór cutover verlagen.
4. `www` als CNAME naar ACA FQDN; apex via A-record naar ACA environment
   static IP, plus `asuid` TXT-validatie.
5. Managed certificate binden en HTTPS controleren.
6. Eén canonical host kiezen; de andere host 301 redirecten.
7. DNS wijzigen buiten piekperiode.
8. Smoke-test via meerdere resolvers en mobiele verbinding.
9. GitHub Pages pas verwijderen na rollbackvenster.

ACA managed certificates zijn gratis en automatisch vernieuwbaar, maar vereisen
publieke bereikbaarheid en specifieke DNS-records. Bronnen:
<https://learn.microsoft.com/en-us/azure/container-apps/custom-domains-managed-certificates>.

**Rollback:** DNS terugzetten naar oude GitHub Pages-records en oude deployment
behouden. DNS-cache betekent dat beide hosts tijdens propagatie verkeer kunnen
ontvangen.

### Stap 7 — monitoring

- [ ] Log Analytics koppelen.
- [ ] Alerts op 5xx, failed revisions, probe failures en image-pull errors.
- [ ] Dashboard voor requests, latency, statuscodes en replica count.
- [ ] Uptime smoke-check op homepage, `/plaatsen/` en één plaats.
- [ ] Maandbudget instellen.
- [ ] Logretentie instellen passend bij privacy en kosten.
- [ ] Geen tokens of persoonsgegevens in logs/querystrings.

ACA levert console-, system- en HTTP-logs via Log Analytics. HTTP-logs kunnen
client-IP en URL bevatten; behandel die als persoonsgegevens:
<https://learn.microsoft.com/en-us/azure/container-apps/log-monitoring>.

Azure budgets zijn signalen, geen harde spend cap. Maak daarom budgetalerts én
resource-/deploymentdiscipline:
<https://learn.microsoft.com/en-us/azure/cost-management-billing/costs/tutorial-acm-create-budgets>.

## 6. Security-baseline

### Container

- Gebruik kleine, gepinde base image waar praktisch; rebuild voor patches.
- Run nginx niet als root wanneer image/config dit toelaten.
- Gebruik immutable SHA-tags; geen `latest` in productie.
- Scan images vóór push/deploy.
- Publiceer alleen runtime-assets; geen `.git`, testdata of trainingsdata.
- Voeg ACA startup/readiness/liveness probes toe op lichte endpoints.

ACA ondersteunt startup, readiness en liveness probes; readiness is belangrijk
vóór traffic shift:
<https://learn.microsoft.com/en-us/azure/container-apps/health-probes>.

### Identity en secrets

- GitHub Actions: OIDC + least-privilege federated identity.
- ACA -> ACR: alleen pull.
- Backend later: system-assigned identity per app; RBAC per resource.
- Secrets later in Key Vault; app gebruikt Key Vault reference.
- Geen database-credentials in Git, image, frontend JavaScript of URL.

ACA ondersteunt Key Vault-references via managed identity. Brede Container Apps-
rollen kunnen `listSecrets` toelaten; vermijd wildcard-permissions:
<https://learn.microsoft.com/en-us/azure/container-apps/manage-secrets>.

### HTTP en browser

- HTTPS afdwingen; HTTP redirect naar canonical HTTPS.
- CSP beperken tot eigen origin en expliciete Open-Meteo-hosts.
- `X-Content-Type-Options: nosniff`, `Referrer-Policy`, HSTS pas na HTTPS-
  validatie.
- CORS alleen op API, met expliciete origins; geen `*` met credentials.
- Rate-limit en inputvalidatie zodra publieke API ontstaat.
- Analytics alleen na privacybesluit en bijgewerkte CSP/privacytekst.

### Data/privacy

Huidige frontend stuurt plaatszoekopdrachten rechtstreeks naar Open-Meteo. Een
backend kan caching bieden, maar maakt server-side logging en privacy groter.
Sla geen volledige IP-adressen, zoekhistorie of gebruikersdata op zonder doel,
grondslag, retentiebeleid en privacytekst.

## 7. Databasebesluit

### Nu: niet doen

Geen DB nodig voor huidige functionaliteit. Een ongebruikte PostgreSQL-server
kost geld, vraagt backupbeleid en vergroot attack surface.

### Later: PostgreSQL Flexible Server

Kies PostgreSQL als data relationeel is en queries/constraints belangrijk zijn.
Productiepatroon:

```text
public web -> ACA API -> PostgreSQL (private access)
                    -> Key Vault secret reference / managed identity
```

Database niet direct publiek maken. Configureer backups, point-in-time restore,
TLS, connection pooling/PgBouncer en migraties in CI/CD. Begin development met
single-zone/non-HA; productie-HA vereist een expliciet beschikbaarheidsdoel.

PostgreSQL Flexible Server ondersteunt automatische backups met standaard zeven
dagen retentie, uitbreidbaar tot 35 dagen, TLS 1.2+, private VNet-access en
burstable compute:
<https://learn.microsoft.com/en-us/azure/postgresql/overview>.

## 8. Kostenraming

Bedragen zijn indicatieve USD retailprijzen vóór belasting, West Europe,
gecontroleerd via Microsoft Retail Prices API op 23 oktober 2026. Werkelijke
prijs varieert door regio, valuta, contract, traffic, egress, logs en credits.
Gebruik vóór provisioneren de calculator:
<https://azure.microsoft.com/en-us/pricing/calculator/>.

### Fase 1: static container

ACA Consumption geeft per subscription per kalendermaand gratis:

- 180.000 vCPU-seconden;
- 360.000 GiB-seconden;
- 2 miljoen HTTP-requests.

Bij nul replicas zijn geen resource-consumptionkosten. Bron:
<https://learn.microsoft.com/en-us/azure/container-apps/billing>.

West-Europe retail-meters:

| Meter | Indicatieve prijs |
|---|---:|
| ACA standard vCPU active | $0,000034 per vCPU-seconde |
| ACA standard memory active | $0,000004 per GiB-seconde |
| ACA HTTP requests | $0,56 per miljoen requests |
| ACA vCPU idle | $0,000004 per vCPU-seconde |
| ACA memory idle | $0,000004 per GiB-seconde |
| Log Analytics analyzed | ongeveer $2,30/GB; actuele meters controleren |
| ACR Basic | ongeveer $0,167/dag = circa $5,10/30 dagen, plus storage/egress |

Voorbeeld 0,25 vCPU + 0,5 GiB, één replica, continu 30 dagen, vóór gratis
grant:

```text
vCPU: 0,25 × 2.592.000 sec × $0,000034 = $22,03
RAM:  0,5  × 2.592.000 sec × $0,000004 = $5,18
Totaal compute vóór grant                         $27,21
```

Dit is always-on, niet de verwachte scale-to-zero-belasting. Een kleine site
kan vaak rond **ACR + beperkte logs + weinig ACA compute** blijven. Exact bedrag
volgt pas uit echte uptime, replicas, requests en logvolume.

### Fase 2: API zonder DB

Voeg API compute en requests toe. `minReplicas: 0` beperkt kosten; minimum één
replica verlaagt cold start maar veroorzaakt continue kosten.

### Fase 3: PostgreSQL

PostgreSQL is grootste vaste kostenrisico. Azure publiceert prijzen per regio
en SKU; gebruik calculator voor burstable, storage, backup, network en HA.
Reken grofweg op **tientallen dollars per maand** voor een kleine draaiende
managed server, exclusief network/backup/HA. Niet provisioneren zonder schema
en feature.

### Optionele perimeter

Front Door Standard/Premium, WAF, private endpoints, VNet-infrastructuur,
Application Gateway en Defender kunnen de rekening sterk verhogen. Front Door
Premium is geen standaardkeuze voor deze site:
<https://learn.microsoft.com/en-us/azure/frontdoor/understanding-pricing>.

### Kostenmaatregelen

- Consumption profile, `minReplicas: 0` waar cold start acceptabel is.
- Productie-environment apart; dev-apps alleen delen als isolatie volstaat.
- Logretentie en HTTP logging beperken.
- Oude ACR image-tags/digests opruimen.
- Budgetalerts op resource group én subscription.
- PostgreSQL dev stoppen wanneer mogelijk.
- Geen HA/private endpoint/Front Door zonder expliciete requirement.

## 9. Release, rollback en herstel

Releasepad:

```text
PR -> generator/tests/scan -> image SHA -> ACR -> ACA revision
   -> readiness -> smoke test -> traffic switch -> monitor
```

Risicovolle release: multiple revisions met bijvoorbeeld 5% -> 25% -> 100%.

Rollback:

- App-regressie: traffic terug naar vorige gezonde revision.
- Image-probleem: vorige SHA opnieuw activeren.
- DNS-probleem: DNS terug naar GitHub Pages.
- Datamigratieprobleem: backward-compatible schema; restore gecontroleerd.

Leg vóór DB/productie vast:

```text
RTO: hoeveel tijd mag herstel kosten?
RPO: hoeveel data mag verloren gaan?
Beschikbaarheid: welk percentage is nodig?
```

## 10. Acceptatiecriteria

Migratie is klaar als:

- bestaande URL's, canonical URLs en redirects werken;
- homepage, plaatsindex, alle deep links, 404, manifest en service worker werken;
- weer- en geocoding-API werken onder CSP/CORS;
- HTTPS geldig is op apex en canonical host;
- ACA revision readiness groen is;
- GitHub Actions zonder statische Azure-secret deployt;
- ACR pull via managed identity werkt;
- logs en alerts zichtbaar zijn;
- budgetalert bestaat;
- vorige hosting één rollbackperiode beschikbaar blijft;
- privacytekst niet meer claimt dat hosting op GitHub Pages draait.

## 11. Niet doen in eerste iteratie

- Geen AKS-cluster, VM of handmatig Dockerbeheer.
- Geen PostgreSQL “voor later”.
- Geen Front Door Premium zonder WAF/edge-eis.
- Geen publieke database.
- Geen GitHub JSON credentials.
- Geen `latest` als productieidentifier.
- Geen frontend API keys of databasecredentials.

## 12. Primaire bronnen

1. ACA overview — <https://learn.microsoft.com/en-us/azure/container-apps/overview>
2. ACA environments — <https://learn.microsoft.com/en-us/azure/container-apps/environment>
3. ACA billing — <https://learn.microsoft.com/en-us/azure/container-apps/billing>
4. Health probes — <https://learn.microsoft.com/en-us/azure/container-apps/health-probes>
5. Managed identity — <https://learn.microsoft.com/en-us/azure/container-apps/managed-identity>
6. Security — <https://learn.microsoft.com/en-us/azure/container-apps/security>
7. Secrets — <https://learn.microsoft.com/en-us/azure/container-apps/manage-secrets>
8. Custom domain/TLS — <https://learn.microsoft.com/en-us/azure/container-apps/custom-domains-managed-certificates>
9. GitHub Actions — <https://learn.microsoft.com/en-us/azure/container-apps/github-actions>
10. GitHub OIDC — <https://learn.microsoft.com/en-us/azure/developer/github/connect-from-azure-openid-connect>
11. Logs — <https://learn.microsoft.com/en-us/azure/container-apps/log-monitoring>
12. Ingress — <https://learn.microsoft.com/en-us/azure/container-apps/ingress-overview>
13. Jobs — <https://learn.microsoft.com/en-us/azure/container-apps/jobs>
14. PostgreSQL — <https://learn.microsoft.com/en-us/azure/postgresql/overview>
15. ACR identity — <https://learn.microsoft.com/en-us/azure/container-registry/container-registry-authentication-managed-identity>
16. Static Web Apps plans — <https://learn.microsoft.com/en-us/azure/static-web-apps/plans>
17. Front Door pricing — <https://learn.microsoft.com/en-us/azure/frontdoor/understanding-pricing>
18. Azure budgets — <https://learn.microsoft.com/en-us/azure/cost-management-billing/costs/tutorial-acm-create-budgets>
19. Retail Prices API — <https://prices.azure.com/api/retail/prices>

Prijsdata is momentopname. Herbereken met subscription, regio, currency,
traffic, logs en commitment vóór aankoop.
