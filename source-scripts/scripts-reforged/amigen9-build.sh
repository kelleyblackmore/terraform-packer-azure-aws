---
- name: Execute AMIGen9 scripts to prepare an EC2 instance for the AMI Create Image task
    hosts: localhost
    become: yes
    vars:
        PROGNAME: "{{ ansible_playbook_name }}"
        AMIGENBOOTSIZE: "{{ lookup('env', 'SPEL_AMIGENBOOTDEVSZ') | default('768') }}"
        AMIGENBOOTLABL: "{{ lookup('env', 'SPEL_AMIGENBOOTDEVLBL') | default('boot_disk') }}"
        AMIGENBRANCH: "{{ lookup('env', 'SPEL_AMIGENBRANCH') | default('main') }}"
        AMIGENCHROOT: "{{ lookup('env', 'SPEL_AMIGENCHROOT') | default('/mnt/ec2-root') }}"
        AMIGENFSTYPE: "{{ lookup('env', 'SPEL_AMIGENFSTYPE') | default('xfs') }}"
        AMIGENMANFST: "{{ lookup('env', 'SPEL_AMIGENMANFST') }}"
        AMIGENPKGGRP: "{{ lookup('env', 'SPEL_AMIGENPKGGRP') | default('core') }}"
        AMIGENREPOS: "{{ lookup('env', 'SPEL_AMIGENREPOS') }}"
        AMIGENREPOSRC: "{{ lookup('env', 'SPEL_AMIGENREPOSRC') }}"
        AMIGENROOTNM: "{{ lookup('env', 'SPEL_AMIGENROOTNM') }}"
        AMIGENSOURCE: "{{ lookup('env', 'SPEL_AMIGEN9SOURCE') | default('https://github.com/plus3it/AMIgen9.git') }}"
        AMIGENSTORLAY: "{{ lookup('env', 'SPEL_AMIGENSTORLAY') }}"
        AMIGENTIMEZONE: "{{ lookup('env', 'SPEL_TIMEZONE') | default('UTC') }}"
        AMIGENUEFISIZE: "{{ lookup('env', 'SPEL_AMIGENUEFIDEVSZ') | default('128') }}"
        AMIGENUEFILABL: "{{ lookup('env', 'SPEL_AMIGENUEFIDEVLBL') | default('UEFI_DISK') }}"
        AMIGENVGNAME: "{{ lookup('env', 'SPEL_AMIGENVGNAME') }}"
        CLOUDPROVIDER: "{{ lookup('env', 'SPEL_CLOUDPROVIDER') | default('aws') }}"
        EXTRARPMS: "{{ lookup('env', 'SPEL_EXTRARPMS') }}"
        FIPSDISABLE: "{{ lookup('env', 'SPEL_FIPSDISABLE') }}"
        GRUBTMOUT: "{{ lookup('env', 'SPEL_GRUBTMOUT') | default('5') }}"
        HTTP_PROXY: "{{ lookup('env', 'SPEL_HTTP_PROXY') }}"
        USEDEFAULTREPOS: "{{ lookup('env', 'SPEL_USEDEFAULTREPOS') | default('true') }}"
        USEROOTDEVICE: "{{ lookup('env', 'SPEL_USEROOTDEVICE') | default('true') }}"
        ELBUILD: "/tmp/el-build"
        DEBUG: "{{ lookup('env', 'DEBUG') | default('true') }}"
        AWSCLIV1SOURCE: "{{ lookup('env', 'SPEL_AWSCLIV1SOURCE') }}"
        AWSCLIV2SOURCE: "{{ lookup('env', 'SPEL_AWSCLIV2SOURCE') | default('https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip') }}"
        AWSCFNBOOTSTRAP: "{{ lookup('env', 'SPEL_AWSCFNBOOTSTRAP') }}"
        AMIGENSSMAGENT: "{{ lookup('env', 'SPEL_AMIGENSSMAGENT') }}"
        AMIGENICNCTURL: "{{ lookup('env', 'SPEL_AMIGENICNCTURL') }}"

    tasks:
        - name: Restart networkd/resolved for DNS resolution
            ansible.builtin.systemd:
                name: "{{ item }}"
                state: restarted
            loop:
                - systemd-networkd
                - systemd-resolved

        - name: Ensure build-tools directory exists
            ansible.builtin.file:
                path: "{{ ELBUILD }}"
                state: directory
                mode: '0755'

        - name: Pull build-tools from git clone-source
            ansible.builtin.git:
                repo: "{{ AMIGENSOURCE }}"
                dest: "{{ ELBUILD }}"
                version: "{{ AMIGENBRANCH }}"

        - name: Detect the root device
            ansible.builtin.command: grep ' / ' /proc/mounts
            register: root_device

        - name: Set ROOT_DEV and ROOT_DISK
            ansible.builtin.set_fact:
                ROOT_DEV: "{{ root_device.stdout.split()[0] }}"
                ROOT_DISK: "{{ (root_device.stdout.split()[0] | regex_replace('p.*', '')) if root_device.stdout.split()[0].startswith('/dev/nvme') else '' }}"
                DISKS: "{{ ansible_devices.keys() | select('match', '^nvme.*n1$') | list }}"

        - name: Check if using root device
            ansible.builtin.set_fact:
                AMIGENBUILDDEV: "{{ ROOT_DISK if USEROOTDEVICE == 'true' else (DISKS | difference([ROOT_DISK]) | first) }}"
            when: USEROOTDEVICE == 'true' or DISKS | length <= 2

        - name: Fail if more than 2 disks are attached
            ansible.builtin.fail:
                msg: "This script supports at most 2 attached disks. Detected {{ DISKS | length }} disks"
            when: DISKS | length > 2

        - name: Ensure the disk has a GPT label
            ansible.builtin.command: parted -s "{{ AMIGENBUILDDEV }}" -- mklabel gpt
            when: AMIGENBUILDDEV is defined and AMIGENBUILDDEV != ''

        - name: Clone AMIGen9 repository
            ansible.builtin.git:
                repo: "{{ AMIGENSOURCE }}"
                dest: "{{ ELBUILD }}"
                version: "{{ AMIGENBRANCH }}"

        - name: Run the builder-scripts
            ansible.builtin.command: bash -euxo pipefail "{{ ELBUILD }}/{{ item }}"
            loop:
                - "{{ ComposeDiskSetupString }}"
                - "{{ ComposeChrootMountString }}"
                - "{{ ComposeOSpkgString }}"
                - "{{ ComposeAWSutilsString }}"
                - "{{ PostBuildString }}"
                - Umount.sh -c "{{ AMIGENCHROOT }}"
            environment:
                AMIGENCHROOT: "{{ AMIGENCHROOT }}"
                AMIGENFSTYPE: "{{ AMIGENFSTYPE }}"
                AMIGENSTORLAY: "{{ AMIGENSTORLAY }}"
                AMIGENBUILDDEV: "{{ AMIGENBUILDDEV }}"
                AMIGENVGNAME: "{{ AMIGENVGNAME }}"
                AMIGENROOTNM: "{{ AMIGENROOTNM }}"
                ENABLEDREPOS: "{{ ENABLEDREPOS }}"
                EXTRARPMS: "{{ EXTRARPMS }}"
                AMIGENMANFST: "{{ AMIGENMANFST }}"
                AMIGENPKGGRP: "{{ AMIGENPKGGRP }}"
                CLOUDPROVIDER: "{{ CLOUDPROVIDER }}"
                HTTP_PROXY: "{{ HTTP_PROXY }}"
                GRUBTMOUT: "{{ GRUBTMOUT }}"
                AMIGENTIMEZONE: "{{ AMIGENTIMEZONE }}"
                AWSCLIV1SOURCE: "{{ AWSCLIV1SOURCE }}"
                AWSCLIV2SOURCE: "{{ AWSCLIV2SOURCE }}"
                AWSCFNBOOTSTRAP: "{{ AWSCFNBOOTSTRAP }}"
                AMIGENSSMAGENT: "{{ AMIGENSSMAGENT }}"
                AMIGENICNCTURL: "{{ AMIGENICNCTURL }}"
            ignore_errors: yes

        - name: Save the release info to the manifest
            ansible.builtin.command: grep "PRETTY_NAME=" "{{ AMIGENCHROOT }}/etc/os-release"
            register: release_info

        - name: Write release info to manifest
            ansible.builtin.copy:
                content: "{{ release_info.stdout }}"
                dest: /tmp/manifest.txt

        - name: Save the aws-cli-v1 version to the manifest
            ansible.builtin.command: chroot "{{ AMIGENCHROOT }}" /usr/local/bin/aws1 --version
            when: CLOUDPROVIDER == 'aws' and AWSCLIV1SOURCE is defined
            register: aws_cli_v1_version

        - name: Append aws-cli-v1 version to manifest
            ansible.builtin.copy:
                content: "{{ aws_cli_v1_version.stdout }}"
                dest: /tmp/manifest.txt
                remote_src: yes
            when: aws_cli_v1_version is defined

        - name: Save the aws-cli-v2 version to the manifest
            ansible.builtin.command: chroot "{{ AMIGENCHROOT }}" /usr/local/bin/aws2 --version
            when: CLOUDPROVIDER == 'aws' and AWSCLIV2SOURCE is defined
            register: aws_cli_v2_version

        - name: Append aws-cli-v2 version to manifest
            ansible.builtin.copy:
                content: "{{ aws_cli_v2_version.stdout }}"
                dest: /tmp/manifest.txt
                remote_src: yes
            when: aws_cli_v2_version is defined

        - name: Save the cfn bootstrap version to the manifest
            ansible.builtin.command: chroot "{{ AMIGENCHROOT }}" python3 -m pip list | grep aws-cfn-bootstrap
            when: CLOUDPROVIDER == 'aws' and AWSCFNBOOTSTRAP is defined
            register: cfn_bootstrap_version

        - name: Append cfn bootstrap version to manifest
            ansible.builtin.copy:
                content: "{{ cfn_bootstrap_version.stdout }}"
                dest: /tmp/manifest.txt
                remote_src: yes
            when: cfn_bootstrap_version is defined

        - name: Save the waagent version to the manifest
            ansible.builtin.command: chroot "{{ AMIGENCHROOT }}" /usr/sbin/waagent --version
            when: CLOUDPROVIDER == 'azure'
            register: waagent_version

        - name: Append waagent version to manifest
            ansible.builtin.copy:
                content: "{{ waagent_version.stdout }}"
                dest: /tmp/manifest.txt
                remote_src: yes
            when: waagent_version is defined

        - name: Save the RPM manifest
            ansible.builtin.command: rpm --root "{{ AMIGENCHROOT }}" -qa | sort -u
            register: rpm_manifest

        - name: Append RPM manifest to file
            ansible.builtin.copy:
                content: "{{ rpm_manifest.stdout }}"
                dest: /tmp/manifest.txt
                remote_src: yes

    handlers:
        - name: Restart networkd/resolved
            ansible.builtin.systemd:
                name: "{{ item }}"
                state: restarted
            loop:
                - systemd-networkd
                - systemd-resolved
