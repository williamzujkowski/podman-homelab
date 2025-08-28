import { test, expect } from '@playwright/test';

test.describe('Loki Tests', () => {
  const LOKI_URL = 'http://10.14.185.35:3100';

  test('should check Loki ready endpoint', async ({ request }) => {
    const response = await request.get(`${LOKI_URL}/ready`);
    expect(response.ok()).toBeTruthy();
    
    const text = await response.text();
    expect(text).toContain('ready');
  });

  test('should check Loki metrics endpoint', async ({ request }) => {
    const response = await request.get(`${LOKI_URL}/metrics`);
    expect(response.ok()).toBeTruthy();
    
    const text = await response.text();
    expect(text).toContain('loki_');
    expect(text).toContain('go_');
  });

  test('should query logs via API', async ({ request }) => {
    // Query for recent logs
    const response = await request.get(`${LOKI_URL}/loki/api/v1/query_range`, {
      params: {
        query: '{job="systemd-journal"}',
        limit: 10,
        start: (Date.now() - 3600000) * 1000000, // Last hour in nanoseconds
        end: Date.now() * 1000000,
      }
    });
    
    expect(response.ok()).toBeTruthy();
    
    const data = await response.json();
    expect(data.status).toBe('success');
  });

  test('should check API labels', async ({ request }) => {
    const response = await request.get(`${LOKI_URL}/loki/api/v1/labels`);
    expect(response.ok()).toBeTruthy();
    
    const data = await response.json();
    expect(data.status).toBe('success');
    expect(Array.isArray(data.data)).toBeTruthy();
  });

  test('performance: API response time', async ({ request }) => {
    const startTime = Date.now();
    const response = await request.get(`${LOKI_URL}/ready`);
    const responseTime = Date.now() - startTime;
    
    console.log(`Loki ready endpoint response time: ${responseTime}ms`);
    expect(response.ok()).toBeTruthy();
    expect(responseTime).toBeLessThan(1000); // Should respond in under 1 second
  });
});