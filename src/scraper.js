// scraper.js (src)
// Usage: node src/scraper.js <site> <query> [--headed]
// Sites supported: 'super' (super.lider.cl) and 'jumbo' (www.jumbo.cl)

const { chromium } = require('playwright');
const path = require('path');
const fs = require('fs');

function usage() {
  console.error('Usage: node src/scraper.js <site> <query> [--headed]');
  process.exit(2);
}

(async () => {
  try {
    const argv = process.argv.slice(2);
    let timeoutMs = 60000;
    const tEq = argv.findIndex(a => a.startsWith('--timeout='));
    if (tEq >= 0) {
      const val = argv[tEq].split('=')[1];
      timeoutMs = parseInt(val, 10) || timeoutMs;
      argv.splice(tEq, 1);
    } else {
      const tIdx = argv.findIndex(a => a === '--timeout');
      if (tIdx >= 0 && argv.length > tIdx + 1) {
        const val = argv[tIdx + 1];
        timeoutMs = parseInt(val, 10) || timeoutMs;
        argv.splice(tIdx, 2);
      }
    }
    if (argv.length < 2) usage();

    const siteArgRaw = argv[0].toLowerCase();
    let headless = !argv.includes('--headed') && !argv.includes('--no-headless') && !argv.includes('--head');
    ['--headed','--no-headless','--head'].forEach(f => { let idx; while ((idx = argv.indexOf(f)) !== -1) argv.splice(idx,1); });
    const query = argv.slice(1).join(' ');

    const siteKey = (siteArgRaw.includes('super') || siteArgRaw.includes('lider')) ? 'lider' :
                    (siteArgRaw.includes('jumbo')) ? 'jumbo' : siteArgRaw;

    const mapping = {
      'lider': {
        url: (q) => `https://super.lider.cl/search?q=${q}`,
        selector: '.mb0'
      },
      'jumbo': {
        url: (q) => `https://www.jumbo.cl/busqueda?ft=${q}`,
        selector: '.items-left'
      }
    };

    if (!mapping[siteKey]) {
      console.error(JSON.stringify({ error: 'Unknown site', site: siteArgRaw }));
      process.exit(2);
    }

    // Force headed for 'lider' (super.lider.cl)
    if (siteKey === 'lider') { headless = false; }

    const q = encodeURIComponent(query.trim().replace(/\s+/g, '+'));
    const url = mapping[siteKey].url(q);
    const selector = mapping[siteKey].selector;

    const repoRoot = path.resolve(__dirname, '..');
    const artifactsDir = path.join(repoRoot, 'artifacts');
    try { fs.mkdirSync(artifactsDir, { recursive: true }) } catch (e) { /* ignore */ }

    const browser = await chromium.launch({ headless });
    const context = await browser.newContext({ userAgent: 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/116.0.0.0 Safari/537.36' });
    const page = await context.newPage();
    page.setDefaultNavigationTimeout(timeoutMs);
    await page.goto(url, { waitUntil: 'domcontentloaded' });

    try { await page.waitForSelector(selector, { timeout: Math.max(15000, Math.floor(timeoutMs/2)) }); } catch (e) { }

    const items = await (async () => {
      if (siteKey === 'lider') {
        return await page.$$eval(selector, els => {
          return Array.from(els).map(el => {
            const raw = (el.textContent || '').replace(/\s+/g,' ').trim();
            let title = '';
            const a = el.querySelector('a');
            if (a && a.textContent) title = a.textContent.trim();
            if (!title) {
              const h = el.querySelector('h3, h2, h4, .product-title, .title, .name');
              if (h && h.textContent) title = h.textContent.trim();
            }
            if (!title) {
              const idx = raw.search(/\$|precio|Agregar|Patrocinado|Oferta|x\s*kg/i);
              title = (idx > 0) ? raw.slice(0, idx).trim() : raw.slice(0,120).trim();
            }
            const priceMatch = raw.match(/\$\s*([\d\.,]+)/);
            let price = null;
            if (priceMatch) { const cleaned = priceMatch[1].replace(/\./g,'').replace(/,/g,'.'); price = parseFloat(cleaned); }
            let unit = null; let unitPrice = null;
            const upMatch = raw.match(/\$\s*([\d\.,]+)\s*x\s*(kg|g|l|ml|un|unidad|unidades)/i);
            if (upMatch) { const cleaned = upMatch[1].replace(/\./g,'').replace(/,/g,'.'); unitPrice = parseFloat(cleaned); unit = upMatch[2].toLowerCase(); }
            const sizeMatch = raw.match(/(\d+(?:[\.,]\d+)?)\s*(kg|g|gr|ml|l|un|unidad|unidades)/i);
            let size = null; if (sizeMatch) size = `${sizeMatch[1]} ${sizeMatch[2]}`;
            let url = null; if (a && a.href) url = a.href;
            return { title, price, currency: 'CLP', size, unit, unitPrice, productUrl: url, brand: null, availability: true, raw };
          }).filter(Boolean);
        });
      } else if (siteKey === 'jumbo') {
        return await page.$$eval(selector, els => {
          return Array.from(els).map(el => {
            const raw = (el.textContent || '').replace(/\s+/g,' ').trim();
            let title = '';
            const a = el.querySelector('a');
            if (a && a.textContent) title = a.textContent.trim();
            if (!title) {
              const idx = raw.indexOf('$');
              title = (idx > 0) ? raw.slice(0, idx).trim() : raw.slice(0,120).trim();
            }
            const priceMatch = raw.match(/\$\s*([\d\.,]+)/);
            let price = null; if (priceMatch) { const cleaned = priceMatch[1].replace(/\./g,'').replace(/,/g,'.'); price = parseFloat(cleaned); }
            let unit = null; let unitPrice = null;
            const upMatch = raw.match(/\$\s*([\d\.,]+)\s*x\s*(kg|g|l|ml|un|unidad|unidades)/i);
            if (upMatch) { const cleaned = upMatch[1].replace(/\./g,'').replace(/,/g,'.'); unitPrice = parseFloat(cleaned); unit = upMatch[2].toLowerCase(); }
            const sizeMatch = raw.match(/(\d+(?:[\.,]\d+)?)\s*(kg|g|gr|ml|l|un|unidad|unidades)/i);
            let size = null; if (sizeMatch) size = `${sizeMatch[1]} ${sizeMatch[2]}`;
            let url = null; if (a && a.href) url = a.href;
            return { title, price, currency: 'CLP', size, unit, unitPrice, productUrl: url, brand: null, availability: true, raw };
          }).filter(Boolean);
        });
      } else {
        return await page.$$eval(selector, els => Array.from(els).map(e => ({ title: (e.textContent||'').trim(), raw: (e.textContent||'').trim() })));
      }
    })();

    if (!headless) {
      try {
        const fnameBase = `${siteKey.replace(/[^a-z0-9]/gi,'')}-${Date.now()}`;
        const screenshotPath = path.join(artifactsDir, `${fnameBase}.png`);
        const htmlPath = path.join(artifactsDir, `${fnameBase}.html`);
        await page.screenshot({ path: screenshotPath, fullPage: true });
        const html = await page.content();
        fs.writeFileSync(htmlPath, html, 'utf8');
        console.error(JSON.stringify({ debug: 'saved_screenshot', screenshot: screenshotPath, html: htmlPath }));
      } catch (e) {
        console.error(JSON.stringify({ error: 'screenshot_failed', message: e.message }));
      }
    }

    const out = JSON.stringify({ site: siteKey, query, url, items });
    console.log(`___BEGIN___${out}___END___`);
    await browser.close();
  } catch (err) {
    console.error(JSON.stringify({ error: err && err.message ? err.message : String(err) }));
    process.exit(1);
  }
})();
