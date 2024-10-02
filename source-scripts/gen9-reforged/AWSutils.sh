---
- name: Install AWS utilities
  hosts: all
  become: yes
  vars:
    chrootmnt: "/mnt/ec2-root"
    cliv1source: "UNDEF"
    cliv2source: "UNDEF"
    iconnectsrc: "UNDEF"
    ssmagent: "UNDEF"
    utilsdir: "UNDEF"
    systemdsvcs: []
    cfnbootstrap: "UNDEF"

  tasks:
    - name: Ensure Python3 is installed
      yum:
        name: python3
        state: present
        installroot: "{{ chrootmnt }}"
      when: cliv1source != "UNDEF" or cliv2source != "UNDEF"

    - name: Ensure fapolicyd exemptions are pre-staged
      block:
        - name: Create fapolicyd rules directory
          file:
            path: "{{ chrootmnt }}/etc/fapolicyd/rules.d"
            state: directory
            owner: root
            group: root
            mode: '0755'

        - name: Create fapolicyd rules file
          copy:
            content: |
              allow perm=any all : dir=/usr/local/aws-cli/v2/ type=application/x-executable trust 1
              allow perm=any all : dir=/usr/local/aws-cli/v2/ type=application/x-sharedlib trust 1
            dest: "{{ chrootmnt }}/etc/fapolicyd/rules.d/30-aws.rules"
            owner: root
            group: root
            mode: '0644'

    - name: Install AWS CLI version 1.x
      block:
        - name: Fetch AWS CLIv1
          get_url:
            url: "{{ cliv1source }}"
            dest: "{{ chrootmnt }}/tmp/awscli-bundle.zip"
          when: cliv1source != "UNDEF" and cliv1source | regex_search('http[s]?://.*zip')

        - name: Unarchive AWS CLIv1
          unarchive:
            src: "{{ chrootmnt }}/tmp/awscli-bundle.zip"
            dest: "{{ chrootmnt }}/tmp"
            remote_src: yes
          when: cliv1source != "UNDEF" and cliv1source | regex_search('http[s]?://.*zip')

        - name: Install AWS CLIv1
          command: chroot {{ chrootmnt }} python3 /tmp/awscli-bundle/install -i /usr/local/aws-cli/v1 -b /usr/local/bin/aws
          when: cliv1source != "UNDEF" and cliv1source | regex_search('http[s]?://.*zip')

        - name: Create AWS CLIv1 symlink
          file:
            src: /usr/local/aws-cli/v1/bin/aws
            dest: "{{ chrootmnt }}/usr/local/bin/aws1"
            state: link
          when: cliv1source != "UNDEF" and cliv1source | regex_search('http[s]?://.*zip')

        - name: Clean up AWS CLIv1 install files
          file:
            path: "{{ chrootmnt }}/tmp/awscli-bundle.zip"
            state: absent
          when: cliv1source != "UNDEF" and cliv1source | regex_search('http[s]?://.*zip')

        - name: Install AWS CLIv1 via pip
          pip:
            name: "{{ cliv1source.split(',')[1] }}"
            chroot: "{{ chrootmnt }}"
          when: cliv1source != "UNDEF" and cliv1source | regex_search('pip,.*')

    - name: Install AWS CLI version 2.x
      block:
        - name: Fetch AWS CLIv2
          get_url:
            url: "{{ cliv2source }}"
            dest: "{{ chrootmnt }}/tmp/awscli-exe.zip"
          when: cliv2source != "UNDEF" and cliv2source | regex_search('http[s]?://.*zip')

        - name: Unarchive AWS CLIv2
          unarchive:
            src: "{{ chrootmnt }}/tmp/awscli-exe.zip"
            dest: "{{ chrootmnt }}/tmp"
            remote_src: yes
          when: cliv2source != "UNDEF" and cliv2source | regex_search('http[s]?://.*zip')

        - name: Install AWS CLIv2
          command: chroot {{ chrootmnt }} /tmp/aws/install --update -i /usr/local/aws-cli -b /usr/local/bin
          when: cliv2source != "UNDEF" and cliv2source | regex_search('http[s]?://.*zip')

        - name: Create AWS CLIv2 symlink
          file:
            src: /usr/local/aws-cli/v2/current/bin/aws
            dest: "{{ chrootmnt }}/usr/local/bin/aws2"
            state: link
          when: cliv2source != "UNDEF" and cliv2source | regex_search('http[s]?://.*zip')

        - name: Clean up AWS CLIv2 install files
          file:
            path: "{{ chrootmnt }}/tmp/awscli-exe.zip"
            state: absent
          when: cliv2source != "UNDEF" and cliv2source | regex_search('http[s]?://.*zip')

    - name: Install AWS SSM-Agent
      block:
        - name: Install AWS SSM-Agent RPM
          yum:
            name: "{{ ssmagent }}"
            state: present
            installroot: "{{ chrootmnt }}"
          when: ssmagent != "UNDEF" and ssmagent | regex_search('.*\.rpm')

        - name: Enable AWS SSM-Agent service
          command: chroot {{ chrootmnt }} systemctl enable amazon-ssm-agent.service
          when: ssmagent != "UNDEF" and ssmagent | regex_search('.*\.rpm')

    - name: Install AWS InstanceConnect
      block:
        - name: Install AWS InstanceConnect RPM
          yum:
            name: "{{ iconnectsrc }}"
            state: present
            installroot: "{{ chrootmnt }}"
          when: iconnectsrc != "UNDEF" and iconnectsrc | regex_search('.*\.rpm')

        - name: Clone InstanceConnect repository
          git:
            repo: "{{ iconnectsrc }}"
            dest: "{{ chrootmnt }}/tmp/aws-ec2-instance-connect-config"
          when: iconnectsrc != "UNDEF" and iconnectsrc | regex_search('.*\.git')

        - name: Build InstanceConnect RPM
          command: make rpm
          args:
            chdir: "{{ chrootmnt }}/tmp/aws-ec2-instance-connect-config"
          when: iconnectsrc != "UNDEF" and iconnectsrc | regex_search('.*\.git')

        - name: Install built InstanceConnect RPM
          yum:
            name: "{{ item }}"
            state: present
            installroot: "{{ chrootmnt }}"
          with_fileglob:
            - "{{ chrootmnt }}/tmp/aws-ec2-instance-connect-config/*noarch.rpm"
          when: iconnectsrc != "UNDEF" and iconnectsrc | regex_search('.*\.git')

        - name: Enable ec2-instance-connect service
          command: chroot {{ chrootmnt }} systemctl enable ec2-instance-connect
          when: iconnectsrc != "UNDEF"

        - name: Create SELinux policy for InstanceConnect
          copy:
            content: |
              module ec2-instance-connect 1.0;

              require {
                type ssh_keygen_exec_t;
                type sshd_t;
                type http_port_t;
                class process setpgid;
                class tcp_socket name_connect;
                class file map;
                class file { execute execute_no_trans open read };
              }

              #============= sshd_t ==============

              allow sshd_t self:process setpgid;
              allow sshd_t ssh_keygen_exec_t:file map;
              allow sshd_t ssh_keygen_exec_t:file { execute execute_no_trans open read };
              allow sshd_t http_port_t:tcp_socket name_connect;
            dest: "{{ chrootmnt }}/tmp/ec2-instance-connect.te"

        - name: Compile and install SELinux policy for InstanceConnect
          command: chroot {{ chrootmnt }} /bin/bash -c "cd /tmp && checkmodule -M -m -o ec2-instance-connect.mod ec2-instance-connect.te && semodule_package -o ec2-instance-connect.pp -m ec2-instance-connect.mod && semodule -i ec2-instance-connect.pp && rm ec2-instance-connect.*"

    - name: Enable systemd services
      command: chroot {{ chrootmnt }} systemctl enable {{ item }}.service
      with_items: "{{ systemdsvcs }}"
      when: systemdsvcs | length > 0

    - name: Install AWS CFN Bootstrap
      block:
        - name: Fetch AWS CFN Bootstrap
          get_url:
            url: "{{ cfnbootstrap }}"
            dest: "{{ chrootmnt }}/tmp/aws-cfn-bootstrap.tar.gz"
          when: cfnbootstrap != "UNDEF" and cfnbootstrap | regex_search('.*\.tar\.gz')

        - name: Install AWS CFN Bootstrap
          command: chroot {{ chrootmnt }} python3 -m pip install /tmp/aws-cfn-bootstrap.tar.gz
          when: cfnbootstrap != "UNDEF" and cfnbootstrap | regex_search('.*\.tar\.gz')

        - name: Set up directory structure for cfn-hup service
          file:
            path: "{{ chrootmnt }}/opt/aws/apitools/cfn-init/init/redhat/"
            state: directory
            mode: '0755'

        - name: Extract cfn-hup service definition file
          unarchive:
            src: "{{ chrootmnt }}/tmp/aws-cfn-bootstrap.tar.gz"
            dest: "{{ chrootmnt }}/opt/aws/apitools/cfn-init/"
            remote_src: yes
            extra_opts: [--wildcards, --no-anchored, --strip-components=1, redhat/cfn-hup]

        - name: Ensure no invalid file-ownership on binary
          file:
            path: "{{ chrootmnt }}/opt/aws/apitools/cfn-init/init/redhat/cfn-hup"
            owner: root
            group: root

        - name: Create symlink for cfn-hup service
          file:
            src: /opt/aws/apitools/cfn-init/init/redhat/cfn-hup
            dest: "{{ chrootmnt }}/etc/init.d/cfn-hup"
            state: link

        - name: Make sure cfn-hup service is executable
          file:
            path: "{{ chrootmnt }}/opt/aws/apitools/cfn-init/init/redhat/cfn-hup"
            mode: '0755'

        - name: Configure cfn-hup symlink and initscript
          command: chroot {{ chrootmnt }} alternatives --verbose --install /opt/aws/bin/cfn-hup cfn-hup /usr/local/bin/cfn-hup 1 --initscript cfn-hup

        - name: Clean up install files
          file:
            path: "{{ chrootmnt }}/tmp/aws-cfn-bootstrap.tar.gz"
            state: absent
          when: cfnbootstrap != "UNDEF" and cfnbootstrap | regex_search('.*\.tar\.gz')

    - name: Set up /etc/profile.d file for AWS CLI
      copy:
        content: |
          # Point AWS utils/libs to the OS CA-trust bundle
          AWS_CA_BUNDLE=/etc/pki/tls/certs/ca-bundle.crt
          REQUESTS_CA_BUNDLE="${AWS_CA_BUNDLE}"

          # Try to snarf an IMDSv2 token
          IMDS_TOKEN="$(
            curl -sk \
              -X PUT "http://169.254.169.254/latest/api/token" \
              -H "X-aws-ec2-metadata-token-ttl-seconds: 21600"
          )"

          # Use token if available
          if [[ -n ${IMDS_TOKEN} ]]
          then
            AWS_DEFAULT_REGION="$(
              curl -sk \
                -H "X-aws-ec2-metadata-token: ${IMDS_TOKEN}" \
                  http://169.254.169.254/latest/meta-data/placement/region
            )"
          else
            AWS_DEFAULT_REGION="$(
              curl -sk http://169.254.169.254/latest/meta-data/placement/region
            )"
          fi

          # Export AWS region if non-null
          if [[ -n ${AWS_DEFAULT_REGION} ]]
          then
            export AWS_DEFAULT_REGION AWS_CA_BUNDLE REQUESTS_CA_BUNDLE
          else
            echo "Failed setting AWS-supporting shell-envs"
          fi
        dest: "{{ chrootmnt }}/etc/profile.d/aws_envs.sh"
        owner: root
        group: root
        mode: '0644'
