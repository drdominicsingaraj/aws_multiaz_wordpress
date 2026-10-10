import { test, expect } from '@playwright/test';

// These tests need a deployed environment. Without SITE_URL they are skipped.
test.skip(!process.env.SITE_URL, 'SITE_URL not set (no deployed environment)');

test('HTTP redirects to HTTPS', async ({ request }) => {
  const http = process.env.SITE_URL!.replace(/^https:/, 'http:');
  const res = await request.get(http, { maxRedirects: 0 });
  expect([301, 302, 307, 308]).toContain(res.status());
  expect(res.headers()['location']).toMatch(/^https:/);
});

test('site loads over HTTPS and serves WordPress', async ({ page }) => {
  const res = await page.goto('/');
  expect(res?.ok()).toBeTruthy();
  // A fresh install redirects to the installer; a configured one serves the site.
  const html = await page.content();
  expect(html).toMatch(/wp-content|wp-includes|wp-admin/i);
});

test('static assets are served', async ({ request }) => {
  const res = await request.get('/wp-includes/js/jquery/jquery.min.js');
  expect(res.status()).toBe(200);
});
