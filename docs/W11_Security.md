# W11 Security in der Pipeline

## Teil A: Prognose (vor dem ersten Scan)

| Werkzeug | Erwartete Funde | Warum |
|---|---|---|
| Abhängigkeiten (npm audit) | ca. 5 bis 10 | Next.js 15.0.2 und React-RC sind von Ende 2024, seither gab es einige Lücken in Next.js |
| Secrets (gitleaks) | 1 | In `config.js` steht ein API-Key direkt im Code |
| Image (Trivy) | über 100 | `node:18` ist ein volles Debian-Image und Node 18 bekommt keine Updates mehr |

Gefährlichster Fund (Tipp): eine Lücke in Next.js, weil die App direkt im Internet erreichbar wäre. Das Secret ist auffällig, aber noch nicht angebunden.
