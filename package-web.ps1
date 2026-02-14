$src = "Builds"
$out = "Builds/zip"

New-Item -ItemType Directory -Force -Path $out | Out-Null
Copy-Item "$src/GaasRoads.html" "$src/index.html"

$files = Get-ChildItem "$src" -File | Where-Object { $_.Directory.Name -ne "zip" }
Compress-Archive -Path $files.FullName -DestinationPath "$out/gaasroads-web.zip" -Force

Write-Host "Created $out/gaasroads-web.zip"
