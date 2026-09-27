output "dc_instance_id" { value = aws_instance.dc.id }
output "esther_instance_id" { value = aws_instance.esther.id }
output "linux_instance_id" { value = aws_instance.linux.id }
output "media_bucket" { value = aws_s3_bucket.media.bucket }
output "exec_hint" { value = "post-config: same scripts via AWS SSM Run Command (adapter pending)" }
