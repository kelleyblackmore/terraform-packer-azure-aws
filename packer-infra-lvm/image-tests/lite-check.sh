#!/bin/bash

echo 'Checking LVM setup:'
sudo lvmdiskscan
sudo pvs
sudo vgs
sudo lvs

echo 'Checking for loop devices:'
sudo losetup -a

echo 'Checking fstab:'
cat /etc/fstab

echo 'Checking current mounts:'
mount

echo 'Checking boot configuration:'
cat /boot/grub2/grub.cfg | grep -i root

echo 'Checking initramfs for LVM modules:'
lsinitrd /boot/initramfs-$(uname -r).img | grep lvm

echo 'Checking system logs for boot issues:'
sudo journalctl -b | grep -i 'lvm\|volume\|mapper'