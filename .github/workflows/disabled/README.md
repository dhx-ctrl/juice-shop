# Disabled Workflows

These workflows are part of the **upstream OWASP Juice Shop** project and have been intentionally disabled for this PFE (Projet de Fin d'Études) DevSecOps.

## Why?

- They are **not related** to the DevSecOps pipeline (`devsecops.yml`)
- Some require secrets we don't have (`DOCKERHUB_TOKEN`, `HEROKU_API_KEY`, `SLACK_WEBHOOK_URL`)
- They consume GitHub Actions minutes unnecessarily
- The ZAP and CodeQL scans are **replaced** by our own SAST/SCA/DAST pipeline with DefectDojo integration

## Active Pipeline

The only active workflow is:

```
.github/workflows/devsecops.yml
```

Which runs: **SonarQube (SAST)** → **Trivy (SCA)** → **ZAP (DAST)** → **DefectDojo (import)**

## Disabled Files

| File | Original Purpose |
|------|-----------------|
| `ci.yml` | Upstream CI/CD (tests, Docker push, Heroku deploy) |
| `codeql-analysis.yml` | GitHub CodeQL security scanning |
| `lint-fixer.yml` | Automated lint fixing |
| `lock.yml` | Lock inactive issues/PRs |
| `rebase.yml` | Automated PR rebasing |
| `release.yml` | Release packaging & publishing |
| `stale.yml` | Mark/close stale issues |
| `update-challenges-ebook.yml` | Sync challenges to ebook |
| `update-challenges-www.yml` | Sync challenges to website |
| `update-news-www.yml` | Sync news to website |
| `webpack-analysis.yml` | Webpack bundle analysis |
| `zap_scan.yml` | Upstream ZAP scan (replaced by devsecops.yml) |

> To re-enable any workflow, simply move it back to `.github/workflows/`.
