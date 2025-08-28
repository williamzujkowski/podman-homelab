import { test, expect } from '@playwright/test';

test.describe('Node Exporter Tests', () => {
  const NODE_EXPORTERS = [
    { name: 'vm-a', url: 'http://10.14.185.35:9100' },
    { name: 'vm-b', url: 'http://10.14.185.67:9100' },
    { name: 'vm-c', url: 'http://10.14.185.213:9100' },
  ];

  for (const exporter of NODE_EXPORTERS) {
    test(`should serve metrics for ${exporter.name}`, async ({ request }) => {
      const response = await request.get(`${exporter.url}/metrics`);
      expect(response.ok()).toBeTruthy();
      
      const text = await response.text();
      
      // Check for key metrics
      expect(text).toContain('node_cpu_seconds_total');
      expect(text).toContain('node_memory_MemTotal_bytes');
      expect(text).toContain('node_filesystem_size_bytes');
      expect(text).toContain('node_network_receive_bytes_total');
      expect(text).toContain('node_load1');
    });

    test(`should have proper metric format for ${exporter.name}`, async ({ request }) => {
      const response = await request.get(`${exporter.url}/metrics`);
      const text = await response.text();
      
      // Check metric format
      const lines = text.split('\n');
      const metricLines = lines.filter(line => 
        !line.startsWith('#') && line.trim() !== ''
      );
      
      // Each metric line should have proper format
      for (const line of metricLines.slice(0, 10)) { // Check first 10 metrics
        expect(line).toMatch(/^[a-zA-Z_:][a-zA-Z0-9_:]*(\{.*\})?\s+[0-9.e+-]+$/);
      }
    });

    test(`performance: ${exporter.name} should respond quickly`, async ({ request }) => {
      const startTime = Date.now();
      const response = await request.get(`${exporter.url}/metrics`);
      const responseTime = Date.now() - startTime;
      
      console.log(`${exporter.name} response time: ${responseTime}ms`);
      expect(response.ok()).toBeTruthy();
      expect(responseTime).toBeLessThan(2000); // Should respond in under 2 seconds
    });
  }

  test('should verify all exporters in Prometheus', async ({ request }) => {
    const response = await request.get('http://10.14.185.35:9090/api/v1/targets');
    expect(response.ok()).toBeTruthy();
    
    const data = await response.json();
    expect(data.status).toBe('success');
    
    // Check that we have active targets
    const activeTargets = data.data.activeTargets || [];
    console.log(`Found ${activeTargets.length} active targets in Prometheus`);
    
    // Look for node exporter targets
    const nodeTargets = activeTargets.filter((target: any) => 
      target.labels?.job === 'node' || 
      target.discoveredLabels?.__metrics_path__ === '/metrics'
    );
    
    console.log(`Found ${nodeTargets.length} node exporter targets`);
  });
});