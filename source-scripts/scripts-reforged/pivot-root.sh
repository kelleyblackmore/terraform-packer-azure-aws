---
- name: Pivot root partition to tmpfs
  hosts: all
  become: yes
  tasks:
    - name: Install psmisc RPM
      yum:
        name: psmisc
        state: present

    - name: Unmount /boot and /boot/efi if mounted
      shell: |
        for BOOT_DIR in /boot{/efi,}; do
          if [[ -d ${BOOT_DIR} ]] && [[ $( mountpoint "${BOOT_DIR}" ) == "${BOOT_DIR} is a mountpoint" ]]; then
            fuser -vmk "${BOOT_DIR}" || true
            umount "${BOOT_DIR}"
          fi
        done
      args:
        executable: /bin/bash

    - name: Create /tmp/tmproot directory
      file:
        path: /tmp/tmproot
        state: directory
        mode: '0755'

    - name: Mount tmpfs to /tmp/tmproot
      mount:
        path: /tmp/tmproot
        src: none
        fstype: tmpfs
        state: mounted

    - name: Copy / to /tmp/tmproot
      command: cp -ax / /tmp/tmproot

    - name: Copy dev-nodes to /tmp/tmproot
      command: cp -a /dev /tmp/tmproot

    - name: Create /tmp/tmproot/oldroot directory
      file:
        path: /tmp/tmproot/oldroot
        state: directory

    - name: Prepare for pivot_root action
      command: mount --make-rprivate /

    - name: Execute pivot_root
      command: pivot_root /tmp/tmproot /tmp/tmproot/oldroot

    - name: Move sub-mounts into /oldroot
      block:
        - name: Move /dev
          command: mount --move /oldroot/dev /dev

        - name: Move /proc
          command: mount --move /oldroot/proc /proc

        - name: Move /sys
          command: mount --move /oldroot/sys /sys

        - name: Move /run
          command: mount --move /oldroot/run /run

        - name: Move /tmp if it is a mountpoint
          shell: |
            if [[ $( mountpoint /oldroot/tmp ) =~ "is a mountpoint" ]]; then
              mount --move /oldroot/tmp /tmp
            fi
          args:
            executable: /bin/bash

    - name: Unmount everything we can on /oldroot
      shell: |
        MOUNTS=$(cut -d ' ' -f 2 /proc/mounts | grep '/oldroot/' | sort -ru)
        if [[ ${#MOUNTS} -ne 0 ]]; then
          echo "$MOUNTS" | while IFS= read -r MOUNT; do
            umount "$MOUNT" || true
          done
        fi
      args:
        executable: /bin/bash

    - name: Stop firewalld if active
      systemd:
        name: firewalld
        state: stopped
      when: ansible_facts.services["firewalld"].state == "running"

    - name: Restart sshd
      systemd:
        name: sshd
        state: restarted

    - name: Kill ssh processes to release locks on /oldroot
      command: pkill --signal HUP sshd
