<#
.SYNOPSIS
Updates an existing Container App to an image already pushed to its registry.
.DESCRIPTION
Requires Azure CLI with Container Apps support and an authenticated operator with
permission to update the app. Does not build or push images, run Terraform or azd,
change registry credentials, or open private networking. The app's existing
identity must have pull access to the registry and network access to its endpoints.

A unique revision suffix forces a new revision even when reusing an image tag.
Prefer immutable version tags or image digests for reproducible deployments.
For this repo's Single revision mode, Azure moves traffic when the new revision
is ready. In Multiple revision mode, existing traffic rules still apply.
The returned provisioning status is not an application health check.
Subsequent azd deployments can overwrite this image with web:latest.
.EXAMPLE
.\scripts\update-container-app-image.ps1 -SubscriptionId '<subscription-id>' `
    -ResourceGroupName 'rg-networktest' -ContainerAppName 'ca-web-<token>' `
    -Image '<registry>.azurecr.io/web:v2' -WhatIf
.EXAMPLE
.\scripts\update-container-app-image.ps1 -SubscriptionId '<subscription-id>' `
    -ResourceGroupName 'rg-networktest' -ContainerAppName 'ca-web-<token>' `
    -Image '<registry>.azurecr.io/web:v2'
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$SubscriptionId,

    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$ResourceGroupName,

    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$ContainerAppName,

    [Parameter(Mandatory)]
    [ValidatePattern('^[A-Za-z0-9][^\s]*$')]
    [string]$Image,

    [ValidateNotNullOrEmpty()]
    [string]$ContainerName = 'web'
)

$ErrorActionPreference = 'Stop'
$revisionSuffix = "image-$([guid]::NewGuid().ToString('N'))"
$target = "$SubscriptionId/$ResourceGroupName/$ContainerAppName (container $ContainerName)"
if (-not $PSCmdlet.ShouldProcess($target, "Deploy image '$Image' as revision '$revisionSuffix'")) {
    return
}

$cliName = if ($env:OS -eq 'Windows_NT') { 'az.cmd' } else { 'az' }
$azureCli = Get-Command $cliName -CommandType Application -ErrorAction Stop | Select-Object -First 1
$cliArguments = @(
    'containerapp', 'update',
    '--subscription', $SubscriptionId,
    '--resource-group', $ResourceGroupName,
    '--name', $ContainerAppName,
    '--container-name', $ContainerName,
    '--image', $Image,
    '--revision-suffix', $revisionSuffix,
    '--query', '{name:name,resourceGroup:resourceGroup,provisioningState:properties.provisioningState,latestRevision:properties.latestRevisionName,latestReadyRevision:properties.latestReadyRevisionName,containers:properties.template.containers[].{name:name,image:image}}',
    '--output', 'json',
    '--only-show-errors'
)

$resultJson = & $azureCli.Source @cliArguments
if ($LASTEXITCODE -ne 0) {
    throw "Container App image update failed with exit code $LASTEXITCODE. Check the CLI error, operator permissions, and the app's registry identity and network access."
}

($resultJson -join "`n") | ConvertFrom-Json