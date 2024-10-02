provider "aws" {
  region = "us-east-1"
}

variable "project_name" {
  default = "my-project"
}

variable "aws_region" {
  default = "us-east-1"
}

variable "aws_subnet_id" {
  default = "subnet-085c6713c789edc91"
}

variable "ssh_username" {
  default = "ec2-user"
}

variable "root_volume_size" {
  default = 20
}

resource "aws_instance" "rhel9_instance" {
  ami                         = data.aws_ami.rhel9_ami.id
  instance_type               = "t3.large"
  subnet_id                   = var.aws_subnet_id
  key_name                    = "mac-test"                  # SSH key for connection
  associate_public_ip_address = true
  tags = {
    Name = "${var.project_name}-rhel9-lvm-fips"
  }

  root_block_device {
    volume_size           = var.root_volume_size
    volume_type           = "gp3"
    delete_on_termination = true
  }

  ebs_block_device {
    device_name           = "/dev/xvdf"
    volume_size           = var.root_volume_size
    volume_type           = "gp3"
    delete_on_termination = true
  }

  # SSH access via public IP
  vpc_security_group_ids = ["sg-059c7b30031c81f0d"] # You will need to use a valid SG here

  connection {
    type     = "ssh"
    user     = var.ssh_username
    private_key = file("${path.module}/path-to-private-key.pem") # Update with actual key path
    host     = self.public_ip
  }
}

data "aws_ami" "rhel9_ami" {
  most_recent = true
  owners      = ["309956199498", "219670896067", "174003430611", "216406534498"]  # Red Hat and SPEL Owners

  filter {
    name   = "name"
    values = ["RHEL-9.*_HVM-*-x86_64-*-Hourly*-GP*", "spel-bootstrap-rhel-9-*.x86_64-gp*"]
  }

  filter {
    name   = "root-device-type"
    values = ["ebs"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

resource "aws_security_group" "allow_ssh" {
  name        = "allow_ssh"
  description = "Allow SSH inbound traffic"
  vpc_id      = "vpc-01a8230e50e13923b"  # Your VPC ID

  ingress {
    description = "Allow SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

output "rhel9_instance_public_ip" {
  value = aws_instance.rhel9_instance.public_ip
  description = "The public IP address of the RHEL 9 instance"
}