#!/bin/bash

echo "=========== EC2 Configuration Check ==========="

echo -e "\n1. Disk Partitions:"
lsblk

echo -e "\n2. LVM Setup:"
echo "Volume Groups:"
sudo vgs
echo "Logical Volumes:"
sudo lvs

echo -e "\n3. Filesystems:"
df -h

echo -e "\n4. /etc/fstab Contents:"
cat /etc/fstab

echo -e "\n5. GRUB Configuration:"
cat /etc/default/grub

echo -e "\n6. SELinux Status:"
getenforce

echo -e "\n7. Cloud-init Default User:"
grep "name:" /etc/cloud/cloud.cfg

echo -e "\n8. Network Interface Configuration:"
cat /etc/sysconfig/network-scripts/ifcfg-eth0

echo -e "\n9. Enabled Services:"
systemctl list-unit-files | grep enabled

echo -e "\n10. Timezone:"
timedatectl

echo -e "\n11. /tmp Filesystem:"
findmnt /tmp

echo -e "\n12. AWS CLI Version:"
aws --version

echo -e "\n=========== End of Configuration Check ==========="