[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$SubscriptionId,

    [string]$Location = 'eastus'
)

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path $PSScriptRoot -Parent
$testRoot = Join-Path ([IO.Path]::GetTempPath()) ("azd-password-test-{0}" -f [guid]::NewGuid().ToString('N'))
$syntheticPassword = "Synthetic-$([guid]::NewGuid().ToString('N'))!"
$process = $null
$processStarted = $false

try {
    New-Item -ItemType Directory -Path (Join-Path $testRoot 'infra'), (Join-Path $testRoot 'scripts') | Out-Null
    Copy-Item (Join-Path $projectRoot 'infra/variables.tf') (Join-Path $testRoot 'infra/variables.tf')
    Copy-Item (Join-Path $projectRoot 'infra/main.tfvars.json') (Join-Path $testRoot 'infra/main.tfvars.json')
    Copy-Item (Join-Path $projectRoot 'scripts/preprovision.ps1') (Join-Path $testRoot 'scripts/preprovision.ps1')

        $projectYaml = Get-Content (Join-Path $projectRoot 'azure.yaml') -Raw
        $deployStep = '      - azd: deploy --all'
        if (-not $projectYaml.Contains($deployStep)) {
                throw 'The regression fixture must explicitly replace the cloud deployment step with packaging.'
        }
            $projectYaml.Replace($deployStep, '      - azd: package web --no-prompt --output json') | Set-Content (Join-Path $testRoot 'azure.yaml') -Encoding utf8

    @'
output "PASSWORD_INPUT_ACCEPTED" {
  value = nonsensitive(length(var.jumpbox_admin_password) > 0)
}

output "SERVICE_WEB_IMAGE" {
    value = "regression.azurecr.io/web:latest"
}

output "SELECTED_VM_SIZE" {
    value = var.jumpbox_vm_size
}

output "SELECTED_WINDOWS_VM_SIZE" {
    value = var.windows_desktop_vm_size
}
'@ | Set-Content (Join-Path $testRoot 'infra/main.tf') -Encoding utf8

    & azd env new password-prompt-test --subscription $SubscriptionId --location $Location --cwd $testRoot --no-prompt
    if ($LASTEXITCODE -ne 0) {
        throw 'Could not initialize the isolated azd test environment.'
    }

    & azd env set TF_VAR_jumpbox_vm_size Standard_D2as_v4 --environment password-prompt-test --cwd $testRoot
    if ($LASTEXITCODE -ne 0) {
        throw 'Could not save the isolated VM-size override.'
    }

    & azd env set TF_VAR_windows_desktop_vm_size Standard_D2s_v4 --environment password-prompt-test --cwd $testRoot
    if ($LASTEXITCODE -ne 0) {
        throw 'Could not save the isolated Windows VM-size override.'
    }

    $process = [Diagnostics.Process]::new()
    $process.StartInfo.FileName = (Get-Command azd -CommandType Application).Source
    $process.StartInfo.WorkingDirectory = $testRoot
    $process.StartInfo.UseShellExecute = $false
    $process.StartInfo.RedirectStandardInput = $true
    $process.StartInfo.RedirectStandardOutput = $true
    $process.StartInfo.RedirectStandardError = $true
    foreach ($argument in @('up', '-e', 'password-prompt-test', '--location', $Location)) {
        $process.StartInfo.ArgumentList.Add($argument)
    }
    foreach ($variable in @('TF_VAR_jumpbox_admin_password', 'TF_VAR_jumpbox_vm_size', 'TF_VAR_windows_desktop_vm_size', 'TF_INPUT', 'TF_CLI_ARGS', 'TF_CLI_ARGS_plan', 'SERVICE_WEB_IMAGE', 'AZURE_CONTAINER_REGISTRY_ENDPOINT')) {
        $process.StartInfo.Environment.Remove($variable) | Out-Null
    }

    $process.Start() | Out-Null
    $processStarted = $true
    $stdoutTask = $process.StandardOutput.ReadToEndAsync()
    $stderrTask = $process.StandardError.ReadToEndAsync()
    $process.StandardInput.WriteLine($syntheticPassword)
    $process.StandardInput.Close()
    if (-not $process.WaitForExit(180000)) {
        $process.Kill($true)
        throw 'The isolated azd password-prompt test timed out.'
    }

    $output = $stdoutTask.GetAwaiter().GetResult() + $stderrTask.GetAwaiter().GetResult()
    if ($output.Contains($syntheticPassword)) {
        throw 'The synthetic sensitive password appeared in azd output.'
    }
    if ($process.ExitCode -ne 0) {
        throw "Isolated azd up failed with exit code $($process.ExitCode):`n$output"
    }
    if ($output -notmatch 'var\.jumpbox_admin_password') {
        throw "The expected Terraform password prompt was not observed:`n$output"
    }

    $statePath = Join-Path $testRoot '.azure/password-prompt-test/infra/terraform.tfstate'
    $state = Get-Content $statePath -Raw | ConvertFrom-Json
    if ($state.outputs.PASSWORD_INPUT_ACCEPTED.value -ne $true) {
        throw 'The native password prompt did not supply a valid Terraform input.'
    }
    if (@($state.resources).Count -ne 0) {
        throw 'The regression fixture unexpectedly contains managed resources.'
    }
    if ($state.outputs.SELECTED_VM_SIZE.value -ne 'Standard_D2as_v4') {
        throw "The saved azd VM-size override did not reach Terraform; selected $($state.outputs.SELECTED_VM_SIZE.value)."
    }
    if ($state.outputs.SELECTED_WINDOWS_VM_SIZE.value -ne 'Standard_D2s_v4') {
        throw "The saved azd Windows VM-size override did not reach Terraform; selected $($state.outputs.SELECTED_WINDOWS_VM_SIZE.value)."
    }

    if ($output -notmatch 'regression\.azurecr\.io/web:latest') {
        throw "Packaging in the same up workflow did not select the private image from the Terraform output: $output"
    }

    Write-Host 'PASS: real web service initialized before registry/image outputs existed.'
    Write-Host 'PASS: real azd up reached the Terraform sensitive-password prompt.'
    Write-Host 'PASS: synthetic stdin password passed the real variable validation and apply.'
    Write-Host 'PASS: saved azd VM-size override reached Terraform without a process environment variable.'
    Write-Host 'PASS: saved azd Windows VM-size override reached Terraform without a process environment variable.'
    Write-Host 'PASS: post-provision packaging selected the private registry image without Docker.'
    Write-Host 'PASS: password was absent from output; no Azure resources were provisioned.'
}
finally {
    if ($process) {
        if ($processStarted -and -not $process.HasExited) {
            $process.Kill($true)
        }
        $process.Dispose()
    }
    Remove-Item $testRoot -Recurse -Force -ErrorAction SilentlyContinue
}