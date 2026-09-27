variable "prefix" {
  type    = string
  default = "esther"
}
variable "project" {
  type = string
}
variable "region" {
  type    = string
  default = "europe-west1"
}
variable "zone" {
  type    = string
  default = "europe-west1-b"
}
variable "subnet_cidr" {
  type    = string
  default = "10.77.1.0/24"
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
  default = "10.77.1.20"
}
variable "dc_machine_type" {
  type    = string
  default = "e2-medium"
}
variable "esther_machine_type" {
  type    = string
  default = "e2-standard-2"
}
variable "linux_machine_type" {
  type    = string
  default = "e2-micro"
}
variable "media_bucket_name" {
  type        = string
  description = "globally unique GCS bucket for install media"
}
