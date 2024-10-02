---
- name: Prepare EC2 instance for AMI Create Image task
    hosts: all
    become: yes
    vars:
        AMIGENREPOS: "{{ lookup('env', 'SPEL_AMIGENREPOS') }}"
        AMIGENREPOSRC: "{{ lookup('env', 'SPEL_AMIGENREPOSRC') }}"
        AMIGENSOURCE: "{{ lookup('env', 'SPEL_AMIGEN9SOURCE') | default('https://github.com/plus3it/AMIgen9.git') }}"
        EXTRARPMS: "{{ lookup('env', 'SPEL_EXTRARPMS') }}"
        HTTP_PROXY: "{{ lookup('env', 'SPEL_HTTP_PROXY') }}"
        USEDEFAULTREPOS: "{{ lookup('env', 'SPEL_USEDEFAULTREPOS') | default('true') }}"
        BUILDDEPS: "{{ lookup('env', 'SPEL_BUILDDEPS') | default('lvm2 yum-utils unzip git dosfstools python3-pip') }}"
        ELBUILD: "/tmp/el-build"
        DEBUG: "{{ lookup('env', 'DEBUG') | default('true') }}"
        EPELREPO: "{{ lookup('env', 'EPELREPO') }}"
    tasks:
        - name: Determine builder type and default repos
            set_fact:
                BUILDER: "{{ 'centos-9stream' if ansible_distribution == 'CentOS' else 'rhel-9' if ansible_distribution == 'RedHat' else 'ol-9' if ansible_distribution == 'OracleLinux' else 'unknown' }}"
                DEFAULTREPOS: "{{ ['baseos', 'appstream', 'extras-common'] if BUILDER == 'centos-9stream' else ['rhel-9-appstream-rhui-rpms', 'rhel-9-baseos-rhui-rpms', 'rhui-client-config-server-9'] if BUILDER == 'rhel-9' else ['ol9_UEKR7', 'ol9_appstream', 'ol9_baseos_latest'] if BUILDER == 'ol-9' else [] }}"
            when: ansible_distribution in ['CentOS', 'RedHat', 'OracleLinux']

        - name: Fail if unknown OS
            fail:
                msg: "Unknown OS. Aborting"
            when: BUILDER == 'unknown'

        - name: Enable default repos
            set_fact:
                ENABLEDREPOS: "{{ DEFAULTREPOS | join(',') }}"
            when: USEDEFAULTREPOS == 'true'

        - name: Enable AMIGENREPOS if present
            set_fact:
                ENABLEDREPOS: "{{ ENABLEDREPOS + ',' + AMIGENREPOS if AMIGENREPOS is defined else ENABLEDREPOS }}"
            when: USEDEFAULTREPOS == 'true'

        - name: Set ENABLEDREPOS to AMIGENREPOS exclusively
            set_fact:
                ENABLEDREPOS: "{{ AMIGENREPOS }}"
            when: USEDEFAULTREPOS != 'true'

        - name: Install build-host dependencies
            yum:
                name: "{{ BUILDDEPS.split(' ') }}"
                state: present

        - name: Set Git Config Proxy
            command: git config --global http.proxy "{{ HTTP_PROXY }}"
            when: HTTP_PROXY is defined

        - name: Enable EPEL repo
            yum_repository:
                name: "{{ EPELREPO }}"
                enabled: yes
            when: EPELREPO is defined

        - name: Install custom repo packages in the builder box
            yum:
                name: "{{ item }}"
                state: present
                ignore_errors: yes
            loop: "{{ AMIGENREPOSRC.split(',') }}"
            register: yum_result
            until: yum_result is succeeded
            retries: 5
            delay: 2

        - name: Enable repos in the builder box
            command: yum-config-manager --disable "*" && yum-config-manager --enable "{{ ENABLEDREPOS }}"

        - name: Install specified extra packages in the builder box
            yum:
                name: "{{ item }}"
                state: present
                ignore_errors: yes
            loop: "{{ EXTRARPMS.split(',') }}"
            register: yum_result
            until: yum_result is succeeded
            retries: 5
            delay: 2

        - name: Disable strict host-key checking when doing git-over-ssh
            lineinfile:
                path: "{{ ansible_env.HOME }}/.ssh/config"
                line: |
                    Host {{ AMIGENSOURCE.split('@')[1].split(':')[0] }}
                        Hostname {{ AMIGENSOURCE.split('@')[1].split(':')[0] }}
                        StrictHostKeyChecking off
            when: AMIGENSOURCE is search('@')
