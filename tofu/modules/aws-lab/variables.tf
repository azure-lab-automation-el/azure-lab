variable "prefix" {
  type    = string
  default = "esther"
}
variable "region" {
  type    = string
  default = "eu-west-1"
}
variable "vpc_cidr" {
  type    = string
  default = "10.77.0.0/16"
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
variable "dc_instance_type" {
  type    = string
  default = "t3.medium"
}
variable "esther_instance_type" {
  type    = string
  default = "t3.large"
}
variable "linux_instance_type" {
  type    = string
  default = "t3.micro"
}
variable "admin_password" {
  type        = string
  sensitive   = true
  description = "set via EC2 user-data/GetPasswordData flow"
}
variable "media_bucket_name" {
  type        = string
  description = "globally unique S3 bucket for install media"
}
