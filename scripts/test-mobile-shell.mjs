import { chromium } from 'playwright';
import AxeBuilder from '@axe-core/playwright';
const base = process.env.EVE_TEST_BASE_URL ?? 'http://localhost:4177';
let checks = 0;
for (const [name, engine] of [['Google Chrome', chromium]]) {
  const browser = await engine.launch({ headless: true, ...(process.env.EVE_BROWSER_EXECUTABLE ? { executablePath: process.env.EVE_BROWSER_EXECUTABLE } : {}) });
  for (const width of [320, 360, 390, 430]) {
    const context = await browser.newContext({ viewport: { width, height: 740 }, reducedMotion: 'reduce', isMobile: true, hasTouch: true });
    const page = await context.newPage();
    const cdp = await context.newCDPSession(page);
    await cdp.send('Emulation.setSafeAreaInsetsOverride', { insets: { top: 24, right: 0, bottom: 34, left: 0 } });
    const errors = [];
    page.on('pageerror', e => errors.push(e.message));
    await page.goto(base + '/today');
    await page.getByRole('heading', { name: 'Bu gün', exact: true }).waitFor();
    await page.waitForFunction(() => Object.keys(document.querySelector('button[aria-label="Əlavə et"]') ?? {}).some(key => key.startsWith('__reactProps$')));
    const safeArea = await page.evaluate(() => ({
      viewportFit: document.querySelector('meta[name="viewport"]')?.content.includes('viewport-fit=cover') ?? false,
      shellBottom: parseFloat(getComputedStyle(document.querySelector('.app-shell')).paddingBottom),
      navBottom: parseFloat(getComputedStyle(document.querySelector('.bottom-nav')).paddingBottom),
      actionBottom: parseFloat(getComputedStyle(document.querySelector('.action-area')).bottom),
    }));
    if (!safeArea.viewportFit || safeArea.shellBottom < 122 || safeArea.navBottom < 42 || safeArea.actionBottom < 120) {
      throw new Error(`${name} ${width} safe-area inset not applied ${JSON.stringify(safeArea)}`);
    }
    checks++;
    const axTree = await cdp.send('Accessibility.getFullAXTree');
    const axNames = axTree.nodes.map(node => node.name?.value).filter(Boolean);
    const axRoles = axTree.nodes.map(node => node.role?.value);
    if (!axRoles.includes('navigation') || !axNames.includes('Əsas mobil naviqasiya')) {
      throw new Error(`${name} ${width} mobile navigation missing from accessibility tree`);
    }
    checks++;
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
      const audit = await new AxeBuilder({ page }).withTags(['wcag2a', 'wcag2aa', 'wcag21a', 'wcag21aa', 'wcag22aa']).analyze();
      if (audit.violations.length) throw new Error(`${name} ${width} ${label} axe: ${audit.violations.map(v => v.id + ':' + v.nodes.length).join(',')}`);
      checks += 3;
    }
    const plus = page.getByRole('button', { name: 'Əlavə et' });
    await plus.focus();
    await page.keyboard.press('Enter');
    await page.getByRole('dialog', { name: 'Yeni əməliyyat' }).waitFor();
    const menuAx = await cdp.send('Accessibility.getFullAXTree');
    if (!menuAx.nodes.some(node => node.role?.value === 'dialog' && node.name?.value === 'Yeni əməliyyat')) {
      throw new Error(`${name} ${width} action menu missing from accessibility tree`);
    }
    checks++;
    const menuSize = await page.evaluate(() => ({ doc: document.documentElement.scrollWidth, body: document.body.scrollWidth }));
    if (menuSize.doc > width || menuSize.body > width) throw new Error(`${name} ${width} menu overflow ${JSON.stringify(menuSize)}`);
    const menuAudit = await new AxeBuilder({ page }).withTags(['wcag2a', 'wcag2aa', 'wcag21a', 'wcag21aa', 'wcag22aa']).analyze();
    if (menuAudit.violations.length) throw new Error(`${name} ${width} menu axe: ${menuAudit.violations.map(v => v.id + ':' + v.nodes.length).join(',')}`);
    checks += 2;
    for (const action of ['Rezervasiya', 'Pul qeydi', 'Xərc', 'Tapşırıq']) {
      if (!await page.getByRole('button', { name: action }).isDisabled()) throw new Error(`${name} ${width} unsafe action ${action}`);
      checks++;
    }
    await page.setViewportSize({ width, height: 420 });
    const keyboardViewport = await page.evaluate(() => {
      const menu = document.querySelector('.action-menu').getBoundingClientRect();
      const nav = document.querySelector('.bottom-nav').getBoundingClientRect();
      return { height: innerHeight, menuTop: menu.top, menuBottom: menu.bottom, navTop: nav.top };
    });
    if (keyboardViewport.menuTop < 24 || keyboardViewport.menuBottom > keyboardViewport.navTop) {
      throw new Error(`${name} ${width} reduced keyboard viewport clips or overlaps menu ${JSON.stringify(keyboardViewport)}`);
    }
    checks++;
    await page.setViewportSize({ width, height: 740 });
    await page.keyboard.press('Escape');
    if (await page.getByRole('dialog').count() || !await plus.evaluate(el => el === document.activeElement)) throw new Error(`${name} ${width} escape focus`);
    checks++;
    await page.keyboard.press('Tab');
    const focusedNav = await page.evaluate(() => document.activeElement?.textContent?.trim());
    if (focusedNav !== 'Bu gün') throw new Error(`${name} ${width} tab focus ${focusedNav}`);
    await page.keyboard.press('Enter');
    await page.waitForURL('**/today');
    checks += 2;
    const missing = await page.goto(base + '/this-route-does-not-exist');
    if (missing?.status() !== 404) throw new Error(`${name} ${width} missing route status ${missing?.status()}`);
    checks++;
    await page.getByRole('heading', { name: 'Səhifə tapılmadı' }).waitFor();
    const errorAx = await cdp.send('Accessibility.getFullAXTree');
    if (!errorAx.nodes.some(node => node.role?.value === 'heading' && node.name?.value === 'Səhifə tapılmadı')) {
      throw new Error(`${name} ${width} 404 heading missing from accessibility tree`);
    }
    checks++;
    const errorSize = await page.evaluate(() => ({ doc: document.documentElement.scrollWidth, body: document.body.scrollWidth }));
    if (errorSize.doc > width || errorSize.body > width) throw new Error(`${name} ${width} error overflow ${JSON.stringify(errorSize)}`);
    checks++;
    const errorAudit = await new AxeBuilder({ page }).withTags(['wcag2a', 'wcag2aa', 'wcag21a', 'wcag21aa', 'wcag22aa']).analyze();
    if (errorAudit.violations.length) throw new Error(`${name} ${width} error axe: ${errorAudit.violations.map(v => v.id + ':' + v.nodes.length).join(',')}`);
    checks++;
    const returnLink = page.getByRole('link', { name: 'Bu günə qayıt' });
    const returnBox = await returnLink.boundingBox();
    if (!returnBox || returnBox.width < 44 || returnBox.height < 44) throw new Error(`${name} ${width} error return target`);
    checks++;
    await returnLink.focus();
    await page.keyboard.press('Enter');
    await page.waitForURL('**/today');
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
console.log(`PASS ${checks} assertions; Chromium mobile emulation; 320/360/390/430; safe-area inset; accessibility tree nav/dialog/error; 404 recovery; target; keyboard Enter/Tab/Escape; axe WCAG; menu safety; offline; no overflow/JS errors`);
