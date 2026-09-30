import { test, expect } from '@playwright/test';

// Add /docs when the Astro page exists; never accept its fallback as coverage.
const pages = [{ name: 'home', path: '/' }];
for (const route of pages) {
  test(route.name, async ({ page }) => {
    const errors: string[] = [];
    page.on('pageerror', error => errors.push(error.message));
    const response = await page.goto(route.path);
    expect(response?.status()).toBe(200);
    await expect(page.locator('h1')).toBeVisible();
    await page.evaluate(async () => {
      await document.fonts.ready;
      await Promise.all([...document.images].map(image => image.decode()));
    });
    // Opt-in fault injection proves comparisons fail without changing the site.
    if (process.env.SITE_SHOTS_MUTATE === '1') {
      await page.addStyleTag({ content: 'h1 { color: #00ff00 !important; }' });
    }
    expect(errors).toEqual([]);
    await expect(page).toHaveScreenshot(`${route.name}.png`);
  });
}
