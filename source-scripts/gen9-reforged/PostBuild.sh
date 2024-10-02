---
- name: PostBuild Tasks
  hosts: localhost
  become: yes
  vars:
    chrootmnt: "{{ chrootmnt | default('/mnt/ec2-root') }}"
    fipsdisable: "{{ fipsdisable | default('UNDEF') }}"
    grubtmout: "{{ grubtmout | default('5') }}"
    maintusr: "{{ maintusr | default('maintuser') }}"
    notmpfs: "{{ notmpfs | default('UNDEF') }}"
    targtz: "{{ targtz | default('UTC') }}"
    subscription_manager: "{{ subscription_manager | default('disabled') }}"
    iscrossdistro: "{{ iscrossdistro | default('') }}"
    fstype: "{{ fstype | default('') }}"
    validfstypes: ['xfs', 'ext2', 'ext3', 'ext4']

  tasks:
    - name: Create /etc/fstab in chroot-dev
      block:
        - name: Find chroot device
          command: findmnt -cnM "{{ chrootmnt }}" -o SOURCE
          register: chrootdev

        - name: Find chroot filesystem type
          command: findmnt -cnM "{{ chrootmnt }}" -o FSTYPE
          register: chrootfstyp

        - name: Set up /etc/fstab for non-LVMed chroot-dev
          when: iscrossdistro != ''
          block:
            - name: Get root label for xfs
              command: xfs_admin -l "{{ chrootdev.stdout }}"
              register: rootlabel
              when: chrootfstyp.stdout == 'xfs'

            - name: Get root label for ext2-4
              command: e2label "{{ chrootdev.stdout }}"
              register: rootlabel
              when: chrootfstyp.stdout in ['ext2', 'ext3', 'ext4']

            - name: Write /etc/fstab
              lineinfile:
                path: "{{ chrootmnt }}/etc/fstab"
                line: "LABEL={{ rootlabel.stdout }}\t/\t{{ chrootfstyp.stdout }}\tdefaults\t0 0"

        - name: Set up /etc/fstab for LVMed chroot-dev
          when: iscrossdistro == ''
          block:
            - name: Append to /etc/fstab
              shell: |
                grep "{{ chrootmnt }}" /proc/mounts | \
                grep -w "/dev/mapper" | \
                sed -e "s/{{ fstype }}.*/{{ fstype }}\tdefaults,rw\t0 0/" \
                    -e "s#{{ chrootmnt }}\s#/\t#" \
                    -e "s#{{ chrootmnt }}##" >> "{{ chrootmnt }}/etc/fstab"

        - name: Add swap devices to /etc/fstab
          block:
            - name: Get swap devices
              command: blkid | awk -F: '/TYPE="swap"/{ print $1 }'
              register: swap_devs

            - name: Add swap to /etc/fstab
              lineinfile:
                path: "{{ chrootmnt }}/etc/fstab"
                line: "{{ item }}\tnone\tswap\tdefaults\t0 0"
              loop: "{{ swap_devs.stdout_lines }}"
              when: item not in lookup('file', '/proc/swaps')

        - name: Add /boot partition to /etc/fstab
          block:
            - name: Get boot partition
              command: grep "{{ chrootmnt }}/boot " /proc/mounts | sed 's/ /:/g'
              register: boot_part

            - name: Add XFS-formatted /boot filesystem to fstab
              when: boot_part.stdout is search(':xfs:')
              block:
                - name: Get boot label
                  command: xfs_admin -l "{{ boot_part.stdout.split(':')[0] }}"
                  register: boot_label

                - name: Write /boot to /etc/fstab
                  lineinfile:
                    path: "{{ chrootmnt }}/etc/fstab"
                    line: "LABEL={{ boot_label.stdout }}\t/boot\txfs\tdefaults,rw\t0 0"

            - name: Add EXTn-formatted /boot filesystem to fstab
              when: boot_part.stdout is search(':ext[2-4]:')
              block:
                - name: Get boot label
                  command: e2label "{{ boot_part.stdout.split(':')[0] }}"
                  register: boot_label

                - name: Get boot filesystem type
                  command: echo "{{ boot_part.stdout.split(':')[2] }}"
                  register: boot_fstyp

                - name: Write /boot to /etc/fstab
                  lineinfile:
                    path: "{{ chrootmnt }}/etc/fstab"
                    line: "LABEL={{ boot_label.stdout }}\t/boot\t{{ boot_fstyp.stdout }}\tdefaults,rw\t0 0"

        - name: Add /boot/efi partition to /etc/fstab
          block:
            - name: Get UEFI partition
              command: grep "{{ chrootmnt }}/boot/efi " /proc/mounts | sed 's/ /:/g'
              register: uefi_part

            - name: Get UEFI label
              command: fatlabel "{{ uefi_part.stdout.split(':')[0] }}"
              register: uefi_label

            - name: Write /boot/efi to /etc/fstab
              lineinfile:
                path: "{{ chrootmnt }}/etc/fstab"
                line: "LABEL={{ uefi_label.stdout }}\t/boot/efi\tvfat\tdefaults,rw\t0 0"

        - name: Apply SELinux label to fstab
          when: ansible_facts['selinux']['status'] == 'enabled'
          command: chcon --reference /etc/fstab "{{ chrootmnt }}/etc/fstab"

    - name: Set /tmp as a tmpfs
      block:
        - name: Unmask tmp.mount unit
          command: chroot "{{ chrootmnt }}" /bin/systemctl unmask tmp.mount
          when: notmpfs != 'true'

        - name: Enable tmp.mount unit
          command: chroot "{{ chrootmnt }}" /bin/systemctl enable tmp.mount
          when: notmpfs != 'true'

    - name: Configure logging
      block:
        - name: Null out log files
          find:
            paths: "{{ chrootmnt }}/var/log"
            recurse: yes
            file_type: file
          register: log_files

        - name: Null log files
          command: cat /dev/null > "{{ item.path }}"
          loop: "{{ log_files.files }}"

        - name: Persist journald logs
          lineinfile:
            path: "{{ chrootmnt }}/etc/systemd/journald.conf"
            line: 'Storage=persistent'

        - name: Ensure /var/log/journal exists
          file:
            path: "{{ chrootmnt }}/var/log/journal"
            state: directory
            mode: '0755'

        - name: Ensure journald logfile storage exists
          command: chroot "{{ chrootmnt }}" systemd-tmpfiles --create --prefix /var/log/journal

    - name: Configure networking
      block:
        - name: Set up ifcfg-eth0 file
          copy:
            dest: "{{ chrootmnt }}/etc/sysconfig/network-scripts/ifcfg-eth0"
            content: |
              DEVICE="eth0"
              BOOTPROTO="dhcp"
              ONBOOT="yes"
              TYPE="Ethernet"
              USERCTL="yes"
              PEERDNS="yes"
              IPV6INIT="no"
              PERSISTENT_DHCLIENT="1"

        - name: Set up network file
          copy:
            dest: "{{ chrootmnt }}/etc/sysconfig/network"
            content: |
              NETWORKING="yes"
              NETWORKING_IPV6="no"
              NOZEROCONF="yes"
              HOSTNAME="localhost.localdomain"

        - name: Ensure NetworkManager starts
          command: chroot "{{ chrootmnt }}" systemctl enable NetworkManager

    - name: Set up firewalld
      block:
        - name: Set up baseline firewall rules
          command: chroot "{{ chrootmnt }}" /bin/bash -c "(
            firewall-offline-cmd --set-default-zone=drop
            firewall-offline-cmd --zone=trusted --change-interface=lo
            firewall-offline-cmd --zone=drop --add-service=ssh
            firewall-offline-cmd --zone=drop --add-service=dhcpv6-client
            firewall-offline-cmd --zone=drop --add-icmp-block-inversion
            firewall-offline-cmd --zone=drop --add-icmp-block=fragmentation-needed
            firewall-offline-cmd --zone=drop --add-icmp-block=packet-too-big
          )"

    - name: Configure time services
      block:
        - name: Set default timezone
          file:
            path: "{{ chrootmnt }}/etc/localtime"
            state: absent

        - name: Link timezone
          command: chroot "{{ chrootmnt }}" ln -s "/usr/share/zoneinfo/{{ targtz }}" /etc/localtime
          when: targtz != 'UTC'

    - name: Configure cloud-init
      block:
        - name: Get cloud-init user
          command: grep -E "name: (maintuser|centos|ec2-user|cloud-user|almalinux)" "{{ chrootmnt }}/etc/cloud/cloud.cfg" | awk '{print $2}'
          register: clinitusr

        - name: Allow password logins to SSH
          lineinfile:
            path: "{{ chrootmnt }}/etc/cloud/cloud.cfg"
            regexp: '^ssh_pwauth'
            line: 'ssh_pwauth: true'
          when: clinitusr.stdout != ''

        - name: Nuke standard system_info block
          command: sed -i '/^system_info/,/^  ssh_svcname/d' "{{ chrootmnt }}/etc/cloud/cloud.cfg"
          when: clinitusr.stdout != ''

        - name: Replace system_info block
          blockinfile:
            path: "{{ chrootmnt }}/etc/cloud/cloud.cfg"
            block: |
              system_info:
                default_user:
                  name: '{{ maintusr }}'
                  lock_passwd: true
                  gecos: Local Maintenance User
                  groups: [wheel, adm]
                  sudo: ['ALL=(root) TYPE=sysadm_t ROLE=sysadm_r NOPASSWD:ALL']
                  shell: /bin/bash
                  selinux_user: staff_u
                distro: rhel
                paths:
                  cloud_dir: /var/lib/cloud
                  templates_dir: /etc/cloud/templates
                ssh_svcname: sshd
          when: clinitusr.stdout != ''

        - name: Enable SEL lookups by nsswitch
          lineinfile:
            path: "{{ chrootmnt }}/etc/nsswitch.conf"
            line: 'sudoers: files'
          when: clinitusr.stdout != ''

    - name: Do GRUB2 setup tasks
      block:
        - name: Check kernel in chroot-dev
          command: chroot "{{ chrootmnt }}" rpm --qf '%{version}-%{release}.%{arch}\n' -q kernel
          register: chrootkrn

        - name: Check if chroot-dev is LVM2'ed
          command: grep "{{ chrootmnt }}" /proc/mounts | awk '/^\/dev\/mapper/{ print $1 }'
          register: vgcheck

        - name: Determine root token for non-LVM
          when: vgcheck.stdout == ''
          block:
            - name: Get root label for xfs
              command: xfs_admin -l "{{ chrootdev.stdout }}"
              register: roottok
              when: chrootfstyp.stdout == 'xfs'

            - name: Get root label for ext2-4
              command: e2label "{{ chrootdev.stdout }}"
              register: roottok
              when: chrootfstyp.stdout in ['ext2', 'ext3', 'ext4']

        - name: Determine root token for LVM
          when: vgcheck.stdout != ''
          block:
            - name: Set root token
              set_fact:
                roottok: "root={{ vgcheck.stdout }}"

            - name: Get PV from VG info
              command: vgs --no-headings -o pv_name "{{ vgcheck.stdout | regex_replace('/dev/mapper/', '') }}" | sed 's/[ \t][ \t]*//g'
              register: chrootdev

            - name: Clip partition
              set_fact:
                chrootdev: "{{ chrootdev.stdout | regex_replace('p.*', '') if 'nvme' in chrootdev.stdout else chrootdev.stdout | regex_replace('[0-9]', '') }}"

        - name: Assemble GRUB_CMDLINE_LINUX value
          set_fact:
            grubcmdline: "{{ roottok }} vconsole.keymap=us vconsole.font=latarcyrheb-sun16 console=tty1 console=ttyS0,115200n8 rd.blacklist=nouveau net.ifnames=0 nvme_core.io_timeout=4294967295 {{ 'fips=0' if fipsdisable == 'true' else '' }}"

        - name: Write default/grub contents
          copy:
            dest: "{{ chrootmnt }}/etc/default/grub"
            content: |
              GRUB_TIMEOUT={{ grubtmout }}
              GRUB_DISTRIBUTOR="CentOS Linux"
              GRUB_DEFAULT=saved
              GRUB_DISABLE_SUBMENU=true
              GRUB_TERMINAL_OUTPUT="console"
              GRUB_SERIAL_COMMAND="serial --speed=115200"
              GRUB_CMDLINE_LINUX="{{ grubcmdline }}"
              GRUB_DISABLE_RECOVERY=true
              GRUB_DISABLE_OS_PROBER=true
              GRUB_ENABLE_BLSCFG=true

        - name: Reinstall GRUB-related RPMs
          command: dnf reinstall -y shim-x64 grub2-*

        - name: Install GRUB2 bootloader when EFI not active
          when: ansible_facts['firmware'] != 'efi'
          command: chroot "{{ chrootmnt }}" /bin/bash -c "/sbin/grub2-install {{ chrootdev }}"

        - name: Install BIOS-boot GRUB components
          command: chroot "{{ chrootmnt }}" /bin/bash -c "grub2-install {{ chrootdev }} --target=i386-pc"

        - name: Install GRUB config-file
          command: chroot "{{ chrootmnt }}" /bin/bash -c "/sbin/grub2-mkconfig -o /boot/grub2/grub.cfg --update-bls-cmdline"

        - name: Enable FIPS mode
          when: fipsdisable != 'true'
          command: chroot "{{ chrootmnt }}" /bin/bash -c "fips-mode-setup --enable"

        - name: Install initramfs
          when: fipsdisable == 'true'
          command: chroot "{{ chrootmnt }}" dracut -fv "/boot/initramfs-{{ chrootkrn.stdout }}.img" "{{ chrootkrn.stdout }}"

    - name: Initialize authselect subsystem
      command: chroot "{{ chrootmnt }}" /bin/authselect select sssd --force

    - name: Wholly disable kdump service
      block:
        - name: Disable kdump service
          command: chroot "{{ chrootmnt }}" /bin/systemctl disable --now kdump

        - name: Mask kdump service
          command: chroot "{{ chrootmnt }}" /bin/systemctl mask --now kdump

    - name: Clean up yum/dnf history
      block:
        - name: Clean yum history
          command: chroot "{{ chrootmnt }}" yum clean --enablerepo=* -y packages

        - name: Nuke DNF history DBs
          command: chroot "{{ chrootmnt }}" rm -rf /var/lib/dnf/history.*

    - name: Apply SELinux settings
      block:
        - name: Set up SELinux configuration
          command: chroot "{{ chrootmnt }}" /bin/sh -c "(
            rpm -q --scripts selinux-policy-targeted | \
            sed -e '1,/^postinstall scriptlet/d' | \
            sed -e '1i #!/bin/sh'
          ) > /tmp/selinuxconfig.sh ; \
          bash -x /tmp/selinuxconfig.sh 1"

        - name: Run fixfiles in chroot
          command: chroot "{{ chrootmnt }}" /sbin/fixfiles -f relabel

        - name: Create /.autorelabel file
          file:
            path: "{{ chrootmnt }}/.autorelabel"
            state: touch
          when: ansible_facts['selinux']['status'] != 'enabled'
