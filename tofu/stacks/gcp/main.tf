terraform {
  required_version = ">= 1.6"
  required_providers {
    google = { source = "hashicorp/google", version = "~> 6.0" }
  }
  backend "local" {}
}

provider "google" {
  project = var.project
  region  = var.region
  # credentials from env/OIDC at plan/apply time only - PLAN-ONLY until he approves spend.
}

variable "project" {
  type    = string
  default = "CHANGE-ME"
}
variable "region" {
  type    = string
  default = "europe-west1"
}
variable "media_bucket_name" {
  type    = string
  default = "esther-lab-media-CHANGE-ME"
}

module "lab" {
  source            = "../../modules/gcp-lab"
  project           = var.project
  region            = var.region
  media_bucket_name = var.media_bucket_name
}

output "lab" { value = module.lab }
