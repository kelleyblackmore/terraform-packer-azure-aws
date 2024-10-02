---
- name: Setup build-chroot's physical and virtual storage
  hosts: localhost
  become: yes
  vars:
    chroot_dev: ""
    chroot_mnt: "{{ lookup('env', 'CHROOT') | default('/mnt/ec2-root', true) }}"
    debug: "{{ lookup('env', 'DEBUG') | default('UNDEF', true) }}"
    def_geom_arr:
      - /:rootVol:4
      - swap:swapVol:2
      - /home:homeVol:1
      - /var:varVol:2
      - /var/tmp:varTmpVol:2
      - /var/log:logVol:2
      - /var/log/audit:auditVol:100%FREE
    def_geom_str: "{{ def_geom_arr | join(',') }}"
    fstype: "{{ lookup('env', 'DEFFSTYPE') | default('xfs', true) }}"
    geometry_string: "{{ def_geom_str }}"
    valid_fstypes: "{{ lookup('pipe', 'awk \'!/^nodev/{ print $1}\' /proc/filesystems | tr \'\\n\' \' \'') }}"
    no_lvm: false
    vgname: ""
    partpre: ""

  tasks:
    - name: Ensure appropriate SEL mode is set
      include_role:
        name: no_sel

    - name: Validate target mount point
      block:
        - name: Check if mount point exists and is a directory
          stat:
            path: "{{ chroot_mnt }}"
          register: mount_point

        - name: Fail if mount point is already in use
          fail:
            msg: "Selected mount-point [{{ chroot_mnt }}] already in use. Aborting."
          when: mount_point.stat.isdir and mount_point.stat.mounted

        - name: Create mount point if it does not exist
          file:
            path: "{{ chroot_mnt }}"
            state: directory
            mode: '0755'
          when: not mount_point.stat.exists

    - name: Mount VG elements
      block:
        - name: Activate LVM volumes
          command: vgchange -a y "{{ vgname }}"
          when: not no_lvm

        - name: Create and mount LVM volumes
          block:
            - name: Create mount point
              file:
                path: "{{ chroot_mnt }}/{{ item.split(':')[0] }}"
                state: directory
                mode: '0755'
              with_items: "{{ geometry_string.split(',') }}"

            - name: Mount the filesystem
              mount:
                path: "{{ chroot_mnt }}/{{ item.split(':')[0] }}"
                src: "/dev/{{ vgname }}/{{ item.split(':')[1] }}"
                fstype: "{{ fstype }}"
                state: mounted
              with_items: "{{ geometry_string.split(',') }}"
              when: item.split(':')[0] != 'swap'

    - name: Mount /boot and /boot/efi partitions
      block:
        - name: Create /boot mount point
          file:
            path: "{{ chroot_mnt }}/boot"
            state: directory

        - name: Mount BIOS-boot partition
          mount:
            path: "{{ chroot_mnt }}/boot"
            src: "{{ chroot_dev }}{{ partpre }}3"
            fstype: "{{ fstype }}"
            state: mounted

        - name: Create /boot/efi mount point
          file:
            path: "{{ chroot_mnt }}/boot/efi"
            state: directory

        - name: Mount UEFI-boot partition
          mount:
            path: "{{ chroot_mnt }}/boot/efi"
            src: "{{ chroot_dev }}{{ partpre }}2"
            fstype: vfat
            state: mounted

    - name: Create block/character-special files
      block:
        - name: Create necessary directories
          file:
            path: "{{ chroot_mnt }}/{{ item }}"
            state: directory
          with_items:
            - proc
            - sys
            - dev/pts
            - dev/shm

        - name: Create character-special files
          block:
            - name: Create device node
              command: mknod -m {{ item.split(':')[3] }} {{ chroot_mnt }}{{ item.split(':')[0] }} c {{ item.split(':')[1] }} {{ item.split(':')[2] }}
              with_items:
                - /dev/null:1:3:000666
                - /dev/zero:1:5:000666
                - /dev/random:1:8:000666
                - /dev/urandom:1:9:000666
                - /dev/tty:5:0:000666:tty
                - /dev/console:5:1:000600
                - /dev/ptmx:5:2:000666:tty

            - name: Set ownership for device node
              file:
                path: "{{ chroot_mnt }}{{ item.split(':')[0] }}"
                owner: root
                group: "{{ item.split(':')[4] }}"
              when: item.split(':')[4] is defined
              with_items:
                - /dev/tty:5:0:000666:tty
                - /dev/ptmx:5:2:000666:tty

        - name: Bind-mount pseudo-filesystems
          mount:
            path: "{{ chroot_mnt }}{{ item }}"
            src: "{{ item }}"
            fstype: none
            opts: bind
            state: mounted
          with_items: "{{ lookup('pipe', 'grep -v \\"' + chroot_mnt + '\\" /proc/mounts | sed \'{/^none/d;/\\/tmp/d;/rootfs/d;/dev\\/sd/d;/dev\\/xvd/d;/dev\\/nvme/d;/\\/user\\//d;/\\/mapper\\//d;/^cgroup/d}\' | awk \'{ print $2 }\' | sort -u') }}"
