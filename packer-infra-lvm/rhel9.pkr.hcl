source "amazon-ebs" "rhel9" {
  ami_name                    = "${var.project_name}-rhel9-lvm-fips-{{timestamp}}"
  instance_type               = var.instance_type
  region                      = var.aws_region
  ssh_username                = var.ssh_username
  associate_public_ip_address = true
  subnet_id                   = var.aws_subnet_id
  security_group_ids          = [var.aws_security_group_id]

  tags = {
    Name        = "${var.project_name}-rhel9-lvm-fips"
    Environment = "production"
    Project     = var.project_name
    CreatedBy   = "packer"
  }

  source_ami_filter {
    filters = {
      name                = "RHEL-9.*_HVM-*-x86_64-*-Hourly*-GP3"
      root-device-type    = "ebs"
      virtualization-type = "hvm"
    }
    owners      = ["309956199498", "219670896067"]
    most_recent = true
  }

  launch_block_device_mappings {
    device_name           = "/dev/sda1"
    volume_size           = 20
    volume_type           = "gp3"
    delete_on_termination = true
  }

  ena_support = true
  communicator = "ssh"
  ssh_timeout  = "60m"
  ssh_port     = 22
  shutdown_behavior = "terminate"
  max_retries = 10
}

build {
  sources = ["source.amazon-ebs.rhel9"]

  provisioner "shell" {
    inline = [
      "sudo dnf install -y https://s3.amazonaws.com/ec2-downloads-windows/SSMAgent/latest/linux_amd64/amazon-ssm-agent.rpm",
      "sudo systemctl enable amazon-ssm-agent",
      "sudo systemctl start amazon-ssm-agent"
    ]
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
 
  provisioner "shell" {
    inline = [
      "echo 'Checking LVM setup before reboot:'",
      "sudo lvmdiskscan",
      "sudo pvs",
      "sudo vgs",
      "sudo lvs",
      "echo 'Checking for loop devices:'",
      "sudo losetup -a",
      "echo 'Checking fstab:'",
      "sudo cat /mnt/new_root/etc/fstab",
      "echo 'Checking boot configuration:'",
      "sudo cat /mnt/new_root/etc/default/grub",
      "sudo cat /mnt/new_root/boot/grub2/grub.cfg | grep -i root",
      "echo 'Checking initramfs for LVM modules:'",
      "sudo lsinitrd /mnt/new_root/boot/initramfs-$(uname -r).img | grep lvm"
    ]
  }
  provisioner "shell" {
    inline = ["sudo reboot"]
    expect_disconnect = true
  }



  provisioner "shell" {
    inline = [
      "sudo fips-mode-setup --check",
      "lsblk",
      "sudo vgdisplay",
      "sudo lvdisplay",
      "df -h /",
      "cat /etc/fstab",
      "mount | grep ' / '",
      "sudo blkid",
      "sudo cat /boot/grub2/grub.cfg | grep root="
    ]
  }

  provisioner "shell" {
    inline = [
      "sudo dnf clean all",
      "sudo rm -rf /tmp/* /var/tmp/* /var/log/*"
    ]
  }
}