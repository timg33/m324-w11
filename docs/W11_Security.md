# W11 Security in der Pipeline

Repo: timg33/m324-w11 · Behebung: Pull Request #1 (`fix/w11-sicherheit`)

## Teil A: Prognose (vor dem ersten Scan)

| Werkzeug | Erwartete Funde | Warum |
|---|---|---|
| Abhängigkeiten (npm audit) | ca. 5 bis 10 | Next.js 15.0.2 und React-RC sind von Ende 2024, seither gab es einige Lücken in Next.js |
| Secrets (gitleaks) | 1 | In `config.js` steht ein API-Key direkt im Code |
| Image (Trivy) | über 100 | `node:18` ist ein volles Debian-Image und Node 18 bekommt keine Updates mehr |

Gefährlichster Fund (Tipp): eine Lücke in Next.js, weil die App direkt im Internet erreichbar wäre. Das Secret ist auffällig, aber noch nicht angebunden.

## Teil A: Pipeline

Drei neue Jobs in `.github/workflows/ci.yml`, alle laufen parallel zum Build:

| Job | Werkzeug | Was er prüft |
|---|---|---|
| Abhängigkeiten prüfen | `npm audit` | Pakete aus `package-lock.json` gegen die Datenbank bekannter Lücken |
| Secrets prüfen | gitleaks 8.30.1 | Die ganze Git-Historie (`fetch-depth: 0`), nicht nur den aktuellen Stand |
| Image prüfen | Trivy 0.76.2 | Das gebaute Docker-Image (Betriebssystem-Pakete und Node-Pakete) |

Jeder Job speichert zuerst einen Bericht mit allen Funden als Artefakt und bricht erst danach nach der Regel ab (siehe Teil D). Actions und das Trivy-Image sind auf Commit bzw. Digest gepinnt, gitleaks mit Prüfsumme. Grund: Im März 2026 waren `aquasec/trivy:latest` und die Tags von `trivy-action` manipuliert (CVE-2026-33634).

Zusätzlich aktiviert: Dependabot alerts. Secret Scanning und Push Protection hat GitHub beim öffentlichen Repo von selbst eingeschaltet.

## Teil A: Funde im Vergleich zur Prognose

Erster Lauf auf `main` (Commit `2519370`):

| Werkzeug | Prognose | Gefunden |
|---|---|---|
| npm audit | 5 bis 10 | **13 Pakete** (1 critical, 10 high, 2 moderate), davon 6 in Produktion |
| Dependabot | (nicht geschätzt) | **68 Alerts** (5 critical, 28 high, 31 medium, 4 low) |
| gitleaks | 1 | **1** (`generic-api-key` in `src/app/api/config.js`, Zeile 2, Commit `255582b`) |
| GitHub Secret Scanning | (nicht geschätzt) | **0** |
| Trivy, OS-Pakete | über 100 | **13'355 Meldungen** = 8'146 verschiedene CVEs in 242 Paketen (228 Meldungen critical) |
| Trivy, Node-Pakete | (nicht geschätzt) | **128** (89 in den Paketen der App, 39 im mitgelieferten npm) |

Was auffällt:
- npm audit zählt pro Paket, Dependabot pro Sicherheitsmeldung. Darum 13 gegen 68 für fast dieselben Pakete.
- GitHub Secret Scanning findet den Key nicht. Es kennt nur Muster bekannter Anbieter (z.B. AWS, Stripe). Unser Key ist ein allgemeiner String, den findet nur gitleaks.
- Beim Image lag ich um den Faktor 100 daneben. Das volle `node:18` bringt viel mit, was die App nie braucht (ImageMagick, Compiler, Header-Dateien).
- Trivy meldet nicht, dass Node 18 selbst End-of-Life ist. Das muss man selber wissen.

## Teil B: Befundliste

Gruppiert, weil 13'000 Einzelmeldungen nicht einzeln bewertbar sind. Sortiert nach Schweregrad.

| # | Fund | Werkzeug | Schweregrad | Relevant? | Entscheid | Begründung |
|---|---|---|---|---|---|---|
| 1 | `next` 15.0.2: RCE in React Server Components (CVE-2025-55182) | npm audit, Dependabot, Trivy | critical | **Ja** | beheben | Läuft in Produktion, App Router nutzt Server Components, von aussen erreichbar. Steht im CISA-KEV (wird aktiv ausgenutzt). Fix: 15.5.29 |
| 2 | `next` 15.0.2: Middleware-Bypass (CVE-2025-29927) | npm audit, Dependabot, Trivy | critical | Nein | False Positive | Die App hat keine `middleware.js`. Wird mit #1 trotzdem mitbehoben |
| 3 | `next` 15.0.2: weitere Lücken (Image Optimizer, Cache, Server Actions, DoS) | npm audit, Dependabot, Trivy | critical bis low | Teilweise | beheben | Die App nutzt kein `next/image` und keine Server Actions, aber `/_next/image` ist standardmässig aktiv. Gleicher Fix wie #1 |
| 4 | API-Key in `config.js` (Commit `255582b`) | gitleaks | (Secret = Vorfall) | **Ja** | beheben | Öffentliches Repo, Key bleibt in der Historie. Widerrufen, aus Umgebungsvariable lesen (siehe PR #1) |
| 5 | `zlib1g` CVE-2023-45853 | Trivy | CRITICAL | Nein | False Positive | Lücke liegt in MiniZip, Debian baut MiniZip nicht aus `zlib1g`. Mit Begründung in `.trivyignore.yaml` |
| 6 | OS-Pakete von `node:18` (8'146 CVEs, z.B. ImageMagick, libxml2-dev, linux-libc-dev) | Trivy | 228× CRITICAL | Eher nein | beheben | Die App ruft diese Programme nie auf, aber jedes Paket ist Angriffsfläche. Node 18 ist End-of-Life. Wechsel auf `node:24-slim` |
| 7 | npm im Image (`tar` critical, `undici`, `brace-expansion`) | Trivy | CRITICAL, HIGH | Nein | beheben | npm wird im Betrieb nicht gebraucht, nur zum Starten. npm aus dem Image entfernt, Start direkt mit `node` |
| 8 | `postcss` (über next) | npm audit, Trivy | high | Gering | beheben | Läuft nur beim Build mit unserem eigenen CSS. Fix nur mit Next 16 (Major), darum `overrides` auf 8.5.33 |
| 9 | `sharp` (über next) | npm audit, Trivy | high | Gering | beheben | Nur für Bildoptimierung, die App hat keine Bilder. Gleicher Fix wie #1 |
| 10 | `nanoid`, `source-map-js` | npm audit | high | Nein | beheben | Werden von Next intern genutzt, keine Benutzereingabe. Fix ohne Risiko (`npm audit fix`) |
| 11 | ESLint-Pakete (`brace-expansion`, `minimatch`, `cross-spawn`, `flatted`, `js-yaml`, `picomatch`, `ajv`, `@typescript-eslint/*`) | npm audit | high, moderate | Nein | beheben, Rest akzeptieren | Nur beim Entwickeln, verarbeiten nur unseren Code. Waren aber im alten Image, weil das Dockerfile die Dev-Pakete nicht entfernt hat |
| 12 | `uuid` < 11.1.1 | npm audit, Dependabot | moderate | Nein | beheben | Lücke nur bei v3/v5/v6 mit `buf`-Parameter. Die App nutzt `v4()` ohne `buf`. Patch-Update, kein Risiko |
| 13 | OS-Pakete von `node:24-slim` ohne Fix (z.B. util-linux, PAM, systemd, ncurses) | Trivy | 37× HIGH | Nein | akzeptieren | Es gibt noch keine korrigierte Version. `mount`, Login und systemd laufen im Container nicht (siehe Teil D) |

**Nach Relevanz sortiert:** #4 und #1 ganz oben (Secret im öffentlichen Repo, RCE im KEV), dann #3, #6, #8, #9. Ganz unten #2 und #5, obwohl beide critical sind.

**Ändert sich die Reihenfolge?** Ja, stark. Zwei der critical-Funde (#2, #5) treffen bei uns gar nicht zu, und das Secret hat bei npm und Trivy gar keinen Schweregrad, ist aber das Dringendste.

## Teil C: Behebung

Alles in PR #1, Pipeline grün.

| Massnahme | Schliesst | Risiko des Updates |
|---|---|---|
| `next` 15.0.2 → 15.5.29 | #1, #2, #3, #9 | Minor. React musste mit (RC → 19.0.9). Lint, Build und alle API-Routen lokal getestet |
| `uuid` → 11.1.1, `npm audit fix` | #10, #12, Teile von #11 | Patch, nur Lockfile |
| `overrides` für `postcss` | #8 | Next ist mit 8.4.31 getestet, 8.5.x ist kompatibel. Build läuft |
| `node:18` → `node:24-slim`, Dev-Pakete und npm entfernt, User `node` | #6, #7 | Neue Node-Major-Version. Build in der Pipeline grün, Start mit `node` lokal getestet |
| Pipeline und `.nvmrc` auf Node 24 | Node 20 End-of-Life | Lokal braucht es `nvm install 24` |

**Erneuter Scan (Commit `a329c46`):**

| Werkzeug | Vorher | Nachher |
|---|---|---|
| npm audit (Produktion) | 6 Pakete | **0** |
| npm audit (alle) | 13 Pakete | 7 (alle ESLint, 1 high, 6 moderate) |
| gitleaks | 1 | 0 (alter Fund nach Widerruf in `.gitleaksignore`) |
| Trivy, OS-Pakete | 13'355 | **250** (120 CVEs in 45 Paketen, **keine** mit Fix) |
| Trivy, Node-Pakete | 128 | **0** |

**Secret:** Die Schritte stehen in der Beschreibung von PR #1 (widerrufen und ersetzen, Nutzung prüfen, sicher ablegen, Historie, künftig verhindern).

## Teil D: Bewusst nicht behoben

| Fund | Begründung | Verantwortlich | Neu bewerten |
|---|---|---|---|
| #13 OS-Pakete ohne Fix in `node:24-slim` (37 HIGH) | Debian hat noch keine korrigierte Version. Betroffen sind vor allem `mount`, PAM und systemd, die im Container nicht laufen. Die App läuft nicht als root | Tim | Bei jedem Dependabot-PR für das Basis-Image (wöchentlich), spätestens 31.01.2027 |
| #11 Rest der ESLint-Kette (1 high, 6 moderate) | Nur Entwicklungswerkzeug, verarbeitet nur unseren eigenen Code, ist im Image nicht mehr drin. Der Fix bräuchte ESLint 9 bzw. Next 16 (Major) | Tim | Beim Update auf Next 16, spätestens 31.01.2027 |

## Teil D: Abbruchregel

| Fund | Reaktion | Umsetzung in der Pipeline |
|---|---|---|
| Secret im Code oder in der Historie | **Abbruch** | gitleaks bricht bei jedem Fund ab |
| Abhängigkeit in Produktion ab high | **Abbruch** | `npm audit --omit=dev --audit-level=high` |
| Image ab HIGH mit verfügbarem Fix | **Abbruch** | Trivy `--severity HIGH,CRITICAL --ignore-unfixed --exit-code 1` |
| Image ab HIGH ohne Fix | Melden | Im Bericht, Neubewertung über Dependabot (wöchentlich) |
| moderate und low | Melden | Im Bericht, im normalen Update-Rhythmus beheben |
| Abhängigkeiten nur für Entwicklung | Melden | Im Bericht und bei Dependabot |
| Bewusste Ausnahme / False Positive | Ausnahmeliste | `.trivyignore.yaml` (mit Ablaufdatum) und `.gitleaksignore` (mit Begründung) |

**Begründung:**
- Secrets brechen immer ab, weil jedes Secret ein Vorfall ist. Ein Schweregrad hilft da nicht.
- Ab high, weil das die Funde sind, die wirklich schaden können. Würde schon moderate abbrechen, wäre die Pipeline fast immer rot und man würde sie ignorieren.
- Nur Produktion, weil Dev-Pakete nicht im Image landen und keine Benutzereingaben sehen.
- Nur mit Fix, weil man ohne Fix nichts tun kann. Sonst wäre die Pipeline wochenlang rot, ohne dass jemand etwas ändern kann. Die Funde ohne Fix verschwinden aber nicht, sie stehen im Bericht.
- Ausnahmen laufen ab. Ein akzeptierter Fund ohne Datum wäre nur ein vergessener Fund.

## Teil D: Bewertung durch eine KI

KI: Claude Sonnet, ohne Websuche (nur Wissen des Modells). Eingabe: die Befundliste vom ersten Scan (Fund, Werkzeug, Schweregrad) und kurz die App, **ohne den Key selbst**. Auftrag an die KI: pro Fund Relevanz, Fix mit Version und ob der Schweregrad stimmt, dazu eine Abbruchregel.

**Aussagen, die nicht stimmen:**

| Fund | Aussage der KI | Meldung des Werkzeugs | Urteil |
|---|---|---|---|
| #1 next | «mindestens 15.0.5, besser >= 15.5.9» | Trivy: CVE-2026-75604 erst ab 15.5.24 behoben, GHSA-2464-fhr4-w9xw erst ab 15.5.28. npm audit schlägt 15.5.29 vor | **falsch**, 15.5.9 wäre noch verwundbar |
| #9 sharp | «next-Update, das ein aktuelles sharp (>= 0.33) bringt» | npm audit: verwundbar bis 0.35.5-rc.1 | **falsch**, 0.33 ist zu alt (jetzt 0.35.5) |
| #10 nanoid | «overrides auf nanoid >= 3.3.8» | npm audit: verwundbar bis 3.3.17 (drei Meldungen, 3.3.8 behebt nur die erste) | **falsch** (jetzt 3.3.20) |
| #11 ESLint | «reine Dev-Abhängigkeiten, nicht im Produktionsimage» | Trivy, alter Scan: 34 Meldungen von ESLint-Paketen in `app/node_modules` im Image | **falsch** für den Ausgangsstand. Das alte Dockerfile hat die Dev-Pakete nicht entfernt |
| #8 postcss | «overrides auf postcss >= 8.5.x oder next-Update» | npm audit: verwundbar bis 8.5.22, über next erst mit 16.4.6 (Major) behoben. next 15.5.29 bringt weiter 8.4.31 | **ungenau**, «8.5.x» reicht nicht und das next-Update hilft nicht |
| #5 zlib | «Debian stuft ihn als minor ein» | Trivy: Status `will_not_fix`. Debian-Tracker: für bookworm «ignored», weil MiniZip nicht gebaut wird | **ungenau**, nicht «minor», sondern «nicht betroffen» |

**Aussagen, die stimmen:** Middleware-Bypass behoben ab 15.2.3 (Trivy: 15.2.3), React2Shell ab 15.0.5 in der 15.0-Linie (Trivy: 15.0.5), uuid ab 11.1.1 (npm audit: < 11.1.1), GitHub Secret Scanning kennt nur Anbieter-Muster (unser Scan: 0 Funde). Die empfohlene Abbruchregel ist fast gleich wie unsere.

**Fazit:** Die Einschätzung der Relevanz war gut. Die Fehler lagen fast alle bei **Versionsnummern**. Die KI kennt nur ältere Meldungen und hat jeweils die erste korrigierte Version genannt, nicht die, die alle Meldungen schliesst. Sie hat selber geschrieben, dass man die Versionen prüfen soll. Wer ihren Vorschlag ungeprüft übernimmt, hätte bei next, sharp und nanoid noch verwundbare Versionen.

## Zusatz: Secret gar nicht erst einchecken

Idee: gitleaks schon **vor dem Commit** laufen lassen, nicht erst in der Pipeline. Zum Beispiel mit dem Framework pre-commit:

```yaml
# .pre-commit-config.yaml (jede Person einmal: pip install pre-commit && pre-commit install)
repos:
  - repo: https://github.com/gitleaks/gitleaks
    rev: v8.30.1
    hooks:
      - id: gitleaks
```

Dann prüft gitleaks bei jedem `git commit` die gestagten Änderungen und bricht den Commit ab, wenn es ein Secret findet.

Zusammen mit den anderen Schichten:

| Schicht | Wo | Kann umgangen werden durch |
|---|---|---|
| Pre-Commit-Hook | Laptop | `git commit --no-verify`, Hook nach dem Klonen nicht installiert (Hooks werden nicht mitgeklont), Commit über den GitHub-Webeditor |
| Push Protection | GitHub | Erkennt nur bekannte Anbieter-Muster. **Unseren Key hat es nicht erkannt.** Beim Push kann man die Sperre mit Begründung übergehen |
| gitleaks in der Pipeline | GitHub Actions | Nicht umgehbar ohne Änderung am Workflow, aber findet erst nach dem Push. Dann ist das Secret schon öffentlich |

Darum braucht es alle drei. Dazu `.env*` in `.gitignore`, damit die typische Datei mit Secrets gar nicht erst im Repo landet.

## Reflexion

**Was hat mich überrascht?** Die Menge beim Image. Ich habe über 100 erwartet, es waren über 13'000. Fast alles kam aus Paketen, die die App nie braucht. Mit `node:24-slim` waren es noch 250, ohne eine Zeile Code zu ändern. Überrascht hat mich auch, dass GitHubs eigenes Secret Scanning den Key nicht gefunden hat.

**Gefährlichster und auffälligster Fund:** Am gefährlichsten war die RCE in Next.js (#1), weil sie aktiv ausgenutzt wird und unsere App genau das verwendet. Am auffälligsten, aber harmlos war zlib (#5): CRITICAL, aber für uns ein False Positive. Auch die 228 critical-Meldungen im alten Image sahen schlimmer aus, als sie für diese App waren.

**Abbruch bei jedem Fund / nie:** Bei jedem Fund wäre die Pipeline auch nach der Behebung rot (250 OS-Funde ohne Fix). Dann würde man sie ignorieren oder abschalten. Nie abbrechen heisst, die RCE wäre ohne Warnung in Produktion gegangen. Darum die Regel: hart bei Secrets und bei Funden ab high mit Fix, den Rest melden.

**Wo würde ich im Betrieb zuerst ansetzen?** Beim Basis-Image und bei den Dependabot-Updates. Das bringt am meisten mit dem wenigsten Aufwand. Danach Secrets: Push Protection und gitleaks in jeder Pipeline.
