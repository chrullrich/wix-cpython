#!PowerShell.

# -Deploy does not start deploying, it only puts the package
# where it belongs and tells Deploy and Inventory about the
# new version.

Param(
    [Parameter(Mandatory)]
    [string]$Version,
    [switch]$Force=$false,
    [switch]$ForceDownload=$false,
    [switch]$Deploy=$false
)

$ErrorActionPreference = "Stop"

function GetScriptDirectory() {
    Write-Output (Split-Path $Script:MyInvocation.MyCommand.Path -Parent)
}

# Creates a GUID from the SHA256 hash of the argument by
# XORing the first and second 16 bytes. The result is rarely
# a standard-compliant GUID, but nobody ever cares.
function GuidFromStringData($s) {
    if (-not $s) {
        Write-Error "GuidFromStringData(): No input"
    }

    $a = [Security.Cryptography.SHA256]::Create()
    $b = [Text.Encoding]::UTF8.GetBytes($s)
    $h = $a.ComputeHash($b)
    $h = for ($i = 0; $i -lt 16; ++$i) { $h[$i] -bxor $h[$i+16] }

    [guid][byte[]]$h
}

function DoPlatform($platform) {

    $urlarch = switch ($platform) {
        "x64" { "-amd64" }
        "x86" { "-win32" }
    }

    [uri]$url = "https://www.python.org/ftp/python/$Version/python-$Version$urlarch.zip"
    $archive = $url.Segments[-1]

    Write-Debug "URL: $url"
    Write-Debug "Archive: $archive"

    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

    $msi = "python-$Version-$platform.msi"
    Write-Debug "MSI: $msi"

    # Do nothing if the latest MSI is already built, unless forced.
    if (-not $Force -and (Test-Path $msi)) {

        Write-Host "No update since latest build."

        # Return empty result
        $null, $null

    } else {

        # Download only if the ZIP is not there, or if forced.
        if ($ForceDownload -or (-not (Test-Path $archive))) {

            Remove-Item $archive -ErrorAction SilentlyContinue
            Invoke-WebRequest -Uri $url -OutFile $archive

        } else {
            Write-Debug "Skipping download, $archive exists"
        }

        if (Test-Path SourceDir) {
            Remove-Item -Recurse -Force SourceDir
        }
        Expand-Archive -Path $archive -DestinationPath SourceDir

        $pyshortver = $rver[0..1] -join "."
        $bin = get-item SourceDir\python.exe
        $binver = $bin.VersionInfo.FileVersionRaw

        if ($rver[0] -ne $binver.Major `
                -or $rver[1] -ne $binver.Minor `
                -or (([int]$rver[2]) * 1000 + 150) -ne $binver.Build) {
            Write-Error "Version mismatch, archive contains version $binver"
        }

        # Trust, but verify.
        if (Test-Path -PathType Leaf SourceDir\python.exe) {
            Write-Host "Packaging $platform ..."

            try {
                $vp = "Python$pydirver$platform"
                $upgcode = GuidFromStringData $vp

                $out = & wix.exe build -arch $platform -o $msi -d Platform=$platform -d "VerMajor=$($binver.Major)" -d "VerMinor=$($binver.Minor)" -d "VerBuildPublic=$($rver[2])" -d "VerBuildInternal=$($binver.Build)" -d "UpgradeCode=$upgcode" -b Python=SourceDir -cc cabcache-$platform -loc Product.en-us.wxl Product.wxs | Out-String

                if ($LASTEXITCODE -ne 0) {
                    Write-Error $out
                    exit $LASTEXITCODE
                }
            } catch [System.Management.Automation.CommandNotFoundException] {
                Write-Error "wix is not on the path"
            }
        } else {
            Write-Error "$archive contains an unexpected directory structure."
        }
    }

    $msi, $binver
}

$rver = $Version -split "\."
$pydirver = $rver[0..1] -join ""

# If the MSI already exists and without -Force, the build is skipped.
# This means we do not update the SourceDir and therefore do not know
# the internal version. In this case we cannot update the variables
# either.

# DoPlatform() is the best place to get the internal version
# (with the "150"); we just overwrite it in the second call.
$x86, $binver = DoPlatform "x86"
$x64, $binver = DoPlatform "x64"

$msiver = $binver.Major, $binver.Minor, $binver.Build, 0 -join "."

if ($Deploy) {
    if ($x64) {
#        Copy-Item $x64 wherever
    }
    if ($x86) {
#        Copy-Item $x86 wherever
    }
}

Write-Host "... done."

