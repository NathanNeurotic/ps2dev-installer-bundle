[CmdletBinding()]
param(
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$InstallerArgs
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function Write-Status {
    param(
        [string]$Tag,
        [string]$Message,
        [string]$Color = 'Gray'
    )

    Write-Host "[$Tag] $Message" -ForegroundColor $Color
}

function Show-Banner {
    Write-Host '------------------------------------------------------------' -ForegroundColor DarkGray
    Write-Host 'PS2DEV Installer Bundle' -ForegroundColor Cyan
    Write-Host 'Windows launcher into Ubuntu on WSL' -ForegroundColor DarkGray
    Write-Host '------------------------------------------------------------' -ForegroundColor DarkGray
}

function Fail {
    param([string]$Message)

    Write-Status -Tag 'FAIL' -Message $Message -Color Red
    exit 1
}

function Quote-Bash {
    param([string]$Value)

    $singleQuote = [string][char]39
    $doubleQuote = [string][char]34
    $replacement = $singleQuote + $doubleQuote + $singleQuote + $doubleQuote + $singleQuote
    return $singleQuote + $Value.Replace($singleQuote, $replacement) + $singleQuote
}

function Get-DefaultWslDistro {
    $lines = & wsl.exe -l -v 2>$null
    if ($LASTEXITCODE -ne 0) {
        return $null
    }

    foreach ($line in $lines) {
        if ($line -match '^\s*\*\s+(.+?)\s{2,}') {
            return $matches[1].Trim()
        }
    }

    return $null
}

function Test-UbuntuDistro {
    param([string]$Distro)

    if (-not $Distro) {
        return $false
    }

    & wsl.exe -d $Distro bash -lc "grep -qiE '(^ID=ubuntu$|^ID_LIKE=.*ubuntu)' /etc/os-release" 2>$null | Out-Null
    return ($LASTEXITCODE -eq 0)
}

function Get-UbuntuDistro {
    param([string]$PreferredDistro)

    $distroOutput = & wsl.exe -l -q 2>$null
    if ($LASTEXITCODE -ne 0) {
        Fail "WSL is unavailable or no distributions are installed. Install Ubuntu in WSL and try again."
    }

    $distros = @(
        $distroOutput |
            ForEach-Object { $_.Trim() } |
            Where-Object { $_ }
    )

    if ($distros.Count -eq 0) {
        Fail "No WSL distributions were found. Install Ubuntu in WSL and try again."
    }

    if ($PreferredDistro) {
        $preferredMatch = $distros | Where-Object { $_ -eq $PreferredDistro } | Select-Object -First 1
        if ($preferredMatch) {
            if (Test-UbuntuDistro -Distro $preferredMatch) {
                return $preferredMatch
            }

            Fail "The bundle path points at WSL distro '$preferredMatch', but that distro does not report itself as Ubuntu."
        }
    }

    $defaultDistro = Get-DefaultWslDistro
    if (Test-UbuntuDistro -Distro $defaultDistro) {
        return $defaultDistro
    }

    $ubuntuDistro = $distros | Where-Object { Test-UbuntuDistro -Distro $_ } | Select-Object -First 1
    if ($ubuntuDistro) {
        return $ubuntuDistro
    }

    Fail "No Ubuntu WSL distribution was found. Install Ubuntu for WSL and try again."
}

function Get-WslShareInfo {
    param([string]$WindowsPath)

    if ($WindowsPath -match '^[\\]{2}(?:wsl\$|wsl\.localhost)\\([^\\]+)(?:\\(.*))?$') {
        $wslPath = '/'
        if ($matches[2]) {
            $wslPath += ($matches[2] -replace '\\', '/')
        }

        return [PSCustomObject]@{
            Distro = $matches[1]
            WslPath = $wslPath
        }
    }

    return $null
}

Show-Banner

if (-not (Get-Command wsl.exe -ErrorAction SilentlyContinue)) {
    Fail "wsl.exe was not found. Install WSL with Ubuntu first, or use https://www.github.com/NathanNeurotic/wsl-dev-pack"
}

$bundleDirWindows = $PSScriptRoot
if (-not $bundleDirWindows) {
    Fail "Unable to determine the bundle directory."
}

$wslShareInfo = Get-WslShareInfo $bundleDirWindows
$preferredDistro = if ($wslShareInfo) { $wslShareInfo.Distro } else { $null }

Write-Status -Tag 'INFO' -Message "Bundle path: $bundleDirWindows" -Color DarkGray
Write-Status -Tag 'STEP' -Message 'Selecting an Ubuntu WSL distro' -Color Cyan
$distro = Get-UbuntuDistro -PreferredDistro $preferredDistro
Write-Status -Tag 'INFO' -Message "Using WSL distro: $distro" -Color Green

if ($wslShareInfo -and $wslShareInfo.Distro -eq $distro) {
    $bundleDirWsl = $wslShareInfo.WslPath
} else {
    Write-Status -Tag 'STEP' -Message 'Translating the bundle path into WSL' -Color Cyan
    $bundleDirWsl = (& wsl.exe -d $distro wslpath -a -u $bundleDirWindows 2>$null | Select-Object -First 1)
    if ($LASTEXITCODE -ne 0 -or -not $bundleDirWsl) {
        Fail "Unable to translate the bundle path into WSL: $bundleDirWindows"
    }
}

$bundleDirWsl = $bundleDirWsl.Trim()
$bundleDirQuoted = Quote-Bash $bundleDirWsl
Write-Status -Tag 'INFO' -Message "WSL path: $bundleDirWsl" -Color DarkGray

$probeCommand = "cd $bundleDirQuoted && test -f ./ps2dev_aio_installer.sh"
& wsl.exe -d $distro bash -lc $probeCommand | Out-Null
if ($LASTEXITCODE -ne 0) {
    Fail "WSL could not access the bundle directory or ./ps2dev_aio_installer.sh is missing: $bundleDirWindows"
}

$quotedArgs = @()
foreach ($arg in $InstallerArgs) {
    $quotedArgs += Quote-Bash $arg
}

$argSuffix = ''
if ($quotedArgs.Count -gt 0) {
    $argSuffix = ' ' + ($quotedArgs -join ' ')
}

$installerCommand = "cd $bundleDirQuoted && bash ./ps2dev_aio_installer.sh$argSuffix"
Write-Status -Tag 'STEP' -Message 'Launching the installer inside WSL' -Color Cyan
& wsl.exe -d $distro bash -lc $installerCommand
if ($LASTEXITCODE -eq 0) {
    Write-Status -Tag ' OK ' -Message 'Installer session finished successfully' -Color Green
} else {
    Write-Status -Tag 'FAIL' -Message "Installer exited with code $LASTEXITCODE" -Color Red
}
exit $LASTEXITCODE
