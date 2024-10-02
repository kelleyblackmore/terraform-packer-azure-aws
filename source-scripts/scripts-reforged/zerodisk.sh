---
- name: Zero out the free space to save space in the final image
    hosts: all
    tasks:
        - name: Zero out free space
            command: dd if=/dev/zero of=/EMPTY bs=1M
            ignore_errors: yes

        - name: Remove the EMPTY file
            file:
                path: /EMPTY
                state: absent

        - name: Sync to ensure that the delete completes
            command: sync
            register: sync_result
            until: sync_result is succeeded
            retries: 3
            delay: 5
