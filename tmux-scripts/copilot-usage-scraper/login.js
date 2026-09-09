// One-time (or auto-triggered) interactive login helper. Launches a real
// (headed) Chromium window via WSLg so you can log into GitHub normally
// (password + 2FA/passkey stay entirely in your hands - this script never
// sees or stores them). It prefills just the username field for convenience,
// using `gh api user` to look it up (no credentials involved).
// It polls the page automatically: once the Copilot usage page loads and shows
// your "AI credit" usage text, the session is saved and the browser closes
// on its own - no need to switch back to the terminal.
const { chromium } = require('playwright');
const path = require('path');
const fs = require('fs');
const { execSync } = require('child_process');

const STATE_DIR = path.join(process.env.HOME, '.config', 'copilot-usage');
const STATE_FILE = path.join(STATE_DIR, 'state.json');
const LOCK_FILE = path.join(STATE_DIR, 'login.lock');
const PASSWORD_FILE = path.join(STATE_DIR, 'password');
const TARGET_URL = 'https://github.com/settings/copilot/features';
const TIMEOUT_MS = 5 * 60 * 1000; // 5 minutes to complete login

function getUsername() {
  try {
    return execSync('gh api user --jq .login', { encoding: 'utf8' }).trim();
  } catch {
    return null;
  }
}

(async () => {
  fs.mkdirSync(STATE_DIR, { recursive: true, mode: 0o700 });

  // Avoid spawning multiple login windows if triggered repeatedly
  if (fs.existsSync(LOCK_FILE)) {
    const lockPid = parseInt(fs.readFileSync(LOCK_FILE, 'utf8').trim(), 10);
    if (lockPid && (() => { try { process.kill(lockPid, 0); return true; } catch { return false; } })()) {
      console.log('Login already in progress (another window is open). Exiting.');
      process.exit(0);
    }
  }
  fs.writeFileSync(LOCK_FILE, String(process.pid));

  const cleanup = () => { try { fs.unlinkSync(LOCK_FILE); } catch {} };
  process.on('exit', cleanup);

  const browser = await chromium.launch({ headless: false });
  const context = await browser.newContext();
  const page = await context.newPage();
  await page.goto('https://github.com/login');

  const username = getUsername();
  if (username) {
    await page.fill('#login_field', username).catch(() => {});
    console.log(`Prefilled username: ${username}`);
  }

  let autoSubmitted = false;
  if (fs.existsSync(PASSWORD_FILE)) {
    const password = fs.readFileSync(PASSWORD_FILE, 'utf8').replace(/\r?\n$/, '');
    if (password) {
      await page.fill('#password', password).catch(() => {});
      await page.click('input[name="commit"]').catch(() => {});
      autoSubmitted = true;
      console.log('Prefilled password and submitted - waiting for 2FA if required.');
    }
  }

  if (autoSubmitted) {
    console.log('\nIf prompted, complete 2FA/passkey. Session saves automatically once logged in.\n');
  } else {
    console.log('\nA browser window has opened. Please enter your password and complete 2FA if prompted,');
    console.log('then wait for redirect to the Copilot settings page.');
    console.log('This script will detect it automatically and save the session - just log in.\n');
  }

  // GitHub may default to a passkey/security-key prompt when several 2FA
  // methods are enrolled. Since this browser can't complete a passkey
  // challenge, steer it to the authenticator-app (TOTP) option instead.
  async function preferAuthenticatorApp() {
    for (let i = 0; i < 6; i++) {
      await page.waitForTimeout(700);
      // Already on the TOTP code entry screen - nothing to do.
      const hasOtpInput = await page.locator('#app_totp, input[name="otp"], input[autocomplete="one-time-code"]').first().isVisible().catch(() => false);
      if (hasOtpInput) return;

      const authenticatorLink = page.locator('a, button').filter({ hasText: /authenticator app/i }).first();
      if (await authenticatorLink.isVisible().catch(() => false)) {
        await authenticatorLink.click().catch(() => {});
        continue;
      }

      const otherWaysLink = page.locator('a, button').filter({ hasText: /(more options|try another way|other (two-factor )?method|different (way|method))/i }).first();
      if (await otherWaysLink.isVisible().catch(() => false)) {
        await otherWaysLink.click().catch(() => {});
      }
    }
  }
  if (autoSubmitted) await preferAuthenticatorApp();

  const start = Date.now();
  let saved = false;
  let lastNav = 0;
  while (Date.now() - start < TIMEOUT_MS) {
    await page.waitForTimeout(2000);
    const url = page.url();
    const onLoginPage = /\/login|\/session/.test(url);

    if (!onLoginPage) {
      // We're logged in (or at least past the login page) - keep steering
      // toward the target settings page every ~4s until it sticks.
      if (!url.startsWith(TARGET_URL) && Date.now() - lastNav > 4000) {
        await page.goto(TARGET_URL).catch(() => {});
        lastNav = Date.now();
        continue;
      }
      const bodyText = await page.textContent('body').catch(() => '');
      if (bodyText && /AI credit/i.test(bodyText)) {
        await context.storageState({ path: STATE_FILE });
        fs.chmodSync(STATE_FILE, 0o600);
        console.log(`Detected usage page - session saved to ${STATE_FILE}`);
        saved = true;
        break;
      }
    }
  }

  if (!saved) {
    console.log('Timed out waiting for login/navigation. Re-run this script to try again.');
  }

  await browser.close();
  process.exit(saved ? 0 : 1);
})();
