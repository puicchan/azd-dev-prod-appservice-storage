#!/usr/bin/env python3
"""
Simple validation script for the Azure App Service + Storage application.
This demonstrates basic health checks that could be expanded for real validation.
"""

import os
import sys
import requests
import time
from urllib.parse import urljoin

def validate_app_health():
    """Validate application health and basic functionality."""
    
    # Get the app URL from environment variables (set by azd)
    app_url = os.environ.get('AZURE_APP_SERVICE_URL')
    if not app_url:
        print("❌ AZURE_APP_SERVICE_URL environment variable not set")
        return False
    
    print(f"🔍 Validating application at: {app_url}")
    
    try:
        # Test 1: Basic health check
        print("  ➤ Testing basic connectivity...")
        response = requests.get(app_url, timeout=30)
        if response.status_code != 200:
            print(f"  ❌ Health check failed: HTTP {response.status_code}")
            return False
        print("  ✅ Health check passed")
        
        # Test 2: Check if the upload form is available
        print("  ➤ Testing upload form availability...")
        if "upload" not in response.text.lower():
            print("  ❌ Upload form not found in response")
            return False
        print("  ✅ Upload form available")
        
        # Test 3: Check Azure Storage connectivity (indirect)
        print("  ➤ Testing files listing endpoint...")
        files_url = urljoin(app_url, '/files')
        files_response = requests.get(files_url, timeout=30)
        if files_response.status_code not in [200, 404]:  # 404 is OK if no files exist
            print(f"  ❌ Files endpoint failed: HTTP {files_response.status_code}")
            return False
        print("  ✅ Files endpoint accessible")
        
        print("🎉 All validation checks passed!")
        return True
        
    except requests.exceptions.RequestException as e:
        print(f"❌ Network error during validation: {e}")
        return False
    except Exception as e:
        print(f"❌ Unexpected error during validation: {e}")
        return False

def main():
    """Main validation function."""
    print("🚀 Starting application validation...")
    
    # Give the app a moment to fully start
    time.sleep(5)
    
    if validate_app_health():
        print("✅ Application validation completed successfully")
        sys.exit(0)
    else:
        print("❌ Application validation failed")
        sys.exit(1)

if __name__ == '__main__':
    main()
