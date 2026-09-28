// https://stackoverflow.com/questions/46745014/alternative-for-dirname-in-node-js-when-using-es6-modules
import path from 'node:path';
import { fileURLToPath } from 'node:url';
// not the same since these will give the absolute paths for this file instead of for the file using them
const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
// explicit object instead of Object.fromEntries since the built-in type would loose the keys, better type: https://dev.to/svehla/typescript-object-fromentries-389c
export const dataDir = s => path.resolve(__dirname, '..', 'data', s);

// modified path.resolve to return null if first argument is '0', used to disable screenshots
export const resolve = (...a) => a.length && a[0] == '0' ? null : path.resolve(...a);

// json database
import { JSONFilePreset } from 'lowdb/node';
export const jsonDb = (file, defaultData) => JSONFilePreset(dataDir(file), defaultData);

// TOTP (2FA) code generation. otplib 13 replaced the `authenticator` singleton with functional
// generate(). Its default guardrail rejects secrets shorter than 16 bytes, but otplib 12 and
// Google Authenticator's 80-bit/16-char secrets are shorter, so lower MIN_SECRET_BYTES to stay
// backward-compatible with existing OTP secrets. Verified to produce identical codes to otplib 12.
import { generateSync, createGuardrails } from 'otplib';
const otpGuardrails = createGuardrails({ MIN_SECRET_BYTES: 10 });
export const totp = secret => generateSync({ secret, guardrails: otpGuardrails });

// CloakBrowser draws a random --fingerprint seed on every launch. With our persistent, logged-in profile that makes the
// same session present as a different device on each run, which costs trust with anti-bot systems (e.g. Epic's hcaptcha
// at checkout). Pin one seed per browser profile instead: FINGERPRINT_SEED if set, else generated once and stored in it.
import { existsSync, mkdirSync, readFileSync, writeFileSync } from 'node:fs';
export const fingerprintSeed = () => {
  if (cfg.fingerprint_seed) return cfg.fingerprint_seed;
  const file = path.join(cfg.dir.browser, 'fingerprint-seed');
  if (existsSync(file)) return readFileSync(file, 'utf8').trim();
  const seed = String(Math.floor(Math.random() * 90000) + 10000); // same range as CloakBrowser's own seeds
  mkdirSync(cfg.dir.browser, { recursive: true });
  writeFileSync(file, seed);
  return seed;
};

export const delay = ms => new Promise(resolve => setTimeout(resolve, ms));
// date and time as UTC (no timezone offset) in nicely readable and sortable format, e.g., 2022-10-06 12:05:27.313
export const datetimeUTC = (d = new Date()) => d.toISOString().replace('T', ' ').replace('Z', '');
// same as datetimeUTC() but for local timezone, e.g., UTC + 2h for the above in DE
export const datetime = (d = new Date()) => datetimeUTC(new Date(d.getTime() - d.getTimezoneOffset() * 60000));
export const filenamify = s => s.replaceAll(':', '.').replace(/[^a-z0-9 _\-.]/gi, '_'); // alternative: https://www.npmjs.com/package/filenamify - On Unix-like systems, / is reserved. On Windows, <>:"/\|?* along with trailing periods are reserved.

// On failure, capture what the page actually looked like so a changed selector can be worked out from the logs instead of
// reproducing it by hand. The log gets the URL, title and a filtered aria snapshot of every frame (checkout and login run
// in iframes, which page-level snapshots don't descend into); the full snapshot, HTML of each frame, a screenshot and the
// error go to data/debug/<name>/<datetime>/. Best effort: it must never throw or hide the original error. DEBUG_DUMP=0 disables it.
const withTimeout = (p, ms = 5000) => Promise.race([p, delay(ms).then(() => Promise.reject(new Error(`timed out after ${ms}ms`)))]);
// Roles worth seeing in the log; links, list items and images are dropped since site navigation would drown out the rest.
const DUMP_LOG_ROLES = /^\s*- (heading|button|textbox|checkbox|radio|combobox|dialog|alertdialog|alert|status|iframe|text|paragraph)\b/;
const DUMP_LOG_MAX_LINES = 150; // per frame
export const dumpFailure = async (page, name, error) => {
  if (!cfg.debug_dump || !page || page.isClosed()) return;
  try {
    const dir = path.join(dataDir('debug'), name, filenamify(datetime()));
    mkdirSync(dir, { recursive: true });
    const url = page.url();
    const title = await withTimeout(page.title()).catch(_ => '?');
    const log = [`--- Debug dump (disable with DEBUG_DUMP=0), files in ${dir}`, `URL: ${url}`, `Title: ${title}`];
    const aria = [];
    let i = 0;
    for (const frame of page.frames()) {
      if (frame.isDetached() || frame.url() == 'about:blank') continue;
      const n = i++;
      const frameUrl = frame.url().split('?')[0]; // query strings can carry tokens, keep them out of the log
      const html = await withTimeout(frame.content()).catch(e => `<!-- content failed: ${e.message} -->`);
      writeFileSync(path.join(dir, `frame-${n}.html`), `<!-- ${frame.url()} -->\n${html}`);
      const snapshot = await frame.locator('body').ariaSnapshot({ timeout: 5000 }).catch(e => `# aria snapshot failed: ${e.message.split('\n')[0]}`);
      aria.push(`# frame-${n}: ${frame.url()}\n${snapshot}`);
      // Show each distinct line once with a repeat count, so e.g. dozens of 'Add to cart' buttons don't eat the budget.
      const counts = new Map();
      for (const l of snapshot.split('\n').filter(l => DUMP_LOG_ROLES.test(l))) counts.set(l.trim(), (counts.get(l.trim()) ?? 0) + 1);
      const lines = [...counts].map(([l, c]) => `  ${l}${c > 1 ? ` (x${c})` : ''}`);
      if (!lines.length) continue; // e.g. tracking iframes
      log.push(`[frame-${n}] ${frameUrl}`, ...lines.slice(0, DUMP_LOG_MAX_LINES));
      if (lines.length > DUMP_LOG_MAX_LINES) log.push(`  ... ${lines.length - DUMP_LOG_MAX_LINES} more lines in aria.yml`);
    }
    writeFileSync(path.join(dir, 'aria.yml'), aria.join('\n\n'));
    writeFileSync(path.join(dir, 'error.txt'), `${url}\n\n${error?.stack ?? error ?? ''}`);
    await page.screenshot({ path: path.join(dir, 'page.png'), fullPage: true, timeout: 10000 }).catch(_ => { });
    console.error(log.join('\n'));
  } catch (e) {
    console.error('dumpFailure failed:', e.message);
  }
};

