# Supermarket Scraper (PowerShell + Playwright)

This repository provides a PowerShell app and Playwright scraper for super.lider.cl and www.jumbo.cl.

Files created:
- `scrape-prices.ps1` — PowerShell CLI wrapper that accepts -Items and -Sites and aggregates results.
- `scraper.js` — Node + Playwright script that renders pages and extracts text using the selectors you provided.
- `skill-super-lider.ps1`, `skill-jumbo.ps1` — thin skills/wrappers to call the main script for each site.

Requirements
- Node.js >= 16
- From the repo root: `npm install` then `npx playwright install --with-deps`

Example

powershell -File .\\scrape-prices.ps1 -Items "pan integral","leche" -Sites "super","jumbo" -Output results.csv

Notes
- Both sites require JS rendering; Playwright handles that.
- If selectors change, update `scraper.js` selector mapping.
- Respect site terms of service and rate limits. Add delays if you plan bulk scraping.
