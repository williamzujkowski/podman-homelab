# Documentation Directory

This directory contains comprehensive documentation for the homelab infrastructure deployment.

## Primary Documentation

### [FINAL_DEPLOYMENT_REPORT.md](FINAL_DEPLOYMENT_REPORT.md)
**The definitive infrastructure status report**
- Complete service inventory with versions and endpoints
- Network architecture and security configuration  
- Operational procedures and maintenance tasks
- Performance metrics and compliance status
- Future roadmap and enhancement plans

### [DEPLOYMENT_STATUS.md](DEPLOYMENT_STATUS.md)
**Current deployment status summary**
- Real-time service status and health checks
- Access methods and authentication status
- Recent deployment activities and next steps
- Quick reference for daily operations

## Operations Documentation

### [operations/OPERATIONAL_RUNBOOK.md](operations/OPERATIONAL_RUNBOOK.md)
**Daily operations and troubleshooting guide**
- Daily health check procedures (5 minutes)
- Emergency response procedures
- Service management and configuration
- Backup and recovery procedures
- Troubleshooting guides for common issues
- Maintenance schedules and change management

## Service-Specific Documentation

### [services/AUTHENTIK_OAUTH2_INTEGRATION_REPORT.md](services/AUTHENTIK_OAUTH2_INTEGRATION_REPORT.md)
**OAuth2 and SSO integration guide**
- Authentik deployment status
- OAuth2 provider configuration steps
- Grafana integration procedures
- Troubleshooting authentication issues

### [services/CLOUDFLARE_INTEGRATION.md](services/CLOUDFLARE_INTEGRATION.md)
**Certificate management and DNS configuration**
- Let's Encrypt certificate setup
- Cloudflare DNS-01 challenge configuration
- Certificate renewal automation
- Traefik integration procedures

### [services/AUTHENTIK_CONFIGURATION_REPORT.md](services/AUTHENTIK_CONFIGURATION_REPORT.md)
**Identity provider configuration**
- Authentik deployment details
- Database and cache configuration
- User management procedures
- Integration with other services

## Legacy Documentation

The `legacy/` directory contains historical documentation that has been superseded by the current comprehensive documentation but is retained for reference:

- `PRODUCTION_DEPLOYMENT_SUMMARY.md`: Previous deployment summary
- `REPOSITORY_CLEANUP_RECOMMENDATIONS.md`: Historical cleanup recommendations  
- `CLOUDFLARE_CONFIG_PLAN.md`: Original certificate planning document

## Quick Navigation

For most operational needs, start with:
1. **[DEPLOYMENT_STATUS.md](DEPLOYMENT_STATUS.md)** - Current system status
2. **[operations/OPERATIONAL_RUNBOOK.md](operations/OPERATIONAL_RUNBOOK.md)** - Daily procedures
3. **[FINAL_DEPLOYMENT_REPORT.md](FINAL_DEPLOYMENT_REPORT.md)** - Comprehensive reference

For authentication setup:
1. **[services/AUTHENTIK_OAUTH2_INTEGRATION_REPORT.md](services/AUTHENTIK_OAUTH2_INTEGRATION_REPORT.md)** - OAuth2 setup guide

For certificate management:
1. **[services/CLOUDFLARE_INTEGRATION.md](services/CLOUDFLARE_INTEGRATION.md)** - Certificate procedures

---

**Documentation Status**: Complete and current as of September 4, 2025  
**Next Review**: After OAuth2 configuration completion  
**Maintenance**: Update documentation with any infrastructure changes