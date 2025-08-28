import { test, expect } from '@playwright/test';

test.describe('Caddy Ingress Tests', () => {
  const CADDY_URL = 'http://10.14.185.67';

  test('should serve default page', async ({ page }) => {
    await page.goto(CADDY_URL);
    
    // Check response
    await expect(page.locator('text=Caddy')).toBeVisible();
    
    await page.screenshot({ path: 'screenshots/caddy-default.png' });
  });

  test('should return correct headers', async ({ request }) => {
    const response = await request.get(CADDY_URL);
    expect(response.ok()).toBeTruthy();
    
    // Check for Caddy server header
    const headers = response.headers();
    expect(headers['server']).toContain('Caddy');
  });

  test('should handle 404 properly', async ({ page }) => {
    const response = await page.goto(`${CADDY_URL}/nonexistent-page`);
    
    // Caddy should return 404
    expect(response?.status()).toBe(404);
  });

  test('performance: should respond quickly', async ({ request }) => {
    const times = [];
    
    // Test 10 requests
    for (let i = 0; i < 10; i++) {
      const startTime = Date.now();
      const response = await request.get(CADDY_URL);
      const responseTime = Date.now() - startTime;
      times.push(responseTime);
      expect(response.ok()).toBeTruthy();
    }
    
    const avgTime = times.reduce((a, b) => a + b, 0) / times.length;
    console.log(`Caddy average response time: ${avgTime}ms`);
    expect(avgTime).toBeLessThan(500); // Average should be under 500ms
  });

  test('should handle concurrent requests', async ({ request }) => {
    // Send 20 concurrent requests
    const promises = [];
    for (let i = 0; i < 20; i++) {
      promises.push(request.get(CADDY_URL));
    }
    
    const responses = await Promise.all(promises);
    
    // All should succeed
    for (const response of responses) {
      expect(response.ok()).toBeTruthy();
    }
  });
});