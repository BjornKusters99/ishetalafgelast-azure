# Azure-containerhosting voor IsHetAlAfgelast.nl

Onderzoek en uitvoerplan voor migratie van GitHub Pages naar Azure Container
Apps. Start bij [onderzoek-en-uitvoerplan.md](onderzoek-en-uitvoerplan.md).

- `onderzoek-en-uitvoerplan.md`: architectuur, kosten, security, stappen,
  operations en groeipad.
- `architectuur.drawio`: importeerbaar diagrams.net/draw.io-bestand.

## Aanbevolen startpunt

Eén nginx-container in Azure Container Apps Consumption, met statische assets
in dezelfde image, ACR voor private images, GitHub Actions via OIDC, managed
HTTPS voor het domein en Log Analytics voor logs. Geen database of Front Door
bij eerste release. Voeg API, PostgreSQL en eventueel WAF pas toe wanneer een
concrete feature dit nodig maakt.
