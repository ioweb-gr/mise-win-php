$ProgressPreference = 'SilentlyContinue'

# Mise passes these via environment variables
$Version = $env:ASDF_INSTALL_VERSION
$Dest = $env:ASDF_INSTALL_PATH
$BaseUrl = 'https://downloads.php.net/~windows/releases/'

function Find-ZipFilename($Url) {
    try {
        $Response = Invoke-WebRequest -Uri $Url -UseBasicParsing -ErrorAction Stop
        # Find a match for the requested version, ensuring it's x64 and NOT nts
        $Match = [regex]::Match($Response.Content, "php-$Version-Win32-.*-x64\.zip")
        if ($Match.Success -and $Match.Value -notmatch '-nts-') {
            return $Match.Value
        }
    } catch { }
    return $null
}

Write-Host "Searching for PHP $Version (Thread Safe, x64)..."
$Filename = Find-ZipFilename $BaseUrl
$DownloadUrl = "$BaseUrl$Filename"

if (-not $Filename) {
    Write-Host "Checking archives..."
    $Filename = Find-ZipFilename "${BaseUrl}archives/"
    $DownloadUrl = "${BaseUrl}archives/$Filename"
}

if (-not $Filename) {
    Write-Error "Could not find PHP version $Version (Thread Safe, x64) on windows.php.net"
    exit 1
}

Write-Host "Found release: $Filename"
Write-Host "Downloading from $DownloadUrl..."

# Ensure destination path exists
if (-not (Test-Path $Dest)) {
    New-Item -ItemType Directory -Force -Path $Dest | Out-Null
}

$ZipPath = Join-Path $Dest "php-$Version.zip"
Invoke-WebRequest -Uri $DownloadUrl -OutFile $ZipPath -ErrorAction Stop

Write-Host "Extracting to $Dest..."
Expand-Archive -Path $ZipPath -DestinationPath $Dest -Force -ErrorAction Stop
Remove-Item $ZipPath -Force

# Set up default php.ini
$IniDev = Join-Path $Dest "php.ini-development"
$Ini = Join-Path $Dest "php.ini"
if ((Test-Path $IniDev) -and -not (Test-Path $Ini)) {
    Copy-Item $IniDev $Ini
    Write-Host "Created default php.ini from php.ini-development"
}

Write-Host "PHP $Version installed successfully!"
