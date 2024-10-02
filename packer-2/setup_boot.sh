#!/bin/bash
set -e

CHROOT="/mnt/ec2-root"
DEVICE="/dev/nvme0n1"

# Partition the disk
parted -s $DEVICE mklabel gpt
parted -s $DEVICE mkpart primary fat32 1MiB 261MiB
parted -s $DEVICE set 1 esp on
parted -s $DEVICE mkpart primary xfs 261MiB 1285MiB
parted -s $DEVICE mkpart primary xfs 1285MiB 100%

# Format partitions
mkfs.vfat -F 32 ${DEVICE}p1
mkfs.xfs ${DEVICE}p2
mkfs.xfs ${DEVICE}p3

# Set up LVM
pvcreate ${DEVICE}p3
vgcreate VolGroup00 ${DEVICE}p3
lvcreate -L 4G -n rootVol VolGroup00
lvcreate -L 2G -n swapVol VolGroup00
lvcreate -L 1G -n homeVol VolGroup00
# ... create other logical volumes ...

# Format LVM volumes
mkfs.xfs /dev/VolGroup00/rootVol
mkswap /dev/VolGroup00/swapVol
mkfs.xfs /dev/VolGroup00/homeVol
# ... format other volumes ...

# Mount filesystems
mount /dev/VolGroup00/rootVol $CHROOT
mkdir -p $CHROOT/boot $CHROOT/boot/efi
mount ${DEVICE}p2 $CHROOT/boot
mount ${DEVICE}p1 $CHROOT/boot/efi
# ... mount other volumes ...

# Install GRUB
chroot $CHROOT grub2-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=RHEL
chroot $CHROOT grub2-install --target=i386-pc $DEVICE

# Generate GRUB config
chroot $CHROOT grub2-mkconfig -o /boot/grub2/grub.cfg

# Update initramfs
chroot $CHROOT dracut --force

# Generate fstab
genfstab -U $CHROOT > $CHROOT/etc/fstab