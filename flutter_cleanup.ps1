# flutter_cleanup.ps1

Write-Host "Cleaning Flutter build folders..."

# Step 1: Run flutter clean if inside a Flutter project
if (Test-Path "pubspec.yaml") {
    flutter clean
}
else {
    Write-Host "Not in a Flutter project folder — skipping flutter clean."
}

# Step 2: Clean Pub cache
$pubCache = "$env:LOCALAPPDATA\Pub\Cache"
if (Test-Path $pubCache) {
    Write-Host "Deleting Pub cache: $pubCache"
    Remove-Item "$pubCache\*" -Recurse -Force -ErrorAction SilentlyContinue
}

# Step 3: Clean Gradle caches
$gradleCache = "$env:USERPROFILE\.gradle\caches"
if (Test-Path $gradleCache) {
    Write-Host "Deleting Gradle cache: $gradleCache"
    Remove-Item "$gradleCache\*" -Recurse -Force -ErrorAction SilentlyContinue
}

# Step 4: Clean .android folder (optional logs/keys)
$androidFolder = "$env:USERPROFILE\.android"
if (Test-Path $androidFolder) {
    Write-Host "Deleting .android folder: $androidFolder"
    Remove-Item "$androidFolder\*" -Recurse -Force -ErrorAction SilentlyContinue
}

# Step 5: Clean Windows TEMP files
$temp = "$env:TEMP"
Write-Host "Deleting Windows TEMP files: $temp"
Remove-Item "$temp\*" -Recurse -Force -ErrorAction SilentlyContinue


Write-Host "Cleanup completed successfully."
