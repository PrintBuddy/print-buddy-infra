import { defineConfig, devices } from '@playwright/test';

export default defineConfig({
    testDir: './tests',
    fullyParallel: false, // shared seeded users/balances — tests aren't independent
    forbidOnly: !!process.env.CI,
    retries: process.env.CI ? 1 : 0,
    workers: 1,
    // Default 30s is too tight for refund-flow.spec.ts, which does 2
    // logins + a print submission + a 45s wait for CUPS to actually
    // process the job through cups-pdf (jobs_updater polls every 5s, but
    // cups-pdf's own conversion adds real latency) + the refund
    // request/approval round trip on top.
    timeout: 90000,
    reporter: process.env.CI ? [['html', { open: 'never' }], ['list']] : 'list',
    use: {
        baseURL: 'http://localhost:8080',
        trace: 'retain-on-failure',
        screenshot: 'only-on-failure',
    },
    projects: [
        {
            name: 'chromium',
            use: { ...devices['Desktop Chrome'] },
        },
    ],
});
