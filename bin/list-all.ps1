$ProgressPreference = 'SilentlyContinue'
$BaseUrl = 'https://downloads.php.net/~windows/releases/'

function Get-PhpVersions($Url) {
    try {
        $Response = Invoke-WebRequest -Uri $Url -UseBasicParsing -ErrorAction Stop
        # Extract links matching the PHP Windows pattern for x64 Thread Safe
        $Matches = [regex]::Matches($Response.Content, 'php-([0-9]+\.[0-9]+\.[0-9]+)-Win32-.*-x64\.zip')
        $Versions = foreach ($Match in $Matches) {
            if ($Match.Value -notmatch '-nts-') {
                $Match.Groups[1].Value
            }
        }
        return $Versions
    } catch {
        return @()
    }
}

$AllVersions = (Get-PhpVersions $BaseUrl) + (Get-PhpVersions "${BaseUrl}archives/")
$AllVersions | Sort-Object { [version]$_ } -Unique | ForEach-Object { $_ }
