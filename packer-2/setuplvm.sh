#!/bin/bash -e

# Install LVM2 if not already installed
sudo yum install -y lvm2

# Identify the attached EBS volumes
DEVICE1="/dev/nvme1n1"    # AWS uses NVMe device names for EBS volumes
DEVICE2="/dev/nvme2n1"

# Wait for the devices to be available
while [ ! -b "$DEVICE1" ]; do sleep 1; done
while [ ! -b "$DEVICE2" ]; do sleep 1; done

# Create Physical Volumes
sudo pvcreate $DEVICE1 $DEVICE2

# Create a Volume Group
sudo vgcreate myvg $DEVICE1 $DEVICE2

# Create a Logical Volume (using 100% of the VG)
sudo lvcreate -l 100%FREE -n mylv myvg

# Format the Logical Volume with XFS filesystem (RHEL default)
sudo mkfs.xfs /dev/myvg/mylv

# Create a Mount Point
sudo mkdir -p /mnt/data

# Mount the Logical Volume
sudo mount /dev/myvg/mylv /mnt/data

# Get the UUID of the Logical Volume
UUID=$(sudo blkid -s UUID -o value /dev/myvg/mylv)

# Update /etc/fstab to mount at boot
echo "UUID=$UUID /mnt/data xfs defaults 0 0" | sudo tee -a /etc/fstab