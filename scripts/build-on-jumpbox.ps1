[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

foreach ($variableName in @('AZURE_SUBSCRIPTION_ID', 'AZURE_RESOURCE_GROUP', 'AZURE_JUMPBOX_NAME', 'AZURE_CONTAINER_REGISTRY_NAME', 'AZURE_CONTAINER_REGISTRY_ENDPOINT')) {
    $variableValue = [Environment]::GetEnvironmentVariable($variableName)
    if (-not $variableValue -or $variableValue -notmatch '^[A-Za-z0-9._()\-]+$') {
        throw "Missing or invalid $variableName. Run azd provision first and invoke this script through azd deploy."
    }
}

if ($env:SERVICE_WEB_IMAGE -cne "$env:AZURE_CONTAINER_REGISTRY_ENDPOINT/web:latest") {
    throw 'SERVICE_WEB_IMAGE must reference this environment registry and web:latest. Run azd provision to refresh its outputs before deploying. The bootstrap image will not be deployed.'
}

foreach ($toolName in @('az', 'tar')) {
    if (-not (Get-Command $toolName -ErrorAction SilentlyContinue)) {
        throw "$toolName is required for the private build workflow."
    }
}

$archivePath = Join-Path ([IO.Path]::GetTempPath()) ("azd-build-{0}.tgz" -f [guid]::NewGuid().ToString('N'))
$remoteScriptPath = "$archivePath.sh"
try {
    & tar -czf $archivePath -C (Join-Path $PSScriptRoot '../src/web') .
    if ($LASTEXITCODE -ne 0) {
        throw 'Could not package the web build context.'
    }

    $archiveBytes = [IO.File]::ReadAllBytes($archivePath)
    if ($archiveBytes.Length -gt 16384) {
        throw 'Build context exceeds the 16 KiB Run Command transport limit for this sample. Transfer larger sources through a Bastion tunnel or clone them on the VM and build there.'
    }

    $payload = [Convert]::ToBase64String($archiveBytes)
    $successMarker = "AZD_PRIVATE_BUILD_OK_$([guid]::NewGuid().ToString('N'))"
    $remoteScript = @'
#!/usr/bin/env bash
set -euo pipefail
timeout 900 cloud-init status --wait
command -v az
docker info >/dev/null
build_dir=$(mktemp -d)
export AZURE_CONFIG_DIR=$(mktemp -d)
export DOCKER_CONFIG=$(mktemp -d)
trap 'rm -rf "$build_dir" "$AZURE_CONFIG_DIR" "$DOCKER_CONFIG"' EXIT
printf '%s' '__PAYLOAD__' | base64 --decode | tar -xz -C "$build_dir"
az login --identity --allow-no-subscriptions --output none
az acr login --name '__REGISTRY_NAME__'
docker build --platform linux/amd64 --tag '__REGISTRY_ENDPOINT__/web:latest' "$build_dir"
docker push '__REGISTRY_ENDPOINT__/web:latest'
printf '\n%s\n' '__SUCCESS_MARKER__'
'@
    $remoteScript = $remoteScript.Replace('__PAYLOAD__', $payload).
        Replace('__REGISTRY_NAME__', $env:AZURE_CONTAINER_REGISTRY_NAME).
        Replace('__REGISTRY_ENDPOINT__', $env:AZURE_CONTAINER_REGISTRY_ENDPOINT).
        Replace('__SUCCESS_MARKER__', $successMarker).Replace("`r`n", "`n")
    $remoteScript = "bash <<'AZD_PRIVATE_BUILD'`n$remoteScript`nAZD_PRIVATE_BUILD`n"
    [IO.File]::WriteAllText($remoteScriptPath, $remoteScript, [Text.UTF8Encoding]::new($false))

    Write-Host "Building and pushing on private VM $env:AZURE_JUMPBOX_NAME..."
    $resultJson = & az vm run-command invoke --subscription $env:AZURE_SUBSCRIPTION_ID `
        --resource-group $env:AZURE_RESOURCE_GROUP --name $env:AZURE_JUMPBOX_NAME `
        --command-id RunShellScript --scripts "@$remoteScriptPath" --output json --only-show-errors
    if ($LASTEXITCODE -ne 0) {
        throw 'Azure VM Run Command failed. Confirm Azure CLI login and VM run-command permissions.'
    }

    $result = ($resultJson -join "`n") | ConvertFrom-Json
    $messages = @($result.value | ForEach-Object { $_.message }) -join "`n"
    Write-Host $messages
    if (-not $messages.Contains($successMarker)) {
        throw 'Private build did not complete. Check cloud-init logs, private DNS, Docker, and AcrPush propagation, then rerun azd deploy. Public registry access remains disabled.'
    }
}
finally {
    Remove-Item -LiteralPath $archivePath -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $remoteScriptPath -Force -ErrorAction SilentlyContinue
}