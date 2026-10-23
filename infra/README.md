# Azure infrastructure

`main.bicep` maakt testresources:

```text
Log Analytics workspace
Private Azure Container Registry Basic
Azure Container Apps Consumption environment
Azure Container App with public temporary ingress
```

Container App krijgt system-assigned managed identity. Het bootstrapscript
geeft deze identity daarna alleen `AcrPull` op de registry.

Geen database, Key Vault, VNet, Front Door, WAF of custom domain in eerste
iteratie. Voeg die alleen toe met expliciete requirement en kostenbesluit.

Compileer lokaal:

```bash
az bicep build --file infra/main.bicep --stdout >/tmp/ishetalafgelast.json
```
