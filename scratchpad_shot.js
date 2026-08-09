const { chromium } = require('playwright');
(async () => {
  const browser = await chromium.launch({ executablePath: '/opt/pw-browsers/chromium' });
  const page = await browser.newPage({ viewport: { width: 1440, height: 900 } });
  await page.goto('http://localhost:3101/', { waitUntil: 'networkidle' });
  await page.screenshot({ path: '/tmp/home-desktop.png', fullPage: true });
  await page.setViewportSize({ width: 390, height: 844 });
  await page.screenshot({ path: '/tmp/home-mobile.png', fullPage: true });
  await page.goto('http://localhost:3101/pricing', { waitUntil: 'networkidle' });
  await page.setViewportSize({ width: 1440, height: 900 });
  await page.screenshot({ path: '/tmp/pricing.png', fullPage: true });
  await browser.close();
})();
