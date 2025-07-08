# Azure App Service + Storage: Dev→Prod Pipeline

A simple web application demonstrating **environment-specific infrastructure** and **"build once, deploy everywhere"** CI/CD pipeline using Azure Developer CLI and GitHub Actions.

![Screenshot](./screenshot.png)

## 🚀 How It Works

The pipeline implements true **"build once, deploy everywhere"**:

1. **Package Application**: Build and package the app to `./dist/app-package.zip`
2. **Deploy to Dev**: Deploy the package to development environment (public storage)
3. **Validate**: Run tests and validation checks on dev deployment
4. **Promote to Prod**: Deploy the **same package** to production environment (private networking)

### Pipeline Flow

```
📦 Package → 🚀 Deploy Dev → 🔍 Validate → 🚀 Promote to Prod (same package)
```

**Key Benefits**:
- ✅ Same exact package deployed to both environments
- ✅ No rebuilding during promotion
- ✅ Faster production deployments
- ✅ Reduces build-related deployment issues

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


### 1. Initialize Project from Template

```bash
azd init -t https://github.com/puicchan/azd-dev-prod-appservice-storage
```

This downloads the complete implementation with all Bicep templates and enhanced GitHub Actions workflow.

### 2. Set Up Development Environment

```bash
azd up
```

When prompted for the environment name, use `myproj-dev` (or your preferred naming pattern with `-dev` suffix).

**Note**: The default `envType` is `dev`, so you don't need to set the `AZURE_ENV_TYPE` environment variable for development. The infrastructure will automatically provision with public access and cost-optimized resources.

### 3. Set Up Production Environment

Create and configure the production environment:

```bash
# Create new production environment
azd env new myproj-prod

# Set environment type to production
azd env set AZURE_ENV_TYPE prod

# Deploy production environment
azd up
```

This provisions production infrastructure with VNet integration, private endpoints, and enhanced security.

### 4. Switch Back to Development Environment

```bash
azd env select myproj-dev
```

You're now ready to develop and test in the development environment.

### 5. Make Code Changes

Edit your application code (e.g., modify `app/templates/index.html` or `app.py`) to test the promotion workflow.

### 6. Configure CI/CD Pipeline

```bash
azd pipeline config
```

This enhances the generated GitHub Actions workflow with dev-to-prod promotion logic. The pipeline will:
- Deploy and validate in development (`myproj-dev`)
- Automatically promote to production (`myproj-prod`) using the same package
- Handle environment naming conversion automatically

Once configured, every push to the main branch will trigger the automated dev-to-prod promotion pipeline!

## 🛡️ Security & Features

**Development**: Public storage, managed identity, HTTPS-only  
**Production**: Private networking, VNet integration, zero public storage access

## 📚 Learn More

- [Azure App Service VNet Integration](https://learn.microsoft.com/azure/app-service/tutorial-networking-isolate-vnet)
- [Azure Developer CLI](https://learn.microsoft.com/azure/developer/azure-developer-cli/)