# Copilot instructions — demo-ghcp-supermarket

Purpose
- Orchestrate scraping and price-optimization across super.lider.cl ("super") and www.jumbo.cl ("jumbo"). This repo exposes a PowerShell agent and POSIX sh equivalents that call a Node + Playwright scraper and an optimizer.

Prerequisites
- Node.js >= 16 (must be on PATH)
- npm
- Playwright browsers: `npx playwright install --with-deps`
- On Windows: PowerShell (7+ recommended)
- On Linux/macOS: bash; make sh scripts executable (chmod +x *.sh)

Primary workflows (commands)
- Windows (PowerShell):
  powershell -File .\agent.ps1 -Items "pan integral","leche" -Sites "super","jumbo" -Output results.csv

- Linux / macOS (bash):
  ./agent.sh --items "pan integral" "leche" --sites super jumbo --output results.csv

- Run a single-site scraper for debugging:
  node scraper.js jumbo "pan integral"
  node scraper.js super "pan integral" --headed --timeout=180000

Key files
- agent.ps1 / agent.sh — main orchestrator (parses prompt/items, saves requests-<ts>.json, calls scraper & optimizer)
- scrape-prices.ps1 / scrape-prices.sh — wrapper that calls scraper.js per item/site and aggregates JSON -> results.csv
- scraper.js — Playwright renderer + extractor (site selectors live here)
- quantity-parser.ps1 / quantity-parser.sh — Parse-QuantityString helper
- optimize-prices.ps1 / optimize-prices.sh — token-overlap matching, unit normalization, and single-store optimizer
- skill-super-lider.*, skill-jumbo.* — thin wrappers for single-site runs

Expected outputs
- requests-<timestamp>.json — parsed item requests (name, quantity, unit)
- results.csv — aggregated scraped products (site, query, title, price, size, unit_price, product_url, raw)
- recommendation-<timestamp>.csv — optimizer output for chosen store
- lider-<timestamp>.png / .html — debug artifacts for lider when scraper runs headed

Operational rules for Copilot (agent behavior)
- Prefer running the existing orchestration (agent.ps1 or agent.sh) rather than reimplementing it.
- If dependencies are missing, add a minimal package.json listing playwright (or other required packages), run `npm install`, then `npx playwright install --with-deps`.
- Always run a smoke test after changes: run agent with 2 simple items (e.g., "pan integral","leche"). Verify that results.csv and recommendation-<ts>.csv are created and non-empty.
- When adjusting selectors in scraper.js: run in headed mode and inspect generated .html/.png for debugging.
- Respect site TOS and rate limits; add delays if performing bulk runs.

Development & commit policy
- Make small, surgical changes. If committing, include the required trailer on every commit message:

  Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>

- Prefer adding tests or a smoke script when changing scraping or matching logic.
- Normalize LF line endings for .sh files and ensure executable bit is set on Unix.

Limitations & notes
- Matching uses a token-overlap heuristic; results are not perfect. Consider integrating fuzzy-string or embeddings for higher-quality matching.
- Optimizer is single-store by design. If mixing stores is desired, update optimize-prices.* accordingly.
- "lider" often requires headed mode; the scripts map "lider" -> "super" and auto-force headed where needed.

Troubleshooting checklist
1. Node missing: install Node >=16 and ensure PATH is updated.
2. "playwright" module missing: add to package.json and `npm install`, then `npx playwright install --with-deps`.
3. No JSON output from scraper: run scraper.js with --headed and inspect the saved lider-*.html/.png and node-*.txt logs.
4. Results CSV empty: confirm scraper produced marker-wrapped JSON lines (___BEGIN___...___END___) on stdout.

If you want, I can:
- Commit these instructions and the new .sh files (with Co-authored-by trailer),
- Make .sh files executable, or
- Add a CI smoke-test step to run the agent in a controlled environment.

End of file.
