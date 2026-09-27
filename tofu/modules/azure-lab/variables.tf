variable "prefix" {
  type    = string
  default = "esther"
}
variable "rg_name" {
  type    = string
  default = "rg-learning-monitoring"
}
variable "location" {
  type        = string
  default     = "israelcentral"
  description = "hub region (policy-approved only)"
}
variable "location_linux" {
  type        = string
  default     = "swedencentral"
  description = "linux spoke region"
}
variable "hub_cidr" {
  type    = string
  default = "10.77.0.0/16"
}
variable "hub_subnet_cidr" {
  type    = string
  default = "10.77.1.0/24"
}
variable "spoke_cidr" {
  type    = string
  default = "10.78.0.0/16"
}
variable "spoke_subnet_cidr" {
  type    = string
  default = "10.78.1.0/24"
}
variable "dc_private_ip" {
  type    = string
  default = "10.77.1.10"
}
variable "esther_private_ip" {
  type    = string
  default = "10.77.1.4"
}
variable "linux_private_ip" {
  type    = string
  default = "10.78.1.20"
}
variable "dc_size" {
  type    = string
  default = "Standard_B2ats_v2"
}
variable "esther_size" {
  type    = string
  default = "Standard_B2as_v2"
}
variable "linux_size" {
  type    = string
  default = "Standard_B2ats_v2"
}
variable "admin_username" {
  type    = string
  default = "estherlabadmin"
}
variable "admin_password" {
  type      = string
  sensitive = true
}
variable "linux_admin_username" {
  type    = string
  default = "scomlab"
}
variable "linux_ssh_public_key" {
  type = string
}
variable "media_account_name" {
  type        = string
  description = "globally unique storage account name for install media"
}
variable "enable_linux_spoke" {
  type    = bool
  default = true
}
