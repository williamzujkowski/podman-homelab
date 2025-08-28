import { test, expect } from '@playwright/test';

test.describe('Grafana Tests', () => {
  const GRAFANA_URL = 'http://10.14.185.35:3000';
  
  test('should load Grafana login page', async ({ page }) => {
    await page.goto(GRAFANA_URL);
    
    // Check for login form
    await expect(page.locator('input[name="user"]')).toBeVisible();
    await expect(page.locator('input[name="password"]')).toBeVisible();
    await expect(page.locator('button:has-text("Log in")')).toBeVisible();
    
    await page.screenshot({ path: 'screenshots/grafana-login.png' });
  });

  test('should login to Grafana', async ({ page }) => {
    await page.goto(GRAFANA_URL);
    
    // Login with default credentials
    await page.fill('input[name="user"]', 'admin');
    await page.fill('input[name="password"]', 'admin');
    await page.click('button:has-text("Log in")');
    
    // Skip password change if prompted
    const skipButton = page.locator('button:has-text("Skip")');
    if (await skipButton.isVisible({ timeout: 3000 }).catch(() => false)) {
      await skipButton.click();
    }
    
    // Check we're logged in
    await expect(page.locator('text=Welcome to Grafana')).toBeVisible({ timeout: 10000 });
    
    await page.screenshot({ path: 'screenshots/grafana-dashboard.png', fullPage: true });
  });

  test('should check datasources', async ({ page }) => {
    await page.goto(GRAFANA_URL);
    
    // Login
    await page.fill('input[name="user"]', 'admin');
    await page.fill('input[name="password"]', 'admin');
    await page.click('button:has-text("Log in")');
    
    // Skip password change if needed
    const skipButton = page.locator('button:has-text("Skip")');
    if (await skipButton.isVisible({ timeout: 3000 }).catch(() => false)) {
      await skipButton.click();
    }
    
    // Navigate to datasources
    await page.goto(`${GRAFANA_URL}/datasources`);
    
    // Check for Prometheus datasource
    await expect(page.locator('text=Prometheus')).toBeVisible({ timeout: 10000 });
    
    // Check for Loki datasource
    await expect(page.locator('text=Loki')).toBeVisible({ timeout: 10000 });
    
    await page.screenshot({ path: 'screenshots/grafana-datasources.png', fullPage: true });
  });

  test('should check API health', async ({ request }) => {
    const health = await request.get(`${GRAFANA_URL}/api/health`);
    expect(health.ok()).toBeTruthy();
    
    const healthData = await health.json();
    expect(healthData.database).toBe('ok');
  });

  test('should navigate to explore page', async ({ page }) => {
    await page.goto(GRAFANA_URL);
    
    // Login
    await page.fill('input[name="user"]', 'admin');
    await page.fill('input[name="password"]', 'admin');
    await page.click('button:has-text("Log in")');
    
    // Skip password change if needed
    const skipButton = page.locator('button:has-text("Skip")');
    if (await skipButton.isVisible({ timeout: 3000 }).catch(() => false)) {
      await skipButton.click();
    }
    
    // Navigate to Explore
    await page.goto(`${GRAFANA_URL}/explore`);
    
    // Check explore page loaded
    await expect(page.locator('text=Explore')).toBeVisible({ timeout: 10000 });
    
    await page.screenshot({ path: 'screenshots/grafana-explore.png', fullPage: true });
  });

  test('performance: should load dashboard quickly', async ({ page }) => {
    const startTime = Date.now();
    await page.goto(GRAFANA_URL);
    await page.waitForLoadState('networkidle');
    const loadTime = Date.now() - startTime;
    
    console.log(`Grafana load time: ${loadTime}ms`);
    expect(loadTime).toBeLessThan(5000);
  });
});