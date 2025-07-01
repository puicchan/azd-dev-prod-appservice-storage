# Multi-Region Scale Unit Deployment Script
# This script deploys a highly available multi-region application architecture

param(
    [Parameter(Mandatory=$false)]
    [ValidateSet("dev", "test", "prod")]
    [string]$EnvironmentType = "dev",
    
    [Parameter(Mandatory=$false)]
    [string]$EnvironmentName = "scale-unit-$(Get-Random -Minimum 1000 -Maximum 9999)",
    
    [Parameter(Mandatory=$false)]
    [string]$PrimaryLocation = "East US",
    
    [Parameter(Mandatory=$false)]
    [string]$SecondaryLocation = "West US 2",
    
    [Parameter(Mandatory=$false)]
    [switch]$WhatIf = $false
)

Write-Host "🌍 Multi-Region Scale Unit Deployment" -ForegroundColor Cyan
Write-Host "=====================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Configuration:" -ForegroundColor Yellow
Write-Host "  Environment Name: $EnvironmentName" -ForegroundColor White
Write-Host "  Environment Type: $EnvironmentType" -ForegroundColor White
Write-Host "  Primary Region:   $PrimaryLocation" -ForegroundColor White
Write-Host "  Secondary Region: $SecondaryLocation" -ForegroundColor White
Write-Host ""

# Set environment variables for azd
$env:AZURE_ENV_NAME = $EnvironmentName
$env:AZURE_ENV_TYPE = $EnvironmentType
$env:AZURE_PRIMARY_LOCATION = $PrimaryLocation
$env:AZURE_SECONDARY_LOCATION = $SecondaryLocation

try {
    # Check if azd is installed
    $azdVersion = azd version 2>$null
    if (-not $azdVersion) {
        Write-Error "Azure Developer CLI (azd) is not installed. Please install it first: https://learn.microsoft.com/azure/developer/azure-developer-cli/install-azd"
        exit 1
    }
    
    Write-Host "✅ Azure Developer CLI found: $($azdVersion -split "`n" | Select-Object -First 1)" -ForegroundColor Green
    
    # Initialize azd environment if it doesn't exist
    Write-Host "🔧 Initializing azd environment..." -ForegroundColor Yellow
    azd env new $EnvironmentName --location $PrimaryLocation --subscription (az account show --query id -o tsv) 2>$null
    
    # Set azd environment
    azd env select $EnvironmentName
    
    # Set environment-specific values
    azd env set AZURE_ENV_TYPE $EnvironmentType
    azd env set AZURE_PRIMARY_LOCATION $PrimaryLocation
    azd env set AZURE_SECONDARY_LOCATION $SecondaryLocation
    
    # Copy the scale unit configuration
    Copy-Item "azure.scale-unit.yaml" "azure.yaml" -Force
    Write-Host "✅ Scale unit configuration activated" -ForegroundColor Green
    
    if ($WhatIf) {
        Write-Host "🔍 Running deployment preview (what-if)..." -ForegroundColor Yellow
        azd provision --preview
    } else {
        Write-Host "🚀 Starting multi-region deployment..." -ForegroundColor Yellow
        azd up
        
        if ($LASTEXITCODE -eq 0) {
            Write-Host ""
            Write-Host "🎉 Multi-Region Scale Unit Deployed Successfully!" -ForegroundColor Green
            Write-Host "=================================================" -ForegroundColor Green
            Write-Host ""
            
            # Get deployment outputs
            $outputs = azd env get-values | ConvertFrom-Json -ErrorAction SilentlyContinue
            
            if ($outputs) {
                Write-Host "📊 Deployment Information:" -ForegroundColor Cyan
                Write-Host "  Front Door Endpoint: $($outputs.AZURE_FRONT_DOOR_ENDPOINT)" -ForegroundColor White
                Write-Host "  Primary App Service: $($outputs.AZURE_PRIMARY_APP_SERVICE)" -ForegroundColor White
                Write-Host "  Secondary App Service: $($outputs.AZURE_SECONDARY_APP_SERVICE)" -ForegroundColor White
                Write-Host ""
                Write-Host "🌐 Access your application at: https://$($outputs.AZURE_FRONT_DOOR_ENDPOINT)" -ForegroundColor Green
            }
            
            Write-Host ""
            Write-Host "📈 Next Steps:" -ForegroundColor Yellow
            Write-Host "  1. Test your application: Browse to the Front Door endpoint" -ForegroundColor White
            Write-Host "  2. Monitor health: Check Azure Portal for Front Door metrics" -ForegroundColor White
            Write-Host "  3. Test failover: Stop one region to verify automatic failover" -ForegroundColor White
            Write-Host "  4. Scale up: Modify autoscaling rules as needed" -ForegroundColor White
        } else {
            Write-Error "Deployment failed. Please check the logs above."
            exit 1
        }
    }
    
} catch {
    Write-Error "An error occurred during deployment: $($_.Exception.Message)"
    exit 1
} finally {
    # Restore original azure.yaml if it existed
    if (Test-Path "azure.yaml.backup") {
        Move-Item "azure.yaml.backup" "azure.yaml" -Force
    }
}

Write-Host ""
Write-Host "🔧 Useful Commands:" -ForegroundColor Cyan
Write-Host "  azd logs          # View application logs" -ForegroundColor White
Write-Host "  azd monitor       # Open monitoring dashboard" -ForegroundColor White
Write-Host "  azd down          # Delete all resources" -ForegroundColor White
Write-Host "  azd deploy        # Deploy app code changes" -ForegroundColor White
