// Uses the saved login session (state.json, created by login.js) to load the
// Copilot usage settings page headlessly and print "used/total" AI credits.
// Prints "n/a" (and nothing else) on any failure, e.g. if the session expired
// (in which case, re-run: node login.js).
const { chromium } = require('playwright');
const path = require('path');
const fs = require('fs');

const STATE_FILE = path.join(process.env.HOME, '.config', 'copilot-usage', 'state.json');
const TARGET_URL = 'https://github.com/settings/copilot/features';

(async () => {
  if (!fs.existsSync(STATE_FILE)) {
    console.log('expired');
    process.exit(0);
  }

  let browser;
  try {
    browser = await chromium.launch({ headless: true });
    const context = await browser.newContext({ storageState: STATE_FILE });
    const page = await context.newPage();
    await page.goto(TARGET_URL, { waitUntil: 'domcontentloaded', timeout: 15000 });

    if (/\/login|\/session/.test(page.url())) {
      console.log('expired');
      await browser.close();
      process.exit(0);
    }

    const bodyText = await page.textContent('body').catch(() => '');
    const match = bodyText && bodyText.match(/([0-9][0-9,]*)\s*\/\s*([0-9][0-9,]*)\s*AI credit/i);

    if (match) {
      const used = match[1].replace(/,/g, '');
      const total = match[2].replace(/,/g, '');
      console.log(`${used}/${total}`);
    } else {
      console.log('n/a');
    }
  } catch (e) {
    console.log('n/a');
  } finally {
    if (browser) await browser.close();
  }
})();
