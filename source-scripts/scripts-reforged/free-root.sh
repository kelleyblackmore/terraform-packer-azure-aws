---
- name: Free root tasks
  hosts: all
  become: yes
  tasks:
    - name: Restart systemd
      command: systemctl daemon-reexec

    - name: Check if auditd service is running
      shell: service auditd status > /dev/null 2>&1
      register: auditd_status
      ignore_errors: yes

    - name: Stop auditd service if running
      service:
        name: auditd
        state: stopped
      when: auditd_status.rc == 0

    - name: Get list of running services
      command: systemctl list-units --type=service --state=running
      register: running_services

    - name: Stop non-essential services
      shell: |
        for SERVICE in $(echo "{{ running_services.stdout }}" | awk '/loaded active running/{ print $1 }' | grep -Ev '(audit|sshd|user@)')
        do
          systemctl stop "${SERVICE}"
        done

    - name: Sleep to allow everything to stop
      pause:
        seconds: 10

    - name: Check if /oldroot is a mountpoint
      command: mountpoint -q /oldroot
      register: oldroot_mountpoint
      ignore_errors: yes

    - name: Kill processes locking /oldroot if it is a mount
      command: fuser -vmk /oldroot
      when: oldroot_mountpoint.rc == 0
