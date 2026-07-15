import { test, expect } from '@playwright/test';
import { login, readBalance, submitTestPrintJob, waitForJobCompleted, USER, ADMIN } from './helpers';

// Unique per run so re-executing this spec against a stack that wasn't
// torn down (e.g. manual local reruns) doesn't produce ambiguous
// duplicate-row matches later in this test.
const FILENAME = `e2e-refund-flow-${Date.now()}.png`;

test('a completed job can be refunded and the balance is restored', async ({ browser }) => {
    // Two separate sessions — the regular user requests the refund, the
    // admin approves it — rather than logging one page in and out twice.
    const userContext = await browser.newContext();
    const adminContext = await browser.newContext();
    const userPage = await userContext.newPage();
    const adminPage = await adminContext.newPage();

    await login(userPage, USER);
    const before = await readBalance(userPage);

    await submitTestPrintJob(userPage, FILENAME);
    const afterPrint = await readBalance(userPage);
    expect(afterPrint).toBeCloseTo(before - 0.10, 2);

    const row = await waitForJobCompleted(userPage, FILENAME);
    await row.getByRole('button', { name: 'Request refund' }).click();
    await userPage.getByLabel(/Reason for refund/i).fill('E2E refund test');
    await userPage.getByRole('button', { name: 'Submit Request' }).click();
    await expect(userPage.getByText(/Submit Request/)).not.toBeVisible();

    // Admin approves it
    await login(adminPage, ADMIN);
    await adminPage.goto('/admin/refunds');
    const refundRow = adminPage.locator('tr', { hasText: FILENAME });
    await refundRow.getByRole('button', { name: 'Resolve request' }).click();
    await adminPage.getByRole('button', { name: 'Approve' }).click();
    await expect(adminPage.getByRole('button', { name: 'Approve' })).not.toBeVisible();

    // Balance restored to the pre-print amount — the refund credit path
    // (adjust_balance, credited *before* the request is marked resolved).
    const afterRefund = await readBalance(userPage);
    expect(afterRefund).toBeCloseTo(before, 2);
});
