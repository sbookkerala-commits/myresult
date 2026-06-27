# Build Flutter web app and copy to server/public for Render deployment.
$ErrorActionPreference = "Stop"
$root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
Set-Location $root

Write-Host "Building Flutter web (release)..."
flutter build web --release --no-wasm-dry-run

$src = Join-Path $root "build\web"
$dest = Join-Path $root "server\public"

if (Test-Path $dest) {
    Remove-Item -Recurse -Force $dest
}
Copy-Item -Recurse $src $dest

Write-Host ""
Write-Host "Web app ready: $dest"
Write-Host "Deploy: push server/ (with public/) to Render, or run 'npm start' in server/"
Write-Host "Local test: cd server && npm start  ->  http://localhost:3000"
