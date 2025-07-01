# 🌍 Multi-Region Scale Unit Architecture

This project implements a highly available, multi-region Flask application with automatic failover and global load balancing using Azure services.

## 🏗️ Architecture Overview

### Production Environment (`envType = 'prod'`)
```
┌─────────────────────────────────────────────────────────────────────┐
│                           Azure Front Door                          │
│                    (Global Load Balancer + CDN)                     │
└─────────────┬───────────────────────────────────┬───────────────────┘
              │                                   │
    ┌─────────▼─────────┐                ┌─────────▼─────────┐
    │   PRIMARY REGION  │                │  SECONDARY REGION │
    │                   │                │                   │
    │  ┌─────────────┐  │                │  ┌─────────────┐  │
    │  │ App Service │  │                │  │ App Service │  │
    │  │ (VNet Integ)│  │                │  │ (VNet Integ)│  │
    │  └──────┬──────┘  │                │  └──────┬──────┘  │
    │         │         │                │         │         │
    │  ┌──────▼──────┐  │                │  ┌──────▼──────┐  │
    │  │ VNet + Priv │  │                │  │ VNet + Priv │  │
    │  │ Endpoints   │  │                │  │ Endpoints   │  │
    │  └──────┬──────┘  │                │  └──────┬──────┘  │
    │         │         │                │         │         │
    │  ┌──────▼──────┐  │                │  ┌──────▼──────┐  │
    │  │ Storage     │  │                │  │ Storage     │  │
    │  │ (Private)   │  │                │  │ (Private)   │  │
    │  └─────────────┘  │                │  └─────────────┘  │
    └───────────────────┘                └───────────────────┘
              │                                   │
              └─────────────┬─────────────────────┘
                            │
                   ┌────────▼────────┐
                   │ Global Storage  │
                   │ (Shared Config) │
                   └─────────────────┘
```

### Development Environment (`envType = 'dev'`)
```
┌─────────────────────────────────────────────────────────────────────┐
│                           Azure Front Door                          │
│                    (Global Load Balancer + CDN)                     │
└─────────────┬───────────────────────────────────┬───────────────────┘
              │                                   │
    ┌─────────▼─────────┐                ┌─────────▼─────────┐
    │   PRIMARY REGION  │                │  SECONDARY REGION │
    │                   │                │                   │
    │  ┌─────────────┐  │                │  ┌─────────────┐  │
    │  │ App Service │  │                │  │ App Service │  │
    │  │ (Simplified)│  │                │  │ (Simplified)│  │
    │  └──────┬──────┘  │                │  └──────┬──────┘  │
    │         │         │                │         │         │
    │  ┌──────▼──────┐  │                │  ┌──────▼──────┐  │
    │  │ Storage     │  │                │  │ Storage     │  │
    │  │ (Public +   │  │                │  │ (Public +   │  │
    │  │  MI Auth)   │  │                │  │  MI Auth)   │  │
    │  └─────────────┘  │                │  └─────────────┘  │
    └───────────────────┘                └───────────────────┘
```

## 🚀 Quick Start

### Prerequisites
- [Azure Developer CLI (azd)](https://learn.microsoft.com/azure/developer/azure-developer-cli/install-azd)
- [Azure CLI](https://docs.microsoft.com/cli/azure/install-azure-cli)
- Azure subscription with appropriate permissions

### 1. Deploy Development Environment (Simplified)
```powershell
# Run the deployment script
.\deploy-scale-unit.ps1 -EnvironmentType dev -EnvironmentName "my-dev-scale-unit"
```

### 2. Deploy Production Environment (Full Security)
```powershell
# Deploy with full VNet integration and private endpoints
.\deploy-scale-unit.ps1 -EnvironmentType prod -EnvironmentName "my-prod-scale-unit"
```

### 3. Manual Deployment (Advanced)
```bash
# Copy scale unit configuration
cp azure.scale-unit.yaml azure.yaml

# Set environment variables
export AZURE_ENV_NAME="my-scale-unit"
export AZURE_ENV_TYPE="dev"
export AZURE_PRIMARY_LOCATION="East US"
export AZURE_SECONDARY_LOCATION="West US 2"

# Deploy
azd up
```

## 🔧 Configuration Options

### Environment Types

| Environment | Networking | Security | Use Case |
|------------|------------|----------|----------|
| `dev` | Public access with MI auth | Basic | Development, testing |
| `test` | Public access with MI auth | Basic | Integration testing |
| `prod` | VNet integration + private endpoints | High | Production workloads |

### Regions

Default regions are optimized for US workloads:
- **Primary**: East US
- **Secondary**: West US 2

To use different regions:
```powershell
.\deploy-scale-unit.ps1 -PrimaryLocation "North Europe" -SecondaryLocation "West Europe"
```

## 📊 Monitoring & Health Checks

### Built-in Health Endpoints

- **`/health`** - Health check for Front Door probes
- **`/info`** - Application information and diagnostics

### Monitoring Components

1. **Azure Front Door** - Global load balancing and CDN
2. **Application Insights** - Application performance monitoring
3. **Log Analytics** - Centralized logging
4. **Metric Alerts** - Automated alerting for health issues
5. **Auto-scaling** - Automatic scaling based on demand

### Key Metrics to Monitor

- Front Door availability percentage
- App Service response times
- Storage account accessibility
- CPU and memory utilization
- Request success rates

## 🛡️ Security Features

### Production Security (`envType = 'prod'`)

- **Network Isolation**: VNet integration with private endpoints
- **Storage Security**: Private-only access to storage accounts
- **Identity Management**: Managed identities for all authentication
- **Transport Security**: HTTPS-only with TLS 1.2 minimum
- **Access Controls**: Network ACLs and IP restrictions

### Development Security (`envType = 'dev'`)

- **Managed Identity**: Passwordless authentication
- **HTTPS Enforcement**: Secure transport
- **Storage Access**: Public with managed identity auth
- **Basic Network Controls**: Azure service bypass

## 🔄 High Availability Features

### Automatic Failover

1. **Health Probes**: Front Door continuously monitors `/health` endpoint
2. **Priority Routing**: Primary region gets priority 1, secondary gets priority 2
3. **Automatic Failover**: Traffic automatically routes to healthy regions
4. **Geographic Distribution**: Users are served from the closest healthy region

### Scaling & Performance

- **Auto-scaling**: CPU-based scaling (70% scale up, 30% scale down)
- **Regional Capacity**: Primary region supports 2-10 instances, secondary 1-5
- **CDN**: Global content delivery network for improved performance
- **Connection Pooling**: Optimized database and storage connections

## 🧪 Testing Failover

### Simulate Region Failure

1. **Stop Primary Region App Service**:
   ```bash
   az webapp stop --name <primary-app-name> --resource-group <primary-rg>
   ```

2. **Monitor Front Door**: Traffic should automatically route to secondary region

3. **Restart Primary Region**:
   ```bash
   az webapp start --name <primary-app-name> --resource-group <primary-rg>
   ```

### Health Check Testing

```bash
# Test health endpoints
curl https://<front-door-endpoint>/health
curl https://<front-door-endpoint>/info

# Test primary region directly
curl https://<primary-app-service>/health

# Test secondary region directly
curl https://<secondary-app-service>/health
```

## 📋 Management Commands

### Deployment Management
```bash
# Deploy infrastructure and application
azd up

# Deploy only application code
azd deploy

# Preview changes
azd provision --preview

# View logs
azd logs

# Monitor application
azd monitor

# Clean up all resources
azd down
```

### Environment Management
```bash
# List environments
azd env list

# Switch environments
azd env select <environment-name>

# View environment values
azd env get-values

# Set environment values
azd env set KEY=value
```

## 🛠️ Troubleshooting

### Common Issues

1. **Front Door Health Probe Failures**
   - Check `/health` endpoint is accessible
   - Verify App Service is running
   - Check storage connectivity

2. **Regional Failover Not Working**
   - Verify health probe configuration
   - Check Front Door origin priorities
   - Monitor Front Door metrics

3. **Storage Access Issues**
   - Check managed identity permissions
   - Verify storage account network rules
   - Test storage connectivity from App Service

### Diagnostic Commands

```bash
# Check deployment status
azd show

# View detailed logs
azd logs --follow

# Check resource health
az resource list --resource-group <rg-name> --query "[].{Name:name,Type:type,Location:location}"

# Test storage connectivity
az storage blob list --account-name <storage-name> --container-name files --auth-mode login
```

## 🔮 Advanced Scenarios

### Adding More Regions

1. Modify `main-scale-unit.bicep` to include additional regions
2. Update Front Door origin groups
3. Add regional resource groups and deployments

### Custom Domain & SSL

1. Configure custom domain in Front Door
2. Add SSL certificate management
3. Update DNS records

### Database Integration

1. Add Azure SQL Database with geo-replication
2. Configure connection strings per region
3. Implement database failover logic

## 📚 Additional Resources

- [Azure Front Door Documentation](https://docs.microsoft.com/azure/frontdoor/)
- [Azure App Service Multi-Region](https://docs.microsoft.com/azure/app-service/app-service-web-tutorial-content-delivery-network)
- [Azure Developer CLI Documentation](https://learn.microsoft.com/azure/developer/azure-developer-cli/)
- [Azure Well-Architected Framework](https://docs.microsoft.com/azure/architecture/framework/)
