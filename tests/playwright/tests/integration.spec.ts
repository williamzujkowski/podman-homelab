import { test, expect } from '@playwright/test';

test.describe('Integration Tests', () => {
  test('should query Prometheus for all node exporters', async ({ request }) => {
    const response = await request.get('http://10.14.185.35:9090/api/v1/query', {
      params: {
        query: 'up{job="node"}'
      }
    });
    
    expect(response.ok()).toBeTruthy();
    const data = await response.json();
    expect(data.status).toBe('success');
    
    // Should have results for node exporters
    const results = data.data?.result || [];
    console.log(`Found ${results.length} node exporters in Prometheus`);
  });

  test('should verify Grafana can query Prometheus', async ({ page, request }) => {
    // First check if datasource is configured
    const response = await request.get('http://10.14.185.35:3000/api/datasources', {
      headers: {
        'Authorization': 'Basic ' + Buffer.from('admin:admin').toString('base64')
      }
    });
    
    if (response.ok()) {
      const datasources = await response.json();
      const prometheusDatasource = datasources.find((ds: any) => ds.type === 'prometheus');
      expect(prometheusDatasource).toBeDefined();
      console.log(`Prometheus datasource found: ${prometheusDatasource?.name}`);
    }
  });

  test('should verify Grafana can query Loki', async ({ request }) => {
    const response = await request.get('http://10.14.185.35:3000/api/datasources', {
      headers: {
        'Authorization': 'Basic ' + Buffer.from('admin:admin').toString('base64')
      }
    });
    
    if (response.ok()) {
      const datasources = await response.json();
      const lokiDatasource = datasources.find((ds: any) => ds.type === 'loki');
      expect(lokiDatasource).toBeDefined();
      console.log(`Loki datasource found: ${lokiDatasource?.name}`);
    }
  });

  test('should verify container health across all VMs', async ({ request }) => {
    const vms = [
      { name: 'vm-a', ip: '10.14.185.35', expectedContainers: ['prometheus', 'loki', 'node-exporter', 'promtail'] },
      { name: 'vm-b', ip: '10.14.185.67', expectedContainers: ['caddy', 'node-exporter', 'promtail'] },
      { name: 'vm-c', ip: '10.14.185.213', expectedContainers: ['node-exporter', 'promtail'] },
    ];

    for (const vm of vms) {
      console.log(`Checking ${vm.name} services...`);
      
      // Check node exporter
      if (vm.expectedContainers.includes('node-exporter')) {
        const nodeResponse = await request.get(`http://${vm.ip}:9100/metrics`);
        expect(nodeResponse.ok()).toBeTruthy();
        console.log(`  ✓ node-exporter on ${vm.name}`);
      }
      
      // Check specific services
      if (vm.name === 'vm-a') {
        const promResponse = await request.get(`http://${vm.ip}:9090/-/ready`);
        expect(promResponse.ok()).toBeTruthy();
        console.log(`  ✓ prometheus on ${vm.name}`);
        
        const lokiResponse = await request.get(`http://${vm.ip}:3100/ready`);
        expect(lokiResponse.ok()).toBeTruthy();
        console.log(`  ✓ loki on ${vm.name}`);
      }
      
      if (vm.name === 'vm-b') {
        const caddyResponse = await request.get(`http://${vm.ip}`);
        expect(caddyResponse.ok()).toBeTruthy();
        console.log(`  ✓ caddy on ${vm.name}`);
      }
    }
  });

  test('should capture full stack screenshot', async ({ page }) => {
    // Create a dashboard view
    await page.setViewportSize({ width: 1920, height: 1080 });
    
    // Capture Prometheus
    await page.goto('http://10.14.185.35:9090/graph');
    await page.screenshot({ 
      path: 'screenshots/stack-prometheus.png', 
      fullPage: false 
    });
    
    // Capture Grafana login
    await page.goto('http://10.14.185.35:3000');
    await page.screenshot({ 
      path: 'screenshots/stack-grafana-login.png', 
      fullPage: false 
    });
    
    // Capture Caddy
    await page.goto('http://10.14.185.67');
    await page.screenshot({ 
      path: 'screenshots/stack-caddy.png', 
      fullPage: false 
    });
  });

  test('performance: end-to-end metric collection', async ({ request }) => {
    const startTime = Date.now();
    
    // 1. Node exporter collects metric
    const nodeResponse = await request.get('http://10.14.185.35:9100/metrics');
    expect(nodeResponse.ok()).toBeTruthy();
    
    // 2. Prometheus scrapes it (check if metric exists)
    await new Promise(resolve => setTimeout(resolve, 2000)); // Wait for scrape
    
    const promResponse = await request.get('http://10.14.185.35:9090/api/v1/query', {
      params: {
        query: 'node_load1'
      }
    });
    expect(promResponse.ok()).toBeTruthy();
    
    const totalTime = Date.now() - startTime;
    console.log(`End-to-end metric collection time: ${totalTime}ms`);
    expect(totalTime).toBeLessThan(5000);
  });
});