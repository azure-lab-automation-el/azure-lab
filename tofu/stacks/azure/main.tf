terraform {
  required_version = ">= 1.6"
  required_providers {
    azurerm = { source = "hashicorp/azurerm", version = "~> 4.0" }
  }
  # State stays out of git. Remote backend (Azure blob) gets wired when the first real apply is approved.
  backend "local" {}
}

provider "azurerm" {
  features {}
  use_oidc = true
  # subscription_id / tenant come from ARM_* env or OIDC at apply time - never literals in this repo.
}

variable "location" {
  type    = string
  default = "israelcentral"
}
variable "location_linux" {
  type    = string
  default = "swedencentral"
}
variable "admin_password" {
  type      = string
  sensitive = true
}
variable "linux_ssh_public_key" {
  type = string
}
variable "media_account_name" {
  type    = string
  default = "estherlabmedia8c8c3c92"
}

module "lab" {
  source               = "../../modules/azure-lab"
  location             = var.location
  location_linux       = var.location_linux
  admin_password       = var.admin_password
  linux_ssh_public_key = var.linux_ssh_public_key
  media_account_name   = var.media_account_name
}

output "lab" {
  value = module.lab
}
