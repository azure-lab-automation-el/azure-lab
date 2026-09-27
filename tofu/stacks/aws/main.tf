terraform {
  required_version = ">= 1.6"
  required_providers {
    aws = { source = "hashicorp/aws", version = "~> 5.0" }
  }
  backend "local" {}
}

provider "aws" {
  region = var.region
  # credentials from env/OIDC at plan/apply time only - PLAN-ONLY until he approves spend.
}

variable "region" {
  type    = string
  default = "eu-west-1"
}
variable "admin_password" {
  type      = string
  sensitive = true
  default   = "PLAN-ONLY-placeholder1!"
}
variable "media_bucket_name" {
  type    = string
  default = "esther-lab-media-CHANGE-ME"
}

module "lab" {
  source            = "../../modules/aws-lab"
  region            = var.region
  admin_password    = var.admin_password
  media_bucket_name = var.media_bucket_name
}

output "lab" { value = module.lab }
