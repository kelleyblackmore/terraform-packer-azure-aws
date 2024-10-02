---
- name: Base setup for RHEL
    hosts: all
    become: yes
    tasks:
        - name: Get major version
            command: rpm -qa --queryformat '%{VERSION}\n' '(redhat|sl|slf|centos|oraclelinux)-release(|-server|-workstation|-client|-computenode)'
            register: el_version

        - name: Install EPEL repo
            yum:
                name: "https://dl.fedoraproject.org/pub/epel/epel-release-latest-{{ el_version.stdout }}.noarch.rpm"
                state: present

        - name: Clean all yum cache
            command: yum clean all

        - name: Update all packages
            command: bash /tmp/retry.sh 5 yum -y update

        - name: Install common dependencies
            command: bash /tmp/retry.sh 5 yum -y install virt-what unzip

        - name: Install python3
            yum:
                name: python36
                state: present

        - name: Disable DNS resolution in sshd
            lineinfile:
                path: /etc/ssh/sshd_config
                regexp: '^UseDNS'
                line: 'UseDNS no'
                state: present
                create: yes
            notify: Restart sshd

    handlers:
        - name: Restart sshd
            service:
                name: sshd
                state: restarted
