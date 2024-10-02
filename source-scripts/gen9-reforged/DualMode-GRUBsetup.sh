---
- name: DualMode GRUB setup
  hosts: all
  become: yes
  tasks:
    - name: Ensure necessary packages are installed
      package:
        name: grub2-pc
        state: present

    - name: Find EFI_HOME path
      command: rpm -ql grub2-common | grep '/EFI/'
      register: efi_home_path
      changed_when: false

    - name: Set EFI_HOME variable
      set_fact:
        EFI_HOME: "{{ efi_home_path.stdout }}"

    - name: Move EFI grub.cfg if it exists
      command: mv "{{ EFI_HOME }}/grub.cfg" /boot/grub2
      when: EFI_HOME is defined and EFI_HOME != '' and ansible_stat.exists
      args:
        creates: /boot/grub2/grub.cfg

    - name: Generate GRUB2 configuration
      command: grub2-mkconfig -o /boot/grub2/grub.cfg

    - name: Remove existing grubenv file if it exists
      file:
        path: /boot/grub2/grubenv
        state: absent

    - name: Create fresh grubenv file
      command: grub2-editenv /boot/grub2/grubenv create

    - name: Populate fresh grubenv file
      command: grub2-editenv /boot/grub2/grubenv set "{{ item.key }}={{ item.value }}"
      with_items: "{{ grubenv_list.stdout_lines | map('split', '=') | map('list') | map('zip', ['key', 'value']) | map('combine') }}"
      vars:
        grubenv_list: "{{ lookup('pipe', 'grub2-editenv ' + EFI_HOME + '/grubenv list') }}"

    - name: Remove EFI grubenv file if it exists
      file:
        path: "{{ EFI_HOME }}/grubenv"
        state: absent

    - name: Get BOOT UUID
      command: grub2-probe --target=fs_uuid /boot/grub2
      register: boot_uuid

    - name: Get GRUB directory
      command: grub2-mkrelpath /boot/grub2
      register: grub_dir

    - name: Ensure EFI grub.cfg is correctly populated
      copy:
        dest: "{{ EFI_HOME }}/grub.cfg"
        content: |
          connectefi scsi
          search --no-floppy --fs-uuid --set=dev {{ boot_uuid.stdout }}
          set prefix=(\$dev){{ grub_dir.stdout }}
          export \$prefix
          configfile \$prefix/grub.cfg

    - name: Remove stale grub2-efi.cfg file if it exists
      file:
        path: /etc/grub2-efi.cfg
        state: absent

    - name: Link BIOS- and EFI-boot GRUB-config files
      file:
        src: ../boot/grub2/grub.cfg
        dest: /etc/grub2-efi.cfg
        state: link

    - name: Calculate the /boot-hosting root-device
      command: df -P /boot/grub2
      register: grub_targ

    - name: Trim off partition-info
      set_fact:
        GRUB_TARG: "{{ grub_targ.stdout_lines[1].split()[0] | regex_replace('p.*', '') if grub_targ.stdout_lines[1].split()[0].startswith('/dev/nvme') else grub_targ.stdout_lines[1].split()[0][:-1] if grub_targ.stdout_lines[1].split()[0].startswith('/dev/xvd') else 'Unsupported disk-type' }}"
      when: grub_targ.stdout_lines[1].split()[0] is defined

    - name: Fail if unsupported disk-type
      fail:
        msg: "Unsupported disk-type. Aborting..."
      when: GRUB_TARG == 'Unsupported disk-type'

    - name: Install the /boot/grub2/i386-pc content
      command: grub2-install --target i386-pc "{{ GRUB_TARG }}"
