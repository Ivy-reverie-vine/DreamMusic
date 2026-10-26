# Setup-HarmonyOS7-SdkCompat.ps1
# Auto-detect DevEco Studio HarmonyOS 7.0 (API 26) SDK and create compatibility mapping

$ErrorActionPreference = "Stop"

$possibleSdkRoots = @(
    "D:\DevEco\DevEco Studio\sdk",
    "D:\DevEco\sdk",
    "C:\Users\$env:USERNAME\AppData\Local\Huawei\Sdk"
)

Write-Host ">>> Searching for HarmonyOS 7.0 (API 26) SDK..." -ForegroundColor Cyan

$foundPkg = $null
$foundSdkDir = $null

foreach ($root in $possibleSdkRoots) {
    if (Test-Path $root) {
        $pkgs = Get-ChildItem -Path $root -Filter "sdk-pkg.json" -Recurse -Depth 4 -ErrorAction SilentlyContinue
        foreach ($pkg in $pkgs) {
            $content = Get-Content -Raw $pkg.FullName | ConvertFrom-Json -ErrorAction SilentlyContinue
            if ($content -and ($content.data.apiVersion -eq "26" -or $content.data.platformVersion -like "7.*")) {
                $foundPkg = $pkg
                $foundSdkDir = $pkg.Directory.FullName
                Write-Host "Found HarmonyOS 7 SDK: $foundSdkDir (API $($content.data.apiVersion), $($content.data.displayName))" -ForegroundColor Green
                break
            }
        }
    }
    if ($foundPkg) { break }
}

if (-not $foundPkg) {
    Write-Warning "HarmonyOS 7.0 (API 26) SDK not found!"
    Write-Host "Please open DevEco Studio -> Settings -> SDK Manager -> HarmonyOS, check and download HarmonyOS 7.0 (API 26) SDK." -ForegroundColor Yellow
    Write-Host "After the download finishes, re-run this script." -ForegroundColor Yellow
    exit 1
}

$compatRoot = "D:\DreamMusic\.devEco-sdk-compat"
if (-not (Test-Path $compatRoot)) {
    New-Item -ItemType Directory -Path $compatRoot -Force | Out-Null
}

$pkgJson = Get-Content -Raw $foundPkg.FullName | ConvertFrom-Json
$folderName = if ($pkgJson.data.path) { $pkgJson.data.path } else { "HarmonyOS-7.0.0" }
$targetDir = Join-Path $compatRoot $folderName

if (-not (Test-Path $targetDir)) {
    New-Item -ItemType Directory -Path $targetDir -Force | Out-Null
}

Copy-Item -Path $foundPkg.FullName -Destination (Join-Path $targetDir "sdk-pkg.json") -Force
Write-Host "Copied sdk-pkg.json -> $targetDir\sdk-pkg.json" -ForegroundColor Green

foreach ($sub in @("hms", "openharmony")) {
    $srcSub = Join-Path $foundSdkDir $sub
    $dstSub = Join-Path $targetDir $sub
    if (Test-Path $srcSub) {
        if (Test-Path $dstSub) {
            cmd /c rmdir "$dstSub" 2>$null
        }
        cmd /c mklink /J "$dstSub" "$srcSub" | Out-Null
        Write-Host "Created Junction: $dstSub -> $srcSub" -ForegroundColor Green
    }
}

Write-Host ">>> HarmonyOS 7.0 SDK compat mapping complete!" -ForegroundColor Cyan
Write-Host "Build verification command:" -ForegroundColor White
Write-Host "  `$env:DEVECO_SDK_HOME='D:\DreamMusic\.devEco-sdk-compat'" -ForegroundColor Yellow
Write-Host "  & 'D:\DevEco\tools\hvigor\bin\hvigorw.bat' assembleHap --no-daemon --no-type-check --stacktrace" -ForegroundColor Yellow

