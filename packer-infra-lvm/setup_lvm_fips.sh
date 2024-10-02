#!/bin/bash
set -e

# Install required packages
sudo dnf install -y dracut-fips lvm2

# Enable FIPS mode
sudo fips-mode-setup --enable
sudo dracut -f

# Get available space
AVAILABLE_SPACE=$(df -BM / | awk 'NR==2 {print $4}' | sed 's/M//')

# Calculate file size (80% of available space)
FILE_SIZE=$((AVAILABLE_SPACE * 80 / 100))

echo "Creating a ${FILE_SIZE}M file for LVM"

# Create a file to use as a loop device
sudo dd if=/dev/zero of=/lvm-file bs=1M count=$FILE_SIZE

# Set up loop device
LOOP_DEVICE=$(sudo losetup -f --show /lvm-file)

# Set up LVM
sudo pvcreate $LOOP_DEVICE
sudo vgcreate vg_rhel $LOOP_DEVICE
sudo lvcreate -n lv_root -l 80%VG vg_rhel
sudo lvcreate -n lv_swap -l 20%VG vg_rhel

# Debug: LVM setup complete. Checking LVM configuration:
echo "Debug: LVM setup complete. Checking LVM configuration:"
sudo pvs
sudo vgs
sudo lvs

# Format logical volumes
sudo mkfs.xfs /dev/mapper/vg_rhel-lv_root
sudo mkswap /dev/mapper/vg_rhel-lv_swap

# Mount new root and copy data
sudo mkdir -p /mnt/new_root
sudo mount /dev/mapper/vg_rhel-lv_root /mnt/new_root
sudo rsync -avx --exclude={"/dev/*","/proc/*","/sys/*","/tmp/*","/run/*","/mnt/*","/media/*","/lost+found","/lvm-file"} / /mnt/new_root/

# Debug: Data copy complete. Checking new root contents:
echo "Debug: Data copy complete. Checking new root contents:"
ls -la /mnt/new_root

# Update fstab
sudo cp /mnt/new_root/etc/fstab /mnt/new_root/etc/fstab.bak
sudo sed -i '/^UUID.*\s\/\s/ s/^/#/' /mnt/new_root/etc/fstab
echo "/dev/mapper/vg_rhel-lv_root /    xfs     defaults        0 0" | sudo tee -a /mnt/new_root/etc/fstab
echo "/dev/mapper/vg_rhel-lv_swap none swap    sw              0 0" | sudo tee -a /mnt/new_root/etc/fstab

# Mount necessary filesystems for chroot
sudo mount --bind /dev /mnt/new_root/dev
sudo mount --bind /proc /mnt/new_root/proc
sudo mount --bind /sys /mnt/new_root/sys
sudo mount --bind /boot /mnt/new_root/boot

# Update GRUB configuration
sudo sed -i 's|root=/dev/nvme0n1p4|root=/dev/mapper/vg_rhel-lv_root rd.lvm.lv=vg_rhel/lv_root|g' /mnt/new_root/etc/default/grub
sudo chroot /mnt/new_root grub2-mkconfig -o /boot/grub2/grub.cfg
sudo sed -i 's|root=/dev/nvme0n1p4|root=/dev/mapper/vg_rhel-lv_root rd.lvm.lv=vg_rhel/lv_root|g' /mnt/new_root/boot/grub2/grub.cfg

# Debug: Updated GRUB configuration:
echo "Debug: Updated GRUB configuration:"
sudo cat /mnt/new_root/etc/default/grub
sudo cat /mnt/new_root/boot/grub2/grub.cfg | grep -i root

# Add necessary modules to initramfs
echo 'add_dracutmodules+=" lvm "' | sudo tee -a /mnt/new_root/etc/dracut.conf.d/lvm.conf
echo 'add_drivers+=" dm-mod "' | sudo tee -a /mnt/new_root/etc/dracut.conf.d/lvm.conf
echo 'force_drivers+=" dm-mod "' | sudo tee -a /mnt/new_root/etc/dracut.conf.d/lvm.conf

# Regenerate initramfs
sudo chroot /mnt/new_root dracut -f --regenerate-all

# Debug: Checking initramfs for LVM modules:
echo "Debug: Checking initramfs for LVM modules:"
sudo lsinitrd /mnt/new_root/boot/initramfs-$(uname -r).img | grep lvm

# Install GRUB
sudo chroot /mnt/new_root grub2-install --target=i386-pc --boot-directory=/boot $LOOP_DEVICE
sudo chroot /mnt/new_root grub2-install --target=x86_64-efi --efi-directory=/boot/efi --boot-directory=/boot --removable

# Unmount bind mounts
sudo umount /mnt/new_root/boot
sudo umount /mnt/new_root/sys
sudo umount /mnt/new_root/proc
sudo umount /mnt/new_root/dev

echo "LVM setup complete. Ready for reboot."