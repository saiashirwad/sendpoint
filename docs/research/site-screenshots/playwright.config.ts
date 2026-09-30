import { defineConfig } from '@playwright/test';
import { resolve } from 'node:path';

const build = resolve(import.meta.dirname, '../../../.build');
const baseURL = `http://127.0.0.1:${process.env.SITE_SHOTS_PORT || 43932}`;
export default defineConfig({
  testDir: '.',
  testMatch: 'site.spec.ts',
  workers: 1,
  retries: 0,
  reporter: 'line',
  outputDir: `${build}/site-shots-diff`,
  snapshotPathTemplate: `${build}/site-shots/{platform}/{projectName}/{arg}{ext}`,
  expect: { toHaveScreenshot: { fullPage: true, animations: 'disabled', caret: 'hide', maxDiffPixels: 0 } },
  use: {
    browserName: 'chromium', baseURL, deviceScaleFactor: 1,
    reducedMotion: 'reduce', locale: 'en-US', timezoneId: 'UTC',
    trace: 'retain-on-failure',
  },
  projects: ['light', 'dark'].flatMap(colorScheme => [
    { name: `desktop-${colorScheme}`, use: { colorScheme: colorScheme as 'light' | 'dark', viewport: { width: 1440, height: 1000 } } },
    { name: `phone-${colorScheme}`, use: { colorScheme: colorScheme as 'light' | 'dark', viewport: { width: 390, height: 844 } } },
  ]),
  webServer: {
    command: 'bun server.ts', url: baseURL, reuseExistingServer: false,
    stdout: 'pipe', stderr: 'pipe',
    gracefulShutdown: { signal: 'SIGTERM', timeout: 1000 },
  },
});
