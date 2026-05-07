# IIS Deployment Guide for EMS Web Application

## Prerequisites

- Windows Server 2016+ or Windows 10/11
- IIS 10+ with ASP.NET Core Hosting Bundle
- Node.js 16+ (for building React app)
- PowerShell 5.1+

---

## Step 1: Install IIS Features

```powershell
# Run as Administrator
Enable-WindowsOptionalFeature -Online -FeatureName IIS-WebServerRole
Enable-WindowsOptionalFeature -Online -FeatureName IIS-WebServer
Enable-WindowsOptionalFeature -Online -FeatureName IIS-CommonHttpFeatures
Enable-WindowsOptionalFeature -Online -FeatureName IIS-HttpErrors
Enable-WindowsOptionalFeature -Online -FeatureName IIS-HttpRedirect
Enable-WindowsOptionalFeature -Online -FeatureName IIS-ApplicationDevelopment
Enable-WindowsOptionalFeature -Online -FeatureName IIS-NetFxExtensibility45
Enable-WindowsOptionalFeature -Online -FeatureName IIS-HealthAndDiagnostics
Enable-WindowsOptionalFeature -Online -FeatureName IIS-HttpLogging
Enable-WindowsOptionalFeature -Online -FeatureName IIS-Security
Enable-WindowsOptionalFeature -Online -FeatureName IIS-RequestFiltering
Enable-WindowsOptionalFeature -Online -FeatureName IIS-Performance
Enable-WindowsOptionalFeature -Online -FeatureName IIS-WebServerManagementTools
Enable-WindowsOptionalFeature -Online -FeatureName IIS-StaticContent
Enable-WindowsOptionalFeature -Online -FeatureName IIS-DefaultDocument
Enable-WindowsOptionalFeature -Online -FeatureName IIS-DirectoryBrowsing
Enable-WindowsOptionalFeature -Online -FeatureName IIS-HttpCompressionStatic
```

Verify installation:
```powershell
Get-WindowsOptionalFeature -Online | Where-Object {$_.FeatureName -like "IIS-*" -and $_.State -eq "Enabled"}
```

---

## Step 2: Install URL Rewrite Module

Download and install from:
https://www.iis.net/downloads/microsoft/url-rewrite

Or use Chocolatey:
```powershell
choco install urlrewrite -y
```

---

## Step 3: Build React Application

```powershell
cd C:\Users\ZORO\PowerShellEndPointv2\WebUI

# Install dependencies (first time only)
npm install

# Build production bundle
npm run build
```

Output will be in `C:\Users\ZORO\PowerShellEndPointv2\WebUI\build`

---

## Step 4: Create IIS Website Directories

```powershell
# Create deployment directory
New-Item -Path "C:\inetpub\ems" -ItemType Directory -Force
New-Item -Path "C:\inetpub\ems\webui" -ItemType Directory -Force

# Copy React build files
Copy-Item -Path "C:\Users\ZORO\PowerShellEndPointv2\WebUI\build\*" `
          -Destination "C:\inetpub\ems\webui\" `
          -Recurse -Force
```

---

## Step 5: Create web.config for React App

Create `C:\inetpub\ems\webui\web.config`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<configuration>
    <system.webServer>
        <rewrite>
            <rules>
                <!-- Redirect all requests to index.html for React Router -->
                <rule name="React Routes" stopProcessing="true">
                    <match url=".*" />
                    <conditions logicalGrouping="MatchAll">
                        <add input="{REQUEST_FILENAME}" matchType="IsFile" negate="true" />
                        <add input="{REQUEST_FILENAME}" matchType="IsDirectory" negate="true" />
                        <add input="{REQUEST_URI}" pattern="^/(api)" negate="true" />
                    </conditions>
                    <action type="Rewrite" url="/" />
                </rule>
            </rules>
        </rewrite>
        <staticContent>
            <mimeMap fileExtension=".json" mimeType="application/json" />
            <mimeMap fileExtension=".woff" mimeType="application/font-woff" />
            <mimeMap fileExtension=".woff2" mimeType="application/font-woff2" />
        </staticContent>
        <httpCompression>
            <staticTypes>
                <add mimeType="text/*" enabled="true" />
                <add mimeType="application/javascript" enabled="true" />
                <add mimeType="application/json" enabled="true" />
            </staticTypes>
        </httpCompression>
    </system.webServer>
</configuration>
```

Run this PowerShell command:
```powershell
@'
<?xml version="1.0" encoding="UTF-8"?>  
<configuration>
    <system.webServer>
        <rewrite>
            <rules>
                <rule name="React Routes" stopProcessing="true">
                    <match url=".*" />
                    <conditions logicalGrouping="MatchAll">
                        <add input="{REQUEST_FILENAME}" matchType="IsFile" negate="true" />
                        <add input="{REQUEST_FILENAME}" matchType="IsDirectory" negate="true" />
                        <add input="{REQUEST_URI}" pattern="^/(api)" negate="true" />
                    </conditions>
                    <action type="Rewrite" url="/" />
                </rule>
            </rules>
        </rewrite>
    </system.webServer>
</configuration>
'@ | Out-File -FilePath "C:\inetpub\ems\webui\web.config" -Encoding UTF8
```

---

## Step 6: Create IIS Website

```powershell
Import-Module WebAdministration

# Create application pool
New-WebAppPool -Name "EMS_Pool"
Set-ItemProperty -Path "IIS:\AppPools\EMS_Pool" -Name "managedRuntimeVersion" -Value ""

# Create website
New-Website -Name "EMS" `
            -PhysicalPath "C:\inetpub\ems\webui" `
            -ApplicationPool "EMS_Pool" `
            -Port 80

# Set permissions
$acl = Get-Acl "C:\inetpub\ems"
$permission = "IIS_IUSRS", "ReadAndExecute", "ContainerInherit,ObjectInherit", "None", "Allow"
$accessRule = New-Object System.Security.AccessControl.FileSystemAccessRule $permission
$acl.SetAccessRule($accessRule)
Set-Acl "C:\inetpub\ems" $acl
```

---

## Step 7: Configure Reverse Proxy for API

Edit `C:\inetpub\ems\webui\web.config` and add API proxy rule:

```xml
<rule name="ReverseProxyAPI" stopProcessing="true">
    <match url="^api/(.*)" />
    <action type="Rewrite" url="http://localhost:5000/api/{R:1}" />
</rule>
```

Complete web.config with API proxy:
```powershell
@'
<?xml version="1.0" encoding="UTF-8"?>
<configuration>
    <system.webServer>
        <rewrite>
            <rules>
                <!-- Reverse proxy for API -->
                <rule name="ReverseProxyAPI" stopProcessing="true">
                    <match url="^api/(.*)" />
                    <action type="Rewrite" url="http://localhost:5000/api/{R:1}" />
                </rule>
                <!-- React Router fallback -->
                <rule name="React Routes" stopProcessing="true">
                    <match url=".*" />
                    <conditions logicalGrouping="MatchAll">
                        <add input="{REQUEST_FILENAME}" matchType="IsFile" negate="true" />
                        <add input="{REQUEST_FILENAME}" matchType="IsDirectory" negate="true" />
                    </conditions>
                    <action type="Rewrite" url="/" />
                </rule>
            </rules>
        </rewrite>
    </system.webServer>
</configuration>
'@ | Out-File -FilePath "C:\inetpub\ems\webui\web.config" -Encoding UTF8 -Force
```

---

## Step 8: Configure API Backend as Windows Service

Install the PowerShell script as a Windows service using NSSM:

```powershell
# Download NSSM (Non-Sucking Service Manager)
choco install nssm -y

# Install API as service
nssm install EMS_API "powershell.exe" `
    "-ExecutionPolicy Bypass -File C:\Users\ZORO\PowerShellEndPointv2\API\Start-EMSAPI.ps1"

# Set service properties
nssm set EMS_API AppDirectory "C:\Users\ZORO\PowerShellEndPointv2\API"
nssm set EMS_API AppStdout "C:\Users\ZORO\PowerShellEndPointv2\Logs\api_stdout.log"
nssm set EMS_API AppStderr "C:\Users\ZORO\PowerShellEndPointv2\Logs\api_stderr.log"

# Start service
Start-Service EMS_API
```

---

## Step 9: Configure Firewall

```powershell
# Allow HTTP (port 80)
New-NetFirewallRule -DisplayName "EMS Web - HTTP" `
    -Direction Inbound `
    -Protocol TCP `
    -LocalPort 80 `
    -Action Allow

# Internal API port (localhost only)
New-NetFirewallRule -DisplayName "EMS API - Internal" `
    -Direction Inbound `
    -Protocol TCP `
    -LocalPort 5000 `
    -RemoteAddress 127.0.0.1 `
    -Action Allow
```

---

## Step 10: Configure HTTPS (Production)

### Option A: Self-Signed Certificate (Development)

```powershell
# Create self-signed certificate
$cert = New-SelfSignedCertificate -DnsName "ems.corp.local" `
    -CertStoreLocation "Cert:\LocalMachine\My" `
    -FriendlyName "EMS Website"

# Bind to IIS
New-WebBinding -Name "EMS" -Protocol "https" -Port 443 -IPAddress "*"
$binding = Get-WebBinding -Name "EMS" -Protocol "https"
$binding.AddSslCertificate($cert.Thumbprint, "my")
```

### Option B: Enterprise CA Certificate (Production)

Request certificate from your organization's CA, then:
```powershell
New-WebBinding -Name "EMS" -Protocol "https" -Port 443 -IPAddress "*"
$cert = Get-ChildItem -Path Cert:\LocalMachine\My | Where-Object { $_.Subject -like "*ems.corp.local*" }
$binding = Get-WebBinding -Name "EMS" -Protocol "https"
$binding.AddSslCertificate($cert.Thumbprint, "my")
```

---

## Step 11: Test Deployment

```powershell
# Test website
Start-Process "http://localhost"

# Test API endpoint
Invoke-RestMethod -Uri "http://localhost/api/auth/validate" -Method GET
```

---

## Troubleshooting

### Issue: 500 Internal Server Error

Check IIS logs:
```powershell
Get-Content "C:\inetpub\logs\LogFiles\W3SVC1\*.log" -Tail 50
```

Check application event log:
```powershell
Get-EventLog -LogName Application -Source "IIS*" -Newest 20
```

### Issue: API Not Responding

Check API service:
```powershell
Get-Service EMS_API
Get-Content "C:\Users\ZORO\PowerShellEndPointv2\Logs\api_stderr.log"
```

### Issue: URL Rewrite Not Working

Verify URL Rewrite module:
```powershell
Get-WindowsFeature -Name *rewrite*
```

Test rewrite rules:
```powershell
Test-WebConfigFile -PSPath "IIS:\Sites\EMS"
```

---

## Maintenance

### Update Web UI

```powershell
cd C:\Users\ZORO\PowerShellEndPointv2\WebUI
npm run build
Copy-Item -Path ".\build\*" -Destination "C:\inetpub\ems\webui\" -Recurse -Force

# Restart IIS
iisreset
```

### Update API Backend

```powershell
# Stop service
Stop-Service EMS_API

# Update files
Copy-Item -Path "C:\Users\ZORO\PowerShellEndPointv2\API\*" -Destination "C:\inetpub\ems\api\" -Force

# Start service
Start-Service EMS_API
```

---

## Production Checklist

- [ ] PostgreSQL database configured and running
- [ ] HTTPS certificate installed
- [ ] Firewall rules configured
- [ ] API backend running as Windows service
- [ ] IIS website started and accessible
- [ ] URL Rewrite rules working
- [ ] API reverse proxy functioning
- [ ] Authentication working (test login)
- [ ] Dashboard loading statistics
- [ ] Scan functionality working
- [ ] Results history displaying data
- [ ] Logs directory writable
- [ ] Backup strategy in place

---

**Access URL**: `http://localhost` or `https://ems.corp.local`

**Default Credentials**: Use Active Directory credentials for users in `EMS_Admins` group
