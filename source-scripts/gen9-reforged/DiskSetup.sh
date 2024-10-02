---
- name: Disk Setup
  hosts: all
  become: yes
  vars:
    bootdevszmin: 768
    bootdevsz: "{{ bootdevszmin }}"
    uefidevsz: 128
    chrootdev: UNDEF
    debug: UNDEF
    fstype: xfs
    label_boot: boot_disk
    label_uefi: UEFI_DISK
    rootlabel: root_disk
    vgname: VolGroup00
    geometrystring: ""
    mkfsforceopt: ""
    partpre: ""

  tasks:
    - name: Ensure appropriate SEL mode is set
      include_tasks: no_sel.bashlib

    - name: Print out a basic usage message
      debug:
        msg: |
          Usage: DiskSetup.sh [GNU long option] [option] ...
            Options:
              -B  Boot-partition size (default: 768MiB)
              -d  Base dev-node used for build-device
              -f  Filesystem-type used for root filesystems (default: xfs)
              -h  Print this message
              -l  for /boot filesystem (default: boot_disk)
              -L  for /boot/efi filesystem (default: UEFI_DISK)
              -p  Comma-delimited string of colon-delimited partition-specs
              -r  Label to apply to root-partition if not using LVM (default: root_disk)
              -v  Name assigned to root volume-group (default: VolGroup00)
              -U  UEFI-partition size (default: 256MiB)
            GNU long options:
              --boot-size  See "-B" short-option
              --disk  See "-d" short-option
              --fstype  See "-f" short-option
              --help  See "-h" short-option
              --label-boot  See "-l" short-option
              --label-uefi  See "-L" short-option
              --partition-string  See "-p" short-option
              --rootlabel  See "-r" short-option
              --uefi-size  See "-U" short-option
              --vgname  See "-v" short-option

    - name: Check if root
      fail:
        msg: "Must be root to execute disk-carving actions"
      when: ansible_user_id != 'root'

    - name: Determine partition prefix
      set_fact:
        partpre: "p"
      when: chrootdev is match("/dev/nvme")

    - name: Carve LVM
      block:
        - name: Clear the target-disk of partitioning and other structural data
          command: parted -s "{{ chrootdev }}" mklabel gpt
          ignore_errors: yes

        - name: Lay down the base partitions
          command: >
            parted -s "{{ chrootdev }}" -- mktable gpt
            mkpart primary "{{ fstype }}" 1049k 2m
            mkpart primary fat16 4096s $(( 2 + uefidevsz ))m
            mkpart primary xfs $(( 2 + uefidevsz ))m $(( ( 2 + uefidevsz ) + bootdevsz ))m
            mkpart primary xfs $(( ( 2 + uefidevsz ) + bootdevsz ))m 100%
            set 1 bios_grub on
            set 2 esp on
            set 3 bls_boot on
            set 4 lvm on

        - name: Create LVM objects
          block:
            - name: Create LVM2 PV
              command: pvcreate "{{ chrootdev }}{{ partpre }}4"
              when: chrootdev not in ['/dev/xvda', '/dev/nvme0n1']

            - name: Create root VolumeGroup
              command: vgcreate -y "{{ vgname }}" "{{ chrootdev }}{{ partpre }}4"

            - name: Create LVM2 volume-objects
              loop: "{{ partition_array }}"
              vars:
                partition_array: "{{ geometrystring.split(',') }}"
              block:
                - name: Create LVs
                  command: >
                    lvcreate --yes -W y {{ item.split(':')[2] | regex_search('FREE') | ternary('-l', '-L') }}
                    {{ item.split(':')[2] | regex_search('FREE') | ternary('100%FREE', item.split(':')[2] + 'g') }}
                    -n {{ item.split(':')[1] }} {{ vgname }}

                - name: Create FSes on LVs
                  command: >
                    mkfs -t {{ fstype }} {{ mkfsforceopt }} /dev/{{ vgname }}/{{ item.split(':')[1] }}
                  when: item.split(':')[0] != 'swap'

                - name: Create swap filesystem
                  command: mkswap /dev/{{ vgname }}/{{ item.split(':')[1] }}
                  when: item.split(':')[0] == 'swap'

      when: rootlabel is undefined and vgname is defined

    - name: Carve Bare
      block:
        - name: Clear the target-disk of partitioning and other structural data
          command: parted -s "{{ chrootdev }}" mklabel gpt
          ignore_errors: yes

        - name: Lay down the base partitions
          command: >
            parted -s "{{ chrootdev }}" -- mklabel gpt
            mkpart primary "{{ fstype }}" 1049k 2m
            mkpart primary fat16 4096s $(( 2 + uefidevsz ))m
            mkpart primary xfs $(( 2 + uefidevsz ))m $(( ( 2 + uefidevsz ) + bootdevsz ))m
            mkpart primary xfs $(( ( 2 + uefidevsz ) + bootdevsz ))m 100%
            set 1 bios_grub on
            set 2 esp on
            set 3 bls_boot on

        - name: Create FS on partitions
          command: mkfs -t "{{ fstype }}" "{{ mkfsforceopt }}" -L "{{ rootlabel }}" "{{ chrootdev }}{{ partpre }}4"

      when: rootlabel is defined and vgname is undefined

    - name: Setup Boot Parts
      block:
        - name: Make filesystem for /boot/efi
          command: mkfs -t vfat -n "{{ label_uefi }}" "{{ chrootdev }}{{ partpre }}2"

        - name: Make filesystem for /boot
          command: mkfs -t "{{ fstype }}" "{{ mkfsforceopt }}" -L "{{ label_boot }}" "{{ chrootdev }}{{ partpre }}3"
