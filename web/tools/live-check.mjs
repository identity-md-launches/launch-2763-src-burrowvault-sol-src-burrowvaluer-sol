// Inspect the production export with real public data. Read-only; never opens a wallet.
import assert from 'node:assert/strict';
import { mkdir, readFile, writeFile } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import { join } from 'node:path';
import { chromium } from '../../test/scratch/site-tooling/node_modules/playwright/index.mjs';
import { previewServer } from './server.mjs';
const root = fileURLToPath(new URL('../../', import.meta.url));
const output = join(root, 'web/validation');
await mkdir(join(output, 'screenshots'), { recursive: true });
const server = previewServer(join(root, 'dist'));
await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
const browser = await chromium.launch({ args: ['--no-sandbox'] });
const context = await browser.newContext({ viewport: { width:1440, height:960 }, colorScheme:'light', reducedMotion:'reduce' });
const page = await context.newPage(), errors = [], missing = [], scripts = [];
page.on('pageerror', error => errors.push(error.message));
page.on('response', response => {
  if (response.url().startsWith('http://127.0.0.1:') && response.status() >= 400) missing.push(new URL(response.url()).pathname.replace('/preview/',''));
  if (response.request().resourceType() === 'script') scripts.push(new URL(response.url()).pathname.replace('/preview/',''));
});
const report = { checkedAt:new Date().toISOString(), passed:false, errors, missing, scripts, views:[] };
try {
  const liveConfig = await fetch('https://burrow-squeek.vercel.app/config.js', { signal:AbortSignal.timeout(30000) });
  assert(liveConfig.ok);
  report.configIdenticalToOperator = (await liveConfig.text()) === await readFile(join(root, 'web/config.js'), 'utf8');
  assert(report.configIdenticalToOperator);
  const response = await page.goto(`http://127.0.0.1:${server.address().port}/preview/`);
  report.scriptPolicy = response.headers()['content-security-policy'];
  await page.waitForFunction(() => document.querySelectorAll('#inv canvas').length === 6 && document.querySelector('#hmStats').textContent.includes('NAV') && document.querySelector('#bondStats').textContent.includes('Wheel clock') && document.querySelector('#gStats').textContent.includes('Cars delivered'), undefined, { timeout:45000 });
  report.live = await page.evaluate(() => ({ feed:document.querySelector('#tick').textContent, rpm:window.__rpm, caption:document.querySelector('#wheelCap').textContent, voxelPreviews:document.querySelectorAll('#inv canvas').length, three:window.THREE.REVISION, bonds:document.querySelector('#bondStats').innerText, stock:document.querySelector('#hmStats').innerText, garage:document.querySelector('#gStats').innerText }));
  for (const colorScheme of ['light','dark']) {
    await page.emulateMedia({ colorScheme });
    for (const width of [320,390,768,1120,1440]) {
      await page.setViewportSize({ width,height:844 });
      const view = await page.evaluate(() => ({width:innerWidth,scrollWidth:document.documentElement.scrollWidth,actionBottom:document.querySelector('.hero-act .pri').getBoundingClientRect().bottom,fonts:[...document.fonts].map(font=>({family:font.family,status:font.status}))}));
      report.views.push({ colorScheme,...view });assert(view.scrollWidth<=width);
      if(width===390)assert(view.actionBottom<844);
      if(width===390 || width===1440 && colorScheme==='light') await page.screenshot({path:join(output,`screenshots/${colorScheme}-${width}.png`)});
    }
    report[colorScheme+'Caption'] = await page.locator('#wheelCap').evaluate(el=>{const s=getComputedStyle(el);return {color:s.color,background:s.backgroundColor}});
  }
  await page.emulateMedia({colorScheme:'light'});await page.setViewportSize({width:390,height:844});
  for(const [id,name] of [['collateral','collateral-390'],['garage-panel','garage-390']]) {
    await page.locator('#'+id).scrollIntoViewIfNeeded();await page.screenshot({path:join(output,'screenshots/'+name+'.png')});
  }
  await page.evaluate(()=>window.scrollTo({top:0,behavior:'instant'}));await page.locator('#connect').focus();await page.keyboard.press('Enter');
  await page.screenshot({path:join(output,'screenshots/wallet-390.png')});await page.keyboard.press('Escape');
  report.walletFocusReturned = await page.locator('#connect').evaluate(el=>el===document.activeElement);assert(report.walletFocusReturned);
  assert.deepEqual(errors,[]);assert.deepEqual(missing,[]);report.passed=true;
} catch(error) { report.failure=String(error.stack||error);process.exitCode=1; }
finally {
  await writeFile(join(output,'live-browser.json'),JSON.stringify(report,null,2)+'\n');
  console.log(JSON.stringify(report,null,2));
  await context.close();await browser.close();await new Promise(resolve=>server.close(resolve));
}
