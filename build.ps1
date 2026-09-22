# Builds Ritder for the TrimUI Brick Pro and packages it for the stock OS.
#
#   .\build.ps1                    -> dist\Ritder (copy to SD:\Apps\Ritder), dist\Ritder-stock.zip
#                                     and the OTA files dist\update\{update.json, ritder-update.tar.gz}
#   .\build.ps1 -UpdateUrl <url>   -> bakes another OTA manifest URL into the app
#   .\build.ps1 -Notes "..."       -> release notes shown on the device before updating
#   .\build.ps1 -Publish           -> also creates the GitHub release (tools\publish_release.py)
#
# Needs only Python 3.10+: KOReader itself is not compiled here, tools\build.py downloads the
# pinned upstream linux-arm64 build (upstream.json) and applies the Ritder overlay on top.
param(
    [switch]$Publish,
    [string]$UpdateUrl = "",
    [string]$Notes = ""
)

# Native tools print progress on stderr; failures are detected with $LASTEXITCODE.
$ErrorActionPreference = "Continue"
$root = $PSScriptRoot

$version = (Get-Content (Join-Path $root "VERSION") -Raw).Trim()

$buildArgs = @((Join-Path $root "tools\build.py"))
if ($UpdateUrl) { $buildArgs += @("--update-url", $UpdateUrl) }
python @buildArgs
if ($LASTEXITCODE -ne 0) { throw "build failed" }

$distRoot = Join-Path $root "dist"
$notesArg = $Notes
if (-not $notesArg -and (Test-Path (Join-Path $root "release-notes.txt"))) {
    $notesArg = Join-Path $root "release-notes.txt"
}
python (Join-Path $root "tools\make_update.py") (Join-Path $distRoot "Ritder") (Join-Path $distRoot "update") $version $notesArg
if ($LASTEXITCODE -ne 0) { throw "OTA package failed" }
Write-Host "Upload dist\update\update.json, dist\update\ritder-update.tar.gz and dist\Ritder-stock.zip to the release."

if ($Publish) {
    python (Join-Path $root "tools\publish_release.py")
    if ($LASTEXITCODE -ne 0) { throw "publishing the release failed" }
}
