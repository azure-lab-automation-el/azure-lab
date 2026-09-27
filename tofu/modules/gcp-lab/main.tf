resource "google_compute_network" "lab" {
  name                    = "${var.prefix}-lab-vpc"
  auto_create_subnetworks = false
}

resource "google_compute_subnetwork" "lab" {
  name                     = "${var.prefix}-lab-subnet"
  network                  = google_compute_network.lab.id
  region                   = var.region
  ip_cidr_range            = var.subnet_cidr
  private_ip_google_access = true
}

# Default-deny posture: no ingress rules are created; internal subnet traffic only.
resource "google_compute_firewall" "internal" {
  name          = "${var.prefix}-lab-internal"
  network       = google_compute_network.lab.id
  direction     = "INGRESS"
  source_ranges = [var.subnet_cidr]
  allow { protocol = "all" }
}

locals {
  windows_dc     = "projects/windows-cloud/global/images/family/windows-2022-core"
  windows_esther = "projects/windows-cloud/global/images/family/windows-2022"
  ubuntu         = "projects/ubuntu-os-cloud/global/images/family/ubuntu-2404-lts-amd64"
}

resource "google_compute_instance" "dc" {
  name         = "${var.prefix}-dc-01"
  machine_type = var.dc_machine_type
  zone         = var.zone
  boot_disk {
    initialize_params {
      image = local.windows_dc
      size  = 32
      type  = "pd-balanced"
    }
  }
  network_interface {
    subnetwork = google_compute_subnetwork.lab.id
    network_ip = var.dc_private_ip
  }
  shielded_instance_config {
    enable_secure_boot = true
    enable_vtpm        = true
  }
}

resource "google_compute_instance" "esther" {
  name         = "${var.prefix}-adaxes-01"
  machine_type = var.esther_machine_type
  zone         = var.zone
  boot_disk {
    initialize_params {
      image = local.windows_esther
      size  = 64
      type  = "pd-ssd"
    }
  }
  network_interface {
    subnetwork = google_compute_subnetwork.lab.id
    network_ip = var.esther_private_ip
  }
  shielded_instance_config {
    enable_secure_boot = true
    enable_vtpm        = true
  }
}

resource "google_compute_instance" "linux" {
  name         = "${var.prefix}-linux-01"
  machine_type = var.linux_machine_type
  zone         = var.zone
  boot_disk {
    initialize_params {
      image = local.ubuntu
      size  = 32
      type  = "pd-balanced"
    }
  }
  network_interface {
    subnetwork = google_compute_subnetwork.lab.id
    network_ip = var.linux_private_ip
  }
  shielded_instance_config {
    enable_secure_boot = true
    enable_vtpm        = true
  }
}

resource "google_storage_bucket" "media" {
  name                        = var.media_bucket_name
  location                    = upper(replace(var.region, "-", "_"))
  uniform_bucket_level_access = true
  public_access_prevention    = "enforced"
}
