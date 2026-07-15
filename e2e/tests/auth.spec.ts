import { test, expect } from '@playwright/test';

const USER = { username: 'e2e_user', password: 'E2ePassword123!' };

test.describe('Authentication', () => {
    test('logs in successfully with valid credentials', async ({ page }) => {
        await page.goto('/login');
        await page.getByLabel('Username').fill(USER.username);
        await page.getByLabel('Password').fill(USER.password);
        await page.getByRole('button', { name: 'Submit' }).click();

        await expect(page).toHaveURL('/');
    });

    test('shows an error and stays on the login page with the wrong password', async ({ page }) => {
        await page.goto('/login');
        await page.getByLabel('Username').fill(USER.username);
        await page.getByLabel('Password').fill('definitely-wrong-password');
        await page.getByRole('button', { name: 'Submit' }).click();

        await expect(page.getByText('Incorrect username or password!')).toBeVisible();
        await expect(page).toHaveURL(/\/login$/);
    });
});
