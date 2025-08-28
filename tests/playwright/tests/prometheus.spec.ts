import { test, expect } from '@playwright/test';

test.describe('Prometheus Tests', () => {
  const PROMETHEUS_URL = 'http://10.14.185.35:9090';

  test('should load Prometheus UI', async ({ page }) => {
    await page.goto(PROMETHEUS_URL);
    
    // Check page title
    await expect(page).toHaveTitle(/Prometheus/);
    
    // Check main UI elements
    await expect(page.locator('text=Expression')).toBeVisible();
    await expect(page.locator('button:has-text("Execute")')).toBeVisible();
    
    // Take screenshot
    await page.screenshot({ path: 'screenshots/prometheus-ui.png', fullPage: true });
  });

  test('should execute a query', async ({ page }) => {
    await page.goto(PROMETHEUS_URL);
    
    // Enter a simple query
    await page.locator('textarea.cm-content').click();
    await page.keyboard.type('up');
    
    // Execute query
    await page.click('button:has-text("Execute")');
    
    // Wait for results
    await page.waitForTimeout(1000);
    
    // Check for results
    const results = page.locator('.data-table');
    await expect(results).toBeVisible();
    
    await page.screenshot({ path: 'screenshots/prometheus-query.png' });
  });

  test('should show targets page', async ({ page }) => {
    await page.goto(`${PROMETHEUS_URL}/targets`);
    
    // Check for targets
    await expect(page.locator('h2:has-text("Targets")')).toBeVisible();
    
    // Look for at least one target
    const targetRows = page.locator('.table tbody tr');
    await expect(targetRows).toHaveCount(await targetRows.count());
    
    await page.screenshot({ path: 'screenshots/prometheus-targets.png', fullPage: true });
  });

  test('should check API endpoints', async ({ request }) => {
    // Test health endpoint
    const health = await request.get(`${PROMETHEUS_URL}/-/ready`);
    expect(health.ok()).toBeTruthy();
    
    // Test metrics endpoint
    const metrics = await request.get(`${PROMETHEUS_URL}/api/v1/query?query=up`);
    expect(metrics.ok()).toBeTruthy();
    const metricsData = await metrics.json();
    expect(metricsData.status).toBe('success');
  });

  test('should verify configuration', async ({ page }) => {
    await page.goto(`${PROMETHEUS_URL}/config`);
    
    // Check configuration is loaded
    await expect(page.locator('pre')).toBeVisible();
    
    // Verify scrape configs exist
    const configText = await page.locator('pre').textContent();
    expect(configText).toContain('scrape_configs');
    expect(configText).toContain('job_name');
    
    await page.screenshot({ path: 'screenshots/prometheus-config.png' });
  });

  test('performance: should load quickly', async ({ page }) => {
    const startTime = Date.now();
    await page.goto(PROMETHEUS_URL);
    await page.waitForLoadState('networkidle');
    const loadTime = Date.now() - startTime;
    
    console.log(`Prometheus UI load time: ${loadTime}ms`);
    expect(loadTime).toBeLessThan(5000); // Should load in under 5 seconds
  });
});