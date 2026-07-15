import { test, expect } from '@playwright/test';
import { login, ADMIN, USER } from './helpers';

test('an admin can see the seeded user in the user directory', async ({ page }) => {
    await login(page, ADMIN);

    await page.goto('/admin/users');

    const row = page.locator('tr', { hasText: USER.username });
    await expect(row).toBeVisible();
    // Balance isn't asserted to an exact value here — print-flow/refund-flow
    // specs mutate e2e_user's balance and file-execution order isn't
    // guaranteed — just that a real, formatted balance renders.
    await expect(row).toContainText('€');
});
