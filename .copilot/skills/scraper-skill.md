Skill: Supermarket scraper (src)

Description
- Quick guide for using the repository scrapers (Playwright + orchestration).

Prerequisites
- Node.js >= 16 on PATH
- From repo root: npm install && npx playwright install --with-deps
- On Unix: make src/*.sh executable (chmod +x src/*.sh)

Where to run
- Use the scripts under ./src. Outputs are written to ./artifacts by default.

Common commands
- Run full agent (bash):
  ./src/agent.sh --items "pan integral" "leche" --sites super jumbo

- Run full agent (PowerShell):
  pwsh -File .\src\agent.ps1 -Items "pan integral","leche" -Sites "super","jumbo"

- Run a single-site skill:
  ./src/skill-jumbo.sh --items "pan integral" --output ./artifacts/jumbo-results.csv

Outputs (artifacts/)
- requests-<ts>.json  (parsed requests)
- results.csv         (aggregated scraped products)
- recommendation-<ts>.csv (optimizer output)
- lider-<ts>.png / .html (debug artifacts when scraper runs headed)

Notes for Copilot agents
- Prefer invoking ./src/agent.* so outputs land in artifacts/.
- When updating selectors in src/scraper.js, run with --headed to capture debug HTML/PNG.
- For automation: read artifacts/recommendation-<ts>.csv as the final output.

This skill is intended as human-facing instructions and automation guidance for integrating the scrapers.