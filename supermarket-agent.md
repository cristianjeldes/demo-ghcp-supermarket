# Supermarket Agent — Usage & Integration Guide

This repository provides a PowerShell "agent" that accepts a shopping request (freeform prompt or list of items), scrapes two Chilean supermarkets (super.lider.cl and www.jumbo.cl), and produces a single-store, price-optimized shopping recommendation. It includes Playwright-based scrapers (Node) and PowerShell orchestration, parsing, and optimization logic.

## Quick prerequisites
- Windows PowerShell (recommended PowerShell 7+)
- Node.js >= 16
- From repository root:
  - npm install
  - npx playwright install --with-deps

## Key files
- agent.ps1 — main orchestrator. Accepts -Prompt (free text) or -Items (string[]) and -Sites (default: super,jumbo). Produces parsed requests, invokes scrapers and optimizer.
- scrape-prices.ps1 — PowerShell wrapper that runs the Node scraper (scraper.js) per item/site and aggregates structured outputs into results.csv.
- scraper.js — Node + Playwright scraper. Supports 'lider' (super.lider.cl) and 'jumbo' (www.jumbo.cl). Emits marker-wrapped JSON to stdout and saves screenshot/.html when run headed.
- skill-super-lider.ps1, skill-jumbo.ps1 — thin wrappers to call the main scraper for a single site.
- quantity-parser.ps1 — Parse-QuantityString function: extracts quantity, unit, and cleaned name from item strings.
- optimize-prices.ps1 — Performs fuzzy matching, unit/price normalization, per-store cost estimation, and selects the single store with the lowest total. Writes recommendation CSV.
- README.md — short project overview and install notes.

## How it works (high-level)
1. Agent parses prompt/items into requests (name + quantity + unit) and saves requests-<timestamp>.json.
2. Agent runs scrape-prices.ps1 which calls scraper.js for each site & query. scraper.js uses Playwright to render JS sites and extract product blocks. scraper outputs JSON wrapped in markers for robust parsing.
3. scrape-prices.ps1 converts scraper JSON into results.csv with structured fields.
4. optimize-prices.ps1 reads requests JSON and results.csv, matches items to products (token overlap heuristic), normalizes unit pricing (kg/g/l/ml/unit where possible), and computes per-store totals. It chooses the single feasible store with lowest total and writes recommendation-<timestamp>.csv.

## CLI examples
- Install dependencies (repo root):

  npm install
  npx playwright install --with-deps

- Quick agent run (example):

  powershell -File .\agent.ps1 -Items "pan integral","leche" -Sites "super","jumbo"

- Use a freeform prompt:

  powershell -File .\agent.ps1 -Prompt "Buy pan integral and 2L leche" -Sites "super","jumbo"

- Call a site-specific skill:

  powershell -File .\skill-super-lider.ps1 -Items "pan integral" -Output super-results.csv

- Run the Node scraper directly:

  node scraper.js jumbo "pan integral"
  node scraper.js super "pan integral" --headed --timeout=180000

  Flags:
  - --headed : run Playwright in headed (non-headless) mode (useful for debugging; scraper auto-forces headed for 'lider')
  - --timeout=MS : navigation timeout in milliseconds

## Outputs and file formats
- results.csv (aggregated scraped items)
  Columns: site, query, index, title, price, currency, size, unit, unit_price, product_url, raw

- requests-<timestamp>.json (parsed item requests; includes quantity and unit)

- recommendation-<timestamp>.csv (optimizer output for chosen store)
  Columns: store, request, query, quantity, req_unit, matched_title, price, match_score, unit_price, unit, item_total, product_url

- Debug artifacts for lider: lider-<timestamp>.png and lider-<timestamp>.html (saved when scraper runs in headed mode)

## Integration notes for other agents
- Preferred integration: invoke agent.ps1 with -Prompt or -Items and let it produce recommendation CSV. The calling agent can then read the CSV and present the result to the user or act on it.

- Low-level integration: call node scraper.js to fetch site-specific product lists (read marker JSON from stdout), then call optimize-prices.ps1 with the requests JSON and results CSV to run matching/optimization separately.

- Programmatic call example (non-PowerShell agent calling shell):

  powershell -NoProfile -NonInteractive -File E:\code\supermarket_ghcp\agent.ps1 -Prompt "pan integral, leche" -Sites "super","jumbo"

## Heuristics and defaults
- Single-store optimization: by default the optimizer prefers a single store with the lowest total price across all requested items (per project preference).
- Quantity parsing: Parse-QuantityString extracts common units (kg, g, l, ml, un). Default quantity is 1 unit when unspecified.
- Brand handling: Current behavior prefers brand where token matching favors it, but will select cheaper substitutes if the exact brand isn't found. This is configurable in future enhancements.
- Unit normalization: Optimizer tries to compute a normalized unit price (price per kg, per L, per unit) when size metadata is available. This is heuristic and not guaranteed perfect for every label.

## Limitations & recommendations
- lider (super.lider.cl) often serves different content to headless browsers. scraper.js forces headed mode for 'lider' by default. Ensure Playwright can run headed or pass --headed.
- Matching uses token-overlap scoring (fast, lightweight). For production-quality matching, consider integrating a fuzzy-string library or embeddings.
- Respect each site's terms of service and rate limits. For bulk runs, add delays between requests.
- Robot/anti-bot protections may change; saved screenshots/.html are useful for debugging when scraping fails.

## Troubleshooting
- "Node not found": install Node.js >= 16 and rerun npm install.
- "Playwright error": run npx playwright install --with-deps.
- No JSON output / parsing issues: inspect node-*.txt logs, check generated lider-<ts>.html and .png.
- If items are missing from results.csv, try running scraper.js for the specific site in headed mode to inspect selectors.

## Extensibility & next steps
- Improve fuzzy matching (Levenshtein, token-weighting, or embeddings).
- Implement explicit brand-preference policies (strict, preferred-with-fallback, ask-before-substitute).
- Add optional cross-store optimization mode (allow mixing stores to minimize total cost).
- Cache product catalogs for repeat runs and faster matching.

## Where to find things
- Repo root: E:\code\supermarket_ghcp
- Main orchestrator: agent.ps1
- Planner & todos (session): see plan.md in the Copilot session-state folder for current todos and progress.

## Legal & ethics
- Verify and comply with each site's terms of service before scraping or automating purchases. Use this tool responsibly.

---

If more details or an alternative output format are needed (JSON, direct cart API calls, or more robust matching), the project can be extended; see the TODOs in the internal plan for next steps.