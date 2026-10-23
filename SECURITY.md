# Security policy

Meld beveiligingsproblemen niet publiek in GitHub Issues. Gebruik GitHub's
private security advisory-flow.

Nooit committen:

- Azure client secrets, service-principal JSON of tokens;
- databasewachtwoorden of connection strings;
- productie-DNS-, certificaat- of private-keymateriaal;
- persoonlijke gegevens of echte productie-logs.

Testomgeving gebruikt `noindex` en geen custom domain. Verwijder testresources
na testen om onnodige kosten te voorkomen.
