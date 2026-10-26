$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$setupDirectory = Join-Path $env:ProgramData 'AzdDesktopSetup'
New-Item -ItemType Directory -Path $setupDirectory -Force | Out-Null
$installerPath = Join-Path $setupDirectory 'AzureCLI.msi'
$logPath = Join-Path $setupDirectory 'AzureCLI-install.log'

try {
    Invoke-WebRequest -Uri 'https://aka.ms/installazurecliwindowsx64' -OutFile $installerPath -UseBasicParsing
    $signature = Get-AuthenticodeSignature -FilePath $installerPath
    if ($signature.Status -ne 'Valid' -or $signature.SignerCertificate.Subject -notmatch 'O=Microsoft Corporation(,|$)') {
        throw 'Azure CLI installer did not have a valid Microsoft signature.'
    }

    $installation = Start-Process -FilePath msiexec.exe -ArgumentList @(
        '/i', "`"$installerPath`"", '/qn', '/norestart', '/L*v', "`"$logPath`""
    ) -Wait -PassThru
    if ($installation.ExitCode -notin @(0, 3010)) {
        throw "Azure CLI installation failed with exit code $($installation.ExitCode). See $logPath."
    }

    $env:Path = [Environment]::GetEnvironmentVariable('Path', 'Machine') + ';' + [Environment]::GetEnvironmentVariable('Path', 'User')
    $azureCli = Get-Command az.cmd -CommandType Application -ErrorAction Stop | Select-Object -First 1
    & $azureCli.Source version --output none
    if ($LASTEXITCODE -ne 0) {
        throw 'Azure CLI installation verification failed.'
    }

    Write-Output 'Windows desktop tools are ready. Use Edge for the private website and PowerShell with az login --identity for registry access.'
}
finally {
    Remove-Item -LiteralPath $installerPath -Force -ErrorAction SilentlyContinue
}