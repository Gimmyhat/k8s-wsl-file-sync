# PowerShell script for running WSL-based data synchronization
param (
    [Parameter(Mandatory=$false)]
    [switch]$Verify,
    
    [Parameter(Mandatory=$false)]
    [string]$LogFile = "$(Get-Date -Format 'yyyy-MM-dd-HHmmss')-sync.log",
    
    [Parameter(Mandatory=$false)]
    [switch]$UseUNCPath,
    
    [Parameter(Mandatory=$false)]
    [string]$SourcePath
)

# Check if WSL is installed
$wslCheck = wsl --status 2>&1
if ($LASTEXITCODE -ne 0) {
    Write-Host "Error: WSL is not installed or configured. Please install WSL 2 and Ubuntu distribution."
    Write-Host "Instructions: https://docs.microsoft.com/en-us/windows/wsl/install"
    exit 1
}

# Check if Ubuntu is installed
$ubuntuCheck = wsl -l -q | Where-Object { $_ -match "Ubuntu" }
if (-not $ubuntuCheck) {
    Write-Host "Error: Ubuntu distribution is not found in WSL. Please install it."
    Write-Host "Command: wsl --install -d Ubuntu"
    exit 1
}

# Prepare script name
$script = if ($Verify) { "./verify-wsl.sh" } else { "./sync-wsl.sh" }

# Prepare arguments
$arguments = @()

if ($UseUNCPath) {
    $arguments += "USE_UNC_PATH=1"
}

if ($SourcePath) {
    $arguments += "SOURCE_PATH='$SourcePath'"
}

$argsString = $arguments -join " "

# Output information
Write-Host "Starting WSL sync script (Ubuntu)..."
Write-Host "Script: $script"
if ($arguments.Count -gt 0) {
    Write-Host "Arguments: $argsString"
}
Write-Host "Log file: $LogFile"

# Create log directory if it doesn't exist
$logDir = Split-Path -Parent $LogFile
if (-not [string]::IsNullOrEmpty($logDir) -and -not (Test-Path $logDir)) {
    New-Item -ItemType Directory -Path $logDir -Force
}

# Run script in WSL and save output to log file
try {
    if ($arguments.Count -gt 0) {
        wsl -d Ubuntu -e /bin/bash -c "cd '$(Get-Location)' && $argsString $script" | Tee-Object -FilePath $LogFile
    } else {
        wsl -d Ubuntu -e /bin/bash -c "cd '$(Get-Location)' && $script" | Tee-Object -FilePath $LogFile
    }
    
    if ($LASTEXITCODE -eq 0) {
        Write-Host "Script completed successfully."
    } else {
        Write-Host "Script completed with errors (code $LASTEXITCODE)."
    }
} catch {
    Write-Host "Error running script: $_"
    $_ | Out-File -Append -FilePath $LogFile
    exit 1
}

Write-Host "Log saved to file: $LogFile" 