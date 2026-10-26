$ErrorActionPreference = 'Stop'

$password = $env:TF_VAR_jumpbox_admin_password
if ([string]::IsNullOrEmpty($password)) {
	Write-Host 'Terraform will request the jumpbox administrator password during planning (var.jumpbox_admin_password).'
}
else {
	$categoryCount = @(@('[a-z]', '[A-Z]', '[0-9]', '[^a-zA-Z0-9]') | Where-Object { $password -cmatch $_ }).Count
	if ($password.Length -lt 12 -or $password.Length -gt 72 -or $categoryCount -lt 3) {
		throw 'The jumpbox password must have 12-72 characters and at least three of: lowercase, uppercase, digits, and special characters. Clear TF_VAR_jumpbox_admin_password to let Terraform prompt, or supply a valid value before running azd.'
	}
}

if (-not (Get-Command az -ErrorAction SilentlyContinue)) {
	throw 'Azure CLI is required for private VM builds. Install it and run az login in addition to azd auth login.'
}
