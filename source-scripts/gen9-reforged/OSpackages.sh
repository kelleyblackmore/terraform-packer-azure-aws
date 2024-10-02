---
- name: Install primary OS packages into chroot-env
  hosts: localhost
  become: yes
  vars:
    chrootmnt: "{{ chroot | default('/mnt/ec2-root') }}"
    debug: "{{ debug | default('UNDEF') }}"
    grubpkgs_arm:
      - grub2-efi-aa64
      - grub2-efi-aa64-modules
      - grub2-tools
      - grub2-tools-extra
      - grub2-tools-minimal
      - shim-aa64
      - shim-unsigned-aarch64
    grubpkgs_x86:
      - grub2-efi-x64
      - grub2-efi-x64-modules
      - grub2-pc-modules
      - grub2-tools
      - grub2-tools-efi
      - grub2-tools-minimal
      - shim-x64
    minxtrapkgs:
      - chrony
      - cloud-init
      - cloud-utils-growpart
      - dhcp-client
      - dracut-config-generic
      - efibootmgr
      - firewalld
      - gdisk
      - grubby
      - kernel
      - kexec-tools
      - libnsl
      - lvm2
      - python3-pip
      - rng-tools
      - unzip
    excludepkgs:
      - alsa-firmware
      - alsa-tools-firmware
      - biosdevname
      - insights-client
      - iprutils
      - iwl100-firmware
      - iwl1000-firmware
      - iwl105-firmware
      - iwl135-firmware
      - iwl2000-firmware
      - iwl2030-firmware
      - iwl3160-firmware
      - iwl5000-firmware
      - iwl5150-firmware
      - iwl6000g2a-firmware
      - iwl6050-firmware
      - iwl7260-firmware
      - rhc
    rpmfile: "{{ rpmfile | default('UNDEF') }}"
    rpmgrp: "{{ rpmgrp | default('core') }}"
    osrepos: "{{ osrepos | default('') }}"
    extrarpms: "{{ extrarpms | default([]) }}"
    extraexclude: "{{ extraexclude | default([]) }}"
    iscrossdistro: "{{ iscrossdistro | default('') }}"
    dnf_array: "{{ dnf_array | default([]) }}"
    reporpms: "{{ reporpms | default('') }}"

  tasks:
    - name: Ensure appropriate SEL mode is set
      include_role:
        name: no_sel

    - name: Get default repos
      command: rpm -qf /etc/os-release --qf '%{name}'
      register: os_release

    - name: Set default repos based on OS
      set_fact:
        baserepos: >
          {% if os_release.stdout == 'almalinux-release' %}
          appstream,baseos,extras
          {% elif os_release.stdout == 'centos-stream-release' %}
          appstream,baseos,extras-common
          {% elif os_release.stdout == 'oraclelinux-release' %}
          ol9_UEKR7,ol9_appstream,ol9_baseos_latest
          {% elif os_release.stdout in ['redhat-release-server', 'redhat-release'] %}
          rhel-9-appstream-rhui-rpms,rhel-9-baseos-rhui-rpms,rhui-client-config-server-9
          {% elif os_release.stdout == 'rocky-release' %}
          appstream,baseos,extras
          {% else %}
          Unknown OS
          {% endif %}

    - name: Fail if OS is unknown
      fail:
        msg: "Unknown OS. Aborting"
      when: baserepos == "Unknown OS"

    - name: Set OS repos if not provided
      set_fact:
        osrepos: "{{ baserepos }}"
      when: osrepos == ''

    - name: Ensure DNS lookups work in chroot-dev
      copy:
        src: /etc/resolv.conf
        dest: "{{ chrootmnt }}/etc/resolv.conf"
        owner: root
        group: root
        mode: '0644'
      when: not ansible_facts['os_family'] == 'Debian'

    - name: Ensure etc/rc.d/init.d exists in chroot-dev
      file:
        path: "{{ chrootmnt }}/etc/rc.d/init.d"
        state: directory
        owner: root
        group: root
        mode: '0755'

    - name: Ensure etc/init.d exists in chroot-dev
      file:
        src: ./rc.d/init.d
        dest: "{{ chrootmnt }}/etc/init.d"
        state: link

    - name: Satisfy weird, OL8-dependency
      copy:
        content: "{{ item.value }}"
        dest: "{{ chrootmnt }}/etc/dnf/vars/{{ item.key }}"
        owner: root
        group: root
        mode: '0644'
      loop: "{{ dnf_array | dict2items }}"
      when: dnf_array | length > 0

    - name: Clean out stale RPMs
      file:
        path: /tmp/*.rpm
        state: absent

    - name: Stage base RPMs
      command: >
        dnf download --disablerepo="*" --enablerepo="{{ osrepos }}" -y --destdir /tmp yum-utils
      when: osrepos != ''

    - name: Initialize RPM db in chroot-dev
      command: rpm --root "{{ chrootmnt }}" --initdb

    - name: Install staged RPMs
      command: rpm --force --root "{{ chrootmnt }}" -ivh --nodeps --nopre /tmp/*.rpm

    - name: Install base RPM's dependencies
      command: yum --disablerepo="*" --enablerepo="{{ osrepos }}" --installroot="{{ chrootmnt }}" -y reinstall yum-utils

    - name: Ensure yum-utils are installed in chroot-dev
      command: yum --disablerepo="*" --enablerepo="{{ osrepos }}" --installroot="{{ chrootmnt }}" -y install yum-utils

    - name: Fetch custom repo-RPMs
      command: >
        {% if item | regex_search('http[s]*://') %}
        curl --connect-timeout 15 -O -sL "{{ item }}"
        {% else %}
        yumdownloader --destdir=/tmp "{{ item }}"
        {% endif %}
      loop: "{{ reporpms.split(',') }}"
      when: reporpms != ''

    - name: Install selected package-set into chroot-dev
      block:
        - name: Expand the "core" RPM group and store as array
          command: yum groupinfo "{{ rpmgrp }}"
          register: groupinfo

        - name: Parse groupinfo for packages
          set_fact:
            includepkgs: "{{ groupinfo.stdout | regex_findall('^[[:space:]]*[-=+[:space:]](.*)$') }}"

        - name: Read manifest file
          slurp:
            src: "{{ rpmfile }}"
          register: manifest
          when: rpmfile != 'UNDEF' and rpmfile | length > 0

        - name: Set includepkgs from manifest file
          set_fact:
            includepkgs: "{{ manifest.content | b64decode | split('\n') }}"
          when: rpmfile != 'UNDEF' and rpmfile | length > 0

        - name: Read manifest from URL
          uri:
            url: "{{ rpmfile }}"
            return_content: yes
          register: manifest_url
          when: rpmfile != 'UNDEF' and rpmfile | regex_search('http([s]{1}|)://')

        - name: Set includepkgs from URL manifest
          set_fact:
            includepkgs: "{{ manifest_url.content | split('\n') }}"
          when: rpmfile != 'UNDEF' and rpmfile | regex_search('http([s]{1}|)://')

        - name: Add extra packages to include-list
          set_fact:
            includepkgs: "{{ includepkgs + minxtrapkgs + extrarpms + (grubpkgs_x86 if ansible_architecture == 'x86_64' else grubpkgs_arm) }}"

        - name: Remove excluded packages from include-list
          set_fact:
            includepkgs: "{{ includepkgs | difference(excludepkgs + extraexclude) }}"

        - name: Install packages
          command: >
            yum --nogpgcheck --installroot="{{ chrootmnt }}" --disablerepo="*" --enablerepo="{{ osrepos }}" install -y {{ includepkgs | join(' ') }}

        - name: Verify installation
          command: chroot "{{ chrootmnt }}" bash -c "rpm -q {{ item }}"
          loop: "{{ includepkgs }}"
          when: item != ''
          failed_when: false
          register: verify_install

        - name: Fail if any package is missing
          fail:
            msg: "Failed finding {{ item.item }}"
          when: item.rc != 0
          loop: "{{ verify_install.results }}"
          loop_control:
            label: "{{ item.item }}"

    - name: Disable any repo that might interfere
      command: chroot "{{ chrootmnt }}" /usr/bin/yum-config-manager --disable "*"

    - name: Enable the requested list of repos
      command: chroot "{{ chrootmnt }}" /usr/bin/yum-config-manager --enable "{{ osrepos }}"
