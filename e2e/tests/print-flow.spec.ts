import { test, expect } from '@playwright/test';
import { login, readBalance, submitTestPrintJob, USER } from './helpers';

test('a full print submission debits the printer\'s exact price', async ({ page }) => {
    await login(page, USER);

    const before = await readBalance(page);

    await submitTestPrintJob(page, 'e2e-print-flow.png');

    // Locks in the exact debit — the money path this whole engagement's
    // security work (atomic adjust_balance, negative-copies fix) protects.
    const after = await readBalance(page);
    expect(after).toBeCloseTo(before - 0.10, 2);
});