export const handleSIGINT = (context = null) => process.on('SIGINT', async () => { // e.g. when killed by Ctrl-C
  console.error('\nInterrupted by SIGINT. Exit!'); // Exception shows where the script was:\n'); // killed before catch in docker...
  process.exitCode = 130; // 128+SIGINT to indicate to parent that process was killed
  if (context) await context.close(); // in order to save recordings also on SIGINT, we need to disable Playwright's handleSIGINT and close the context ourselves
});

// used prompts before, but couldn't cancel prompt
// alternative inquirer is big (node_modules 29MB, enquirer 9.7MB, prompts 9.8MB, none 9.4MB) and slower
// open issue: prevents handleSIGINT() to work if prompt is cancelled with Ctrl-C instead of Escape: https://github.com/enquirer/enquirer/issues/372
import Enquirer from 'enquirer'; const enquirer = new Enquirer();
const timeoutPlugin = timeout => enquirer => { // cancel prompt after timeout ms
  enquirer.on('prompt', prompt => {
    const t = setTimeout(() => {
      prompt.hint = () => 'timeout';
      prompt.cancel();
    }, timeout);
    prompt.on('submit', _ => clearTimeout(t));
    prompt.on('cancel', _ => clearTimeout(t));
  });
};
enquirer.use(timeoutPlugin(cfg.login_timeout)); // TODO may not want to have this timeout for all prompts; better extend Prompt and add a timeout prompt option
// single prompt that just returns the non-empty value instead of an object
// @ts-ignore
export const prompt = o => enquirer.prompt({ name: 'name', type: 'input', message: 'Enter value', ...o }).then(r => r.name).catch(_ => {});
export const confirm = o => prompt({ type: 'confirm', message: 'Continue?', ...o });

// notifications via apprise CLI
import { execFile } from 'child_process';
import { cfg } from './config.js';

export const notify = html => new Promise((resolve, reject) => {
  if (!cfg.notify) {
    if (cfg.debug) console.debug('notify: NOTIFY is not set!');
    return resolve();
  }
  // const cmd = `apprise '${cfg.notify}' ${title} -i html -b '${html}'`; // this had problems if e.g. ' was used in arg; could have `npm i shell-escape`, but instead using safer execFile which takes args as array instead of exec which spawned a shell to execute the command
  const args = [cfg.notify, '-i', 'html', '-b', `'${html}'`];
  if (cfg.notify_title) args.push(...['-t', cfg.notify_title]);
  if (cfg.debug) console.debug(`apprise ${args.map(a => `'${a}'`).join(' ')}`); // this also doesn't escape, but it's just for info
  execFile('apprise', args, (error, stdout, stderr) => {
    if (error) {
      console.log(`error: ${error.message}`);
      if (error.message.includes('command not found')) {
        console.info('Run `pip install apprise`. See https://github.com/vogler/free-games-claimer#notifications');
      }
      return reject(error);
    }
    if (stderr) console.error(`stderr: ${stderr}`);
    if (stdout) console.log(`stdout: ${stdout}`);
    resolve();
  });
});

export const escapeHtml = unsafe => unsafe.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;').replaceAll('"', '&quot;').replaceAll('\'', '&#039;');

export const html_game_list = games => games.map(g => `- <a href="${g.url}">${escapeHtml(g.title)}</a> (${g.status})`).join('<br>');
