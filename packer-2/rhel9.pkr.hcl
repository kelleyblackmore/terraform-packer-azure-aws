# Packer Template for RHEL 9 AMI with LVM and FIPS Mode Enabled



# Source Block
source "amazon-ebssurrogate" "rhel9" {
  ami_name              = "${var.project_name}-rhel9-lvm-fips-{{timestamp}}"
  instance_type               = "t3.large"
  region                      = var.aws_region
  ssh_username                = var.ssh_username
  associate_public_ip_address = true
  ssh_interface               = "public_ip"
  subnet_id                   = var.aws_subnet_id
  tags                        = { Name = "${var.project_name}-rhel9-lvm-fips" }
 

  
  ami_root_device {
    source_device_name    = "/dev/xvdf"
    delete_on_termination = true
    device_name           = "/dev/sda1"
    volume_size           = var.root_volume_size
    volume_type           = "gp3"
  }

  launch_block_device_mappings {
    delete_on_termination = true
    device_name           = "/dev/sda1"
    volume_size           = var.root_volume_size
    volume_type           = "gp3"
  }
  launch_block_device_mappings {
    delete_on_termination = true
    device_name           = "/dev/xvdf"
    volume_size           = var.root_volume_size
    volume_type           = "gp3"
  }


  source_ami_filter {
    filters = {
      name                   = "RHEL-9.*_HVM-*-x86_64-*-Hourly*-GP*,spel-bootstrap-rhel-9-*.x86_64-gp*"
      root-device-type       = "ebs"
      virtualization-type    = "hvm"
    }
    owners = [
      "309956199498", # Red Hat Commercial
      "219670896067", # Red Hat GovCloud
      "174003430611", # SPEL Commercial
      "216406534498", # SPEL GovCloud
    ]
    most_recent = true
  }


  ami_virtualization_type     = "hvm"  # Add virtualization type
  ena_support      = true
  communicator                = "ssh"
  ssh_timeout                 = "60m"  # Extended timeout if necessary
  ssh_pty                     = true
  shutdown_behavior           = "terminate"
  max_retries                 = 20
  ssh_port                    = 22
  
  use_create_image            = true



   user_data_file              = "${path.root}/userdata/userdata.cloud"
}

# Build Block
build {
  sources = ["source.amazon-ebssurrogate.rhel9"]


provisioner "shell" {
  inline = [
    "sudo dnf install -y https://s3.amazonaws.com/ec2-downloads-windows/SSMAgent/latest/linux_amd64/amazon-ssm-agent.rpm"
  ]
}
  
provisioner "shell" {
  inline = [
    "echo \"Instance Public IP: ${build.Host}\""
  ]
  inline_shebang = "/bin/sh -x"  # Enables debug mode for the shell script
}


provisioner "ansible" {
  playbook_file           = "playbook.yml"
  user                    = "ec2-user"
  use_proxy               = false
  inventory_file_template = "default ansible_host=${build.Host} ansible_user=${build.User} \n"
  keep_inventory_file     = true  # Retain the inventory file for inspection
  extra_arguments         = [
    "--extra-vars", "ansible_python_interpreter=/usr/bin/python3",
    "-vv"
   # "--log-path", "/tmp/ansible.log"
  ]
  
  ansible_ssh_extra_args  = [
    "-o", "StrictHostKeyChecking=no",
    "-o", "UserKnownHostsFile=/dev/null"
  ]
}

  

  # Clean up and finalize the image
  provisioner "shell" {
    execute_command = "chmod +x {{ .Path }}; {{ .Vars }} sudo -E sh '{{ .Path }}'"
    inline = [
      # Remove temporary files and logs
      "dnf clean all",
      "rm -rf /tmp/*"
    ]
    inline_shebang = "/bin/sh -x"
  }




}