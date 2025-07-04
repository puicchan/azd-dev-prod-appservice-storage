# Azure App Service + Storage: Dev→Prod Pipeline

A simple web application demonstrating **environment-specific infrastructure** and **"build once, deploy everywhere"** CI/CD pipeline using Azure Developer CLI and GitHub Actions.

![Screenshot](./screenshot.png)

## 🚀 How It Works

1. **Package Once**: Application is built and packaged during GitHub Actions
2. **Deploy to Dev**: Deploy to development environment (public storage)
3. **Validate**: Run tests and validation checks
4. **Promote to Prod**: Deploy same package to production environment (private networking)

### Pipeline Flow

```
📦 Package and Deploy → 🔍 Validate Application → 🚀 Promote to Production
```

**Smart Environment Naming**: `myapp-dev` automatically becomes `myapp-prod`

## 🏗️ Infrastructure

Two environment configurations using Azure Bicep:

| Component | Development | Production |
|-----------|-------------|------------|
| **App Service** | B2 plan, public access | S1 plan, VNet integrated |
| **Storage** | Public access enabled | Private endpoints only |
| **Networking** | Standard | VNet + Private DNS |
| **Security** | Managed identity | Enhanced network isolation |

### Key Infrastructure Files
- `main.bicep` - Main orchestration
- `app.bicep` - App Service hosting  
- `shared.bicep` - Storage with environment-specific access
- `network.bicep` - VNet infrastructure (prod only)
- `monitoring.bicep` - Observability stack

## 🚀 Quick Start

### Prerequisites
- Azure subscription
- GitHub repository with these variables set:
  - `AZURE_CLIENT_ID`, `AZURE_TENANT_ID`, `AZURE_SUBSCRIPTION_ID`
  - `AZURE_ENV_NAME` (e.g., `myapp-dev`)
  - `AZURE_LOCATION`, `AZURE_ENV_TYPE`

### Deploy
```bash
# Manual deployment
azd up

# Or push to main branch for automated GitHub Actions deployment
```

### Environment Naming
- Dev: `myapp-dev` → Prod: `myapp-prod`  
- Dev: `staging` → Prod: `staging-prod`

## 🛡️ Security & Features

**Development**: Public storage, managed identity, HTTPS-only  
**Production**: Private networking, VNet integration, zero public storage access

## 📚 Learn More

- [Azure App Service VNet Integration](https://learn.microsoft.com/azure/app-service/tutorial-networking-isolate-vnet)
- [Azure Developer CLI](https://learn.microsoft.com/azure/developer/azure-developer-cli/)