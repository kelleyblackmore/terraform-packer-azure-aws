---
- name: Cleanup tasks
    hosts: all
    become: yes
    tasks:
        - name: Remove deps no longer needed
            yum:
                name: virt-what
                state: absent
                autoremove: yes

        - name: Generate RPM manifest
            shell: |
                cat /etc/redhat-release > /tmp/manifest.txt
                rpm -qa | sort -u >> /tmp/manifest.txt

        - name: Remove yum artifacts
            yum:
                name: '*'
                state: clean
                enablerepo: '*'
            ignore_errors: yes

        - name: Remove yum cache
            file:
                path: /var/cache/yum
                state: absent

        - name: Remove yum lib
            file:
                path: /var/lib/yum
                state: absent

        - name: Remove leftover DHCP leases
            file:
                path: /var/lib/dhclient
                state: absent

        - name: Remove udev rules
            file:
                path: /etc/udev/rules.d/70-persistent-net.rules
                state: absent

        - name: Create empty udev rules directory
            file:
                path: /etc/udev/rules.d/70-persistent-net.rules
                state: directory

        - name: Remove udev directory
            file:
                path: /dev/.udev/
                state: absent

        - name: Remove persistent net generator rules
            file:
                path: /lib/udev/rules.d/75-persistent-net-generator.rules
                state: absent

        - name: Shred SSH host keys
            shell: shred -uz /etc/ssh/*key*

        - name: Restart SSH service
            service:
                name: sshd
                state: restarted

        - name: Clean out miscellaneous log files
            shell: |
                for FILE in boot.log btmp cloud-init.log cloud-init-output.log cron dmesg \
                        dmesg.old dracut.log lastlog maillog messages secure spooler tallylog \
                        wtmp yum.log rhsm/rhsmcertd.log rhsm/rhsm.log sa/sa22
                do
                        if [[ -e /var/log/$FILE ]];
                        then
                                cat /dev/null > /var/log/${FILE}
                        fi
                done

        - name: Clean out audit logs
            find:
                paths: /var/log/audit
                recurse: yes
                file_type: file
                age: 0
                age_stamp: mtime
            register: audit_logs

        - name: Shred audit logs
            shell: shred -uz {{ item.path }}
            with_items: "{{ audit_logs.files }}"

        - name: Clean out root's history buffers and files
            shell: history -c && cat /dev/null > /root/.bash_history
