output "dc_instance" { value = google_compute_instance.dc.name }
output "esther_instance" { value = google_compute_instance.esther.name }
output "linux_instance" { value = google_compute_instance.linux.name }
output "media_bucket" { value = google_storage_bucket.media.name }
output "exec_hint" { value = "post-config: same scripts via gcloud compute ssh / os-config (adapter pending)" }
