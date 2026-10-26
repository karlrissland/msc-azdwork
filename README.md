# msc-azdwork

Hello World static site (nginx) on **Azure Container Apps**, with private-only
**Azure Container Registry**, a Linux build VM, a Windows 11 desktop, and **Azure Bastion**. Infrastructure
is managed by Terraform and deployment by Azure Developer CLI (azd).

## Layout
```
azure.yaml            Terraform project, image-only web service, private VM build hook
infra/                VNet, private DNS/endpoints, Premium ACR, workload-profiles
                      Container Apps environment, Linux build VM, Windows desktop, Bastion, NAT
src/web/              Dockerfile + html/index.html
scripts/              Password preflight and private VM build/push hook
```

The preprovision hook validates a password if supplied through the environment;
otherwise Terraform prompts for its required sensitive password variable. The predeploy hook packages the
local web source and uses Azure VM Run Command to build and push on the private VM.
No registry credentials are sent from the workstation or stored in Terraform.

## Prerequisites
- [azd](https://aka.ms/azd) >= 1.36.0 supporting `docker.imagePassthrough`,
  [Terraform](https://developer.hashicorp.com/terraform/install) >= 1.5,
  Azure CLI, PowerShell 7, and `tar` on the workstation.
- Both `azd auth login` and `az login`, using the same subscription.
- Resource providers registered: `Microsoft.App`, `Microsoft.ContainerRegistry`,
  `Microsoft.ManagedIdentity`, `Microsoft.Network`, and `Microsoft.Compute`.
- Permission to provision resources and assign roles, plus
  `Microsoft.Compute/virtualMachines/runCommand/action` for image builds.
- A jumpbox password with 12-72 characters and at least three of: lowercase,
  uppercase, digits, and special characters. No SSH key is required.
- Eligible Windows 11 licensing for every desktop user, such as Microsoft 365
  E3/E5 or Windows Enterprise E3/E5 with Azure multitenant hosting rights. Setting
  `license_type = "Windows_Client"` declares this entitlement; it does not buy a license.
- Regional availability and quota for the Linux VM (default `Standard_B2s`),
  Windows desktop (default `Standard_D2as_v4`, 2 vCPUs / 8 GiB RAM), Bastion Standard,
  private endpoints, and Container Apps workload profiles. The VM size can be
  changed through `jumpbox_vm_size` and `windows_desktop_vm_size` respectively.
- Docker is not required on the workstation. VM cloud-init installs Docker and
  Azure CLI; its first boot can take several minutes.
- The Windows VM uses Windows 11 Enterprise 25H2, Secure Boot, vTPM, and a 128 GiB
  Standard SSD. Edge is provided by the image; a VM extension installs Azure CLI
  after checking the installer's Microsoft signature. Docker is not installed on Windows.

## Workflow
```powershell
azd env new msc-azdwork-dev --location eastus2   # pick subscription when prompted
azd up
```

For an existing environment, skip `azd env new` and select it explicitly:

```powershell
azd up -e networktest --location eastus
```

For the requested clean redeployment, run the following yourself. `down` deletes
the environment's resources and their data; preserve anything you need first.

```powershell
azd down -e networktest
azd env set TF_VAR_jumpbox_vm_size Standard_D2as_v4 -e networktest
azd env set TF_VAR_windows_desktop_vm_size Standard_D2as_v4 -e networktest
azd up -e networktest --location eastus
```

Both size settings are explicitly mapped into the generated Terraform inputs.
The Linux build VM and its deployment hook remain unchanged. The desktop is a
second VM, with additional compute and disk charges. Availability is not reserved
by a successful SKU/quota check and can change before deployment.

When no password environment variable is set, Terraform requests
`var.jumpbox_admin_password` during planning, after provider initialization. Enter
the password directly at that terminal prompt. The hook must not reject a missing
password or try to set it in its parent process.

The optional launcher (`.\Invoke-Azd.ps1 -Command up -EnvironmentName networktest`)
instead prompts for the password with masked input before starting azd. It
passes the password to azd and Terraform through the process environment, then
clears a prompted password when azd exits, including on failure. An existing
password supplied by the caller is reused and left unchanged. If it is invalid,
clear it with `Remove-Item Env:TF_VAR_jumpbox_admin_password` and run the launcher
again. `deploy` and `version` do not prompt for a password.

To supply the password in advance instead of using Terraform's prompt, set it in
the same PowerShell session first:

```powershell
$env:TF_VAR_jumpbox_admin_password = [System.Net.NetworkCredential]::new(
  '', (Read-Host 'Jumpbox password' -AsSecureString)
).Password
try {
  azd up             # provision, then build/push on the private VM and deploy
}
finally {
  Remove-Item Env:TF_VAR_jumpbox_admin_password -ErrorAction SilentlyContinue
}
```

For an existing azd environment, skip `azd env new`. The default VM username is
`azureuser`; optionally set `$env:TF_VAR_jumpbox_admin_username` before provisioning
to use another administrator name. Set the password in the same PowerShell session
that launches azd, not in the preprovision hook or with `azd env set`. It is passed
directly to Terraform and is not written to the azd environment or variable JSON
files. Old `AZURE_JUMPBOX_SSH_PUBLIC_KEY` settings are no longer used.

Terraform marks the password sensitive to redact normal output, but **the password
is still stored in Terraform state and saved plan files**. Protect these files,
exclude them from source control, and use encrypted, access-controlled storage for
shared state. Do not paste passwords into chat or literal shell commands. Removing
the process environment variable does not remove the password from Terraform state.

You can run `azd provision` and `azd deploy` separately instead of `azd up`.
Provisioning and preview prompt for the password unless its environment variable
is set; deployments using only `azd deploy` do not require it. Re-enter the same
password before later provision runs unless you intend to change VM credentials.
For unattended runs, provide `TF_VAR_jumpbox_admin_password` through your secret
store and disable Terraform input with `TF_INPUT=false`.

The native prompt is regression-tested with the installed azd and Terraform,
the actual preprovision hook and variable declarations, and synthetic input:

```powershell
.\tests\Test-PasswordPrompt.ps1 -SubscriptionId <subscription-id> -Location eastus
```

This test uses a temporary output-only Terraform project and the actual web service
configuration, replacing the cloud deploy step with image packaging. It verifies
fresh initialization before registry outputs exist, the sensitive password prompt,
both saved VM-size overrides, and private image selection after provisioning in
the same workflow. It creates
no Azure resources, checks the password does not appear in captured output, and
removes its local test files. An existing Azure/azd login is required.

Do not run deployment until you review the subscription, region, costs, and any
resource replacements in the Terraform plan. Integrating an existing environment
into a VNet requires replacement and can recreate its app. Back up local Terraform
state and schedule downtime before migrating an existing deployment. Never delete
state to bypass replacement errors. Consider a fresh azd environment for testing.

The VM build transport deliberately accepts at most 16 KiB of compressed source
for this small sample. It does not use public ACR Tasks or temporarily open ACR.
For larger projects, clone the source on the VM or transfer it through Bastion and
run Docker there. Builds run as root via VM Run Command: only trusted operators
and trusted source should have access. Do not run concurrent builds/deployments
against this sample's shared `web:latest` tag. Do not include secrets in the source
context; the source is transported through Azure's management plane.

## Private Networking

- The default VNet is `10.40.0.0/16`, with non-overlapping subnets derived for
  Container Apps, endpoints, the jumpbox, and `AzureBastionSubnet`. Change
  `vnet_address_space` before provisioning if this overlaps your existing networks.
- ACR uses **Premium**, public network access is disabled, trusted-service bypass
  is disabled, and admin credentials remain disabled. Its private DNS zone covers
  both login and regional data endpoints through the private endpoint zone group.
- Container Apps uses a **workload-profiles environment with a Consumption profile**,
  not the legacy Consumption-only environment. This supports VNet integration,
  NAT, and private endpoints without paying for a dedicated D4 compute instance.
  Private endpoint/environment management charges still apply.
- The environment has public network access disabled. App `external_enabled = true`
  permits ingress from outside the environment through its private endpoint; it
  does not override the environment's public access restriction.
- The app identity has `AcrPull`; each VM's system identity has `AcrPush`, all scoped
  to this registry. Neither VM is granted permission to update the app; azd uses
  the signed-in deployment operator's management-plane permissions for that step.
- The VM has no public IP and accepts SSH only from the Bastion subnet. Bastion
  Standard provides browser SSH and native-client tunneling.
- The Windows desktop shares the jumpbox subnet, private DNS, and NAT Gateway.
  It has no public IP. An additional rule permits TCP 3389 only from Bastion to
  the desktop's private IP; the explicit deny rule still blocks other inbound traffic.
- NAT supplies outbound-only internet connectivity to the VM and app subnet for
  package downloads and public base images. The Bastion and NAT public IPs do not
  expose the VM, registry, or app to public inbound traffic.
- Premium ACR, Bastion Standard, NAT, private endpoints, and the VM/disk add ongoing
  charges, including while the app is idle.

## Linux Build VM Access

In the Azure portal, open the build VM, select **Connect > Bastion**, and use
`azureuser` and the password entered at provisioning. Select password authentication.
Wait for `cloud-init status --wait` to finish
before using build tools. Alternatively, use native SSH from PowerShell:

```powershell
$config = azd env get-values --output json | ConvertFrom-Json
az network bastion ssh --subscription $config.AZURE_SUBSCRIPTION_ID `
  --resource-group $config.AZURE_RESOURCE_GROUP --name $config.AZURE_BASTION_NAME `
  --target-resource-id $config.AZURE_JUMPBOX_ID --auth-type password `
  --username $config.AZURE_JUMPBOX_ADMIN_USERNAME
```

Enter the password in the terminal when prompted; do not pass it as a CLI argument.
If the VM already exists, review the Terraform plan before applying this change:
the authentication and cloud-init changes may require VM replacement.

On the VM, authenticate to ACR with managed identity and build/push manually if needed:

```bash
az login --identity
az acr login --name <registry-name>
docker build --platform linux/amd64 -t <registry-name>.azurecr.io/web:latest ./src/web
docker push <registry-name>.azurecr.io/web:latest
```

## Windows Desktop Access

In the Azure portal, open the VM named by `AZURE_WINDOWS_DESKTOP_NAME`, select
**Connect > Bastion**, choose **RDP** and password authentication, then enter the
same `azureuser` administrator name and password used for the Linux VM. The
Windows setup extension must finish successfully before Azure CLI is ready.

Alternatively, launch the native Windows Remote Desktop client through Bastion
from your workstation (requires the Azure CLI Bastion extension):

```powershell
$config = azd env get-values -e networktest --output json | ConvertFrom-Json
az network bastion rdp --subscription $config.AZURE_SUBSCRIPTION_ID `
  --resource-group $config.AZURE_RESOURCE_GROUP --name $config.AZURE_BASTION_NAME `
  --target-resource-id $config.AZURE_WINDOWS_DESKTOP_ID
```

Enter `azureuser` and the password in the RDP credential dialog, not on the command
line. Inside the desktop, open Edge and visit the `SERVICE_WEB_URI` shown by azd.
That browser runs inside the VNet and can reach the private Container App.

Open a new PowerShell window on the Windows desktop to inspect the private registry:

```powershell
az version
Resolve-DnsName <registry-name>.azurecr.io
az login --identity --allow-no-subscriptions
az acr repository list --name <registry-name> --output table
az acr repository show-tags --name <registry-name> --repository web --output table
az acr login --name <registry-name> --expose-token --output none
```

The final command verifies registry authentication without requiring Docker or
printing the token. Use `az login` instead if you intend to use your own identity;
the VM identity has only registry-scoped access, not deployment permissions. The
Azure portal in Edge uses your interactive identity, not the VM's managed identity.
Registry permissions can take time to propagate after provisioning.

Use the Linux VM for Docker builds/pushes, either through its Bastion SSH session
or the existing workstation `azd deploy` command. The Windows VM is for interactive
browsing and registry tools; it is not a Linux container build host.

## Deployment Checks

1. On the VM, run `cloud-init status --wait`, `docker version`, and `az version`.
2. Run `getent ahostsv4 <registry-name>.azurecr.io` and resolve the app FQDN.
   Both should resolve to private endpoint addresses inside the VNet.
3. Run `azd deploy` from the workstation. The VM hook must report a successful push,
   followed by a healthy Container App revision using the app's pull identity.
4. From the VM, run `curl --fail https://<app-fqdn>` to verify the web page.
   A workstation without private routing should not be able to load the app.
5. Outside the VNet, attempt an authenticated registry pull/push. It must fail;
   a public DNS response or an unauthenticated HTTP challenge alone does not prove
   public data-plane access is enabled.
6. Connect to Windows through Bastion RDP, open `SERVICE_WEB_URI` in Edge, and
  inspect registry repositories using the commands above. DNS for the registry
  and app should resolve privately on Windows as well as Linux.

For provisioning/build failures, inspect `/var/log/cloud-init-output.log` on the
VM. Azure role assignments can take time to propagate; once permissions become
effective, rerun `azd deploy` without opening public access. The hook checks a
success marker as well as the CLI exit code to detect remote build failures.
For Windows tool installation failures, inspect `C:\ProgramData\AzdDesktopSetup\AzureCLI-install.log`
and the Custom Script extension logs under
`C:\WindowsAzure\Logs\Plugins\Microsoft.Compute.CustomScriptExtension`.

### Calling azd from PowerShell

The root-level [Invoke-Azd.ps1](./Invoke-Azd.ps1) demonstrates invoking `azd`
with an argument array and checking its exit code. It always uses the project
root as the working directory. For `up` and `provision`, it requests a missing
password with a masked prompt and validates it before starting azd.

```powershell
.\Invoke-Azd.ps1                              # safe default: azd version
.\Invoke-Azd.ps1 -Command provision -EnvironmentName azdwork-stage
.\Invoke-Azd.ps1 -Command deploy -EnvironmentName azdwork-stage
.\Invoke-Azd.ps1 -Command up -EnvironmentName azdwork-stage
```

Authenticate with `azd auth login` before provisioning or deploying. If
`-EnvironmentName` is omitted, azd uses the currently selected environment.
Provisioning and deployment commands can change Azure resources and incur costs.
The script lets azd load environment configuration; it does not parse `.env` files.

## Design notes
- The Container App is first created with a public MCR placeholder image (port 80),
  pulled outbound through NAT. `azd deploy` then uses the image pushed by the VM;
  Terraform ignores image/revision changes so provisioning does not revert it.
- The service image has a fully qualified bootstrap default because azd validates
  services before provisioning produces registry outputs. Terraform supplies
  `SERVICE_WEB_IMAGE` for subsequent packaging/deployment. The VM build hook rejects
  missing or mismatched private image outputs, so deployment cannot silently use
  the bootstrap image. Existing environments must run provision to refresh outputs.
- The app pulls from ACR using a user-assigned managed identity with `AcrPull` (ACR admin user disabled).
- azd links to resources via the `azd-service-name = web` tag and the Terraform outputs
  (`AZURE_CONTAINER_REGISTRY_ENDPOINT`, etc.).
- Terraform state is local (stored under `.azure/<env>/infra/`); preserve it and
  exclude it from source control. No Log Analytics/App Insights is configured.
- The container listens on port 80 (`nginx:stable-alpine`) to match the placeholder image during first provision.
