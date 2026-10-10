import { defineConfig } from '@playwright/test';

// SITE_URL is the CloudFront domain (terraform output site_url), e.g. https://dxxxx.cloudfront.net
export default defineConfig({
  testDir: './tests',
  timeout: 30_000,
  retries: 1,
  reporter: [['list'], ['html', { open: 'never' }]],
  use: {
    baseURL: process.env.SITE_URL,
    ignoreHTTPSErrors: false,
  },
});
