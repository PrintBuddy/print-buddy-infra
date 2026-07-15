import { expect, Page } from '@playwright/test';

export const USER = { username: 'e2e_user', password: 'E2ePassword123!' };
export const ADMIN = { username: 'e2e_admin', password: 'E2ePassword123!' };

// Smallest possible valid PNG (a 1x1 transparent pixel) — avoids needing a
// binary fixture file in the repo. Only PDF/PNG/JPEG uploads are accepted
// (backend's FileManager.extensions whitelist) and a PNG needs no
// page-count parsing (file_manager.get_total_pages defaults any non-PDF
// file to 1 page), so this is the simplest fixture that satisfies both.
const TEST_PNG_BASE64 =
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=';

export async function login(page: Page, creds: { username: string; password: string }) {
    await page.goto('/login');
    await page.getByLabel('Username').fill(creds.username);
    await page.getByLabel('Password').fill(creds.password);
    await page.getByRole('button', { name: 'Submit' }).click();
    await expect(page).toHaveURL('/');
}

export async function readBalance(page: Page): Promise<number> {
    await page.goto('/balance');
    // BalanceHeader renders the amount as an <h5>; the page's own "My
    // Balance" title is also an h5, so disambiguate by content.
    const text = await page.locator('h5').filter({ hasText: '€' }).textContent();
    return parseFloat((text ?? '').replace('€', '').trim());
}

// Uploads a uniquely-named file, sends it to the seeded "PDF" printer
// (€0.10/page — see seed.py), and waits for the queued confirmation.
// Assumes the caller is already logged in as `e2e_user`.
export async function submitTestPrintJob(page: Page, filename: string) {
    await page.goto('/print');

    await page.locator('input[type="file"]').setInputFiles({
        name: filename,
        mimeType: 'image/png',
        buffer: Buffer.from(TEST_PNG_BASE64, 'base64'),
    });
    await page.getByText(filename).click();
    await page.getByRole('button', { name: 'Next' }).click();

    await page.getByText('PDF', { exact: true }).click();
    await page.getByRole('button', { name: 'Next' }).click();

    await page.getByRole('button', { name: 'Next' }).click(); // print prefs, defaults are valid

    await page.getByRole('button', { name: 'Send' }).click();
    await expect(page.getByText(/queued/i)).toBeVisible({ timeout: 15000 });
    await expect(page).toHaveURL('/');
}

// Polls the History page until the given job's row shows COMPLETED —
// backend's jobs_updater scheduler job syncs CUPS job status every few
// seconds, so completion isn't instant with the print submission itself.
export async function waitForJobCompleted(page: Page, filename: string, timeoutMs = 30000) {
    await page.goto('/history');
    const row = page.locator('tr', { hasText: filename });
    await expect(row).toContainText('COMPLETED', { timeout: timeoutMs });
    return row;
}
