import { chromium } from 'playwright';
const base = process.env.EVE_TEST_BASE_URL ?? 'http://localhost:4177';
let checks = 0;
for (const [name, engine] of [['Google Chrome', chromium]]) {
  const browser = await engine.launch({ headless: true, ...(process.env.EVE_BROWSER_EXECUTABLE ? { executablePath: process.env.EVE_BROWSER_EXECUTABLE } : {}) });
  for (const width of [320, 360, 390, 430]) {
    const context = await browser.newContext({ viewport: { width, height: 740 }, reducedMotion: 'reduce' });
    const page = await context.newPage();
    const errors = [];
    page.on('pageerror', e => errors.push(e.message));
    await page.goto(base + '/today');
    await page.getByRole('heading', { name: 'Bu gün', exact: true }).waitFor();
    await page.waitForFunction(() => Object.keys(document.querySelector('button[aria-label="Əlavə et"]') ?? {}).some(key => key.startsWith('__reactProps$')));
    let size = await page.evaluate(() => ({ width: innerWidth, doc: document.documentElement.scrollWidth, body: document.body.scrollWidth }));
    if (size.doc > width || size.body > width) throw new Error(`${name} ${width} overflow ${JSON.stringify(size)}`);
    checks++;
    for (const label of ['Bu gün', 'Təqvim', 'Mənzillər']) {
      const link = page.getByRole('navigation', { name: 'Əsas mobil naviqasiya' }).getByRole('link', { name: label });
      const box = await link.boundingBox();
      if (!box || box.width < 44 || box.height < 44) throw new Error(`${name} ${width} small target ${label}`);
      await link.click();
      await page.waitForFunction(text => [...document.querySelectorAll('nav a')].some(a => a.textContent?.includes(text) && a.getAttribute('aria-current') === 'page'), label);
      const routeSize = await page.evaluate(() => ({ doc: document.documentElement.scrollWidth, body: document.body.scrollWidth }));
      if (routeSize.doc > width || routeSize.body > width) throw new Error(`${name} ${width} ${label} overflow ${JSON.stringify(routeSize)}`);
      checks += 2;
    }
    await page.getByRole('button', { name: 'Əlavə et' }).click();
    const menuSize = await page.evaluate(() => ({ doc: document.documentElement.scrollWidth, body: document.body.scrollWidth }));
    if (menuSize.doc > width || menuSize.body > width) throw new Error(`${name} ${width} menu overflow ${JSON.stringify(menuSize)}`);
    checks++;
    for (const action of ['Rezervasiya', 'Pul qeydi', 'Xərc', 'Tapşırıq']) {
      if (!await page.getByRole('button', { name: action }).isDisabled()) throw new Error(`${name} ${width} unsafe action ${action}`);
      checks++;
    }
    await page.keyboard.press('Escape');
    if (await page.getByRole('dialog').count() || !await page.getByRole('button', { name: 'Əlavə et' }).evaluate(el => el === document.activeElement)) throw new Error(`${name} ${width} escape focus`);
    checks++;
    await context.setOffline(true);
    await page.evaluate(() => window.dispatchEvent(new Event('offline')));
    await page.getByRole('status').getByText('Bağlantı yoxdur. Məlumat yenilənmir.').waitFor();
    checks++;
    if (errors.length) throw new Error(`${name} ${width} JS ${errors.join(',')}`);
    checks++;
    await context.close();
  }
  await browser.close();
}
console.log(`PASS ${checks} assertions; Chromium; 320/360/390/430; nav, target, menu safety, Escape focus, offline, no overflow/JS errors`);
