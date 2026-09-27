resource "aws_vpc" "lab" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  tags                 = { Name = "${var.prefix}-lab-vpc" }
}

resource "aws_subnet" "lab" {
  vpc_id                  = aws_vpc.lab.id
  cidr_block              = var.subnet_cidr
  map_public_ip_on_launch = false
  tags                    = { Name = "${var.prefix}-lab-subnet" }
}

# No ingress at all by default - same posture as the Azure lab (private, no public IPs).
resource "aws_security_group" "lab" {
  name        = "${var.prefix}-lab-sg"
  description = "lab internal only"
  vpc_id      = aws_vpc.lab.id
  ingress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = [var.vpc_cidr]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

data "aws_ami" "windows_core" {
  most_recent = true
  owners      = ["amazon"]
  filter {
    name   = "name"
    values = ["Windows_Server-2022-English-Core-Base-*"]
  }
}

data "aws_ami" "windows_full" {
  most_recent = true
  owners      = ["amazon"]
  filter {
    name   = "name"
    values = ["Windows_Server-2022-English-Full-Base-*"]
  }
}

data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical
  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*"]
  }
}

resource "aws_instance" "dc" {
  ami                    = data.aws_ami.windows_core.id
  instance_type          = var.dc_instance_type
  subnet_id              = aws_subnet.lab.id
  private_ip             = var.dc_private_ip
  vpc_security_group_ids = [aws_security_group.lab.id]
  root_block_device {
    volume_size = 32
    volume_type = "gp3"
  }
  tags = { Name = "${var.prefix}-dc-01", Role = "dc" }
}

resource "aws_instance" "esther" {
  ami                    = data.aws_ami.windows_full.id
  instance_type          = var.esther_instance_type
  subnet_id              = aws_subnet.lab.id
  private_ip             = var.esther_private_ip
  vpc_security_group_ids = [aws_security_group.lab.id]
  root_block_device {
    volume_size = 64
    volume_type = "gp3"
  }
  tags = { Name = "${var.prefix}-adaxes-01", Role = "scom" }
}

resource "aws_instance" "linux" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.linux_instance_type
  subnet_id              = aws_subnet.lab.id
  private_ip             = var.linux_private_ip
  vpc_security_group_ids = [aws_security_group.lab.id]
  root_block_device {
    volume_size = 32
    volume_type = "gp3"
  }
  tags = { Name = "${var.prefix}-linux-01", Role = "linux-agent" }
}

resource "aws_s3_bucket" "media" {
  bucket = var.media_bucket_name
  tags   = { Name = "${var.prefix}-lab-media" }
}

resource "aws_s3_bucket_public_access_block" "media" {
  bucket                  = aws_s3_bucket.media.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}
