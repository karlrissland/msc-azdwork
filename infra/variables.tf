variable "environment_name" {
  description = "azd environment name; used for naming and tagging."
  type        = string
}

variable "location" {
  description = "Azure region for all resources."
  type        = string
}

variable "image_placeholder" {
  description = "Public image used until `azd deploy` pushes the real image."
  type        = string
  default     = "mcr.microsoft.com/azuredocs/containerapps-helloworld:latest"
}

variable "target_port" {
  description = "Port the container listens on."
  type        = number
  default     = 80
}

variable "vnet_address_space" {
  description = "VNet IPv4 CIDR, /20 or larger; must not overlap connected networks. Subnets are derived automatically."
  type        = string
  default     = "10.40.0.0/16"

  validation {
    condition     = can(cidrnetmask(var.vnet_address_space)) && can(cidrsubnet(var.vnet_address_space, 4, 3)) && try(tonumber(split("/", var.vnet_address_space)[1]) <= 20, false)
    error_message = "Use an IPv4 CIDR with a prefix length of /20 or smaller."
  }
}

variable "jumpbox_admin_password" {
  description = "Bastion login password supplied through TF_VAR_jumpbox_admin_password. Sensitive, but stored in Terraform state."
  type        = string
  sensitive   = true

  validation {
    condition = length(var.jumpbox_admin_password) >= 12 && length(var.jumpbox_admin_password) <= 72 && length([
      for pattern in ["[a-z]", "[A-Z]", "[0-9]", "[^a-zA-Z0-9]"] : pattern
      if can(regex(pattern, var.jumpbox_admin_password))
    ]) >= 3
    error_message = "Use 12-72 characters and at least three of: lowercase, uppercase, digits, and special characters."
  }
}

variable "jumpbox_admin_username" {
  description = "Administrator username shared by the Linux build VM and Windows desktop."
  type        = string
  default     = "azureuser"
}

variable "jumpbox_vm_size" {
  description = "Linux build VM SKU; confirm availability and quota before deployment."
  type        = string
  default     = "Standard_B2s"
}

variable "windows_desktop_vm_size" {
  description = "Windows 11 desktop VM SKU; requires eligible Windows client licensing and regional availability."
  type        = string
  default     = "Standard_D2as_v4"
}
