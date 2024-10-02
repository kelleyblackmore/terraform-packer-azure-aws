#!/bin/bash
# AWSutils.sh

## Overview

`AWSutils.sh` is a script designed to install, configure, and activate various AWS utilities on a system. This script supports the installation of AWS CLI versions 1 and 2, AWS InstanceConnect, AWS SSM Agent, and AWS CFN Bootstrap. It also ensures appropriate SELinux configurations and enables specified systemd services.

## Usage

To use the `AWSutils.sh` script, run it with the appropriate options. Below is a summary of the available options and their descriptions.

### Options

- `-C, --cli-v1 <URL>`: Specify the URL to download AWS CLI version 1. Installs to `/usr/local/bin`.
- `-c, --cli-v2 <URL>`: Specify the URL to download AWS CLI version 2. Installs to `/usr/bin`.
- `-d, --utils-dir <DIR>`: Specify the directory containing installable utility RPMs.
- `-h, --help`: Print the usage message.
- `-i, --instance-connect <URL>`: Specify the URL or RPM to download AWS InstanceConnect.
- `-m, --mountpoint <DIR>`: Specify the mount point for chroot (default: `/mnt/ec2-root`).
- `-n, --cfn-bootstrap <URL>`: Specify the URL to download AWS CFN Bootstrap (Installs tar.gz via Python Pip).
- `-s, --ssm-agent <URL>`: Specify the URL or RPM to download AWS SSM Agent.
- `-t, --systemd-services <SERVICES>`: Specify the systemd services to enable with `systemctl`.

### Example

```sh
./AWSutils.sh -C https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip -c https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip -i https://example.com/aws-instance-connect.rpm -s https://example.com/amazon-ssm-agent.rpm -t "sshd,amazon-ssm-agent"
```

## Functions

### EnsurePy3

Ensures that Python 3 is installed in the chroot environment.

### ExemptFapolicyd

Pre-stages `fapolicyd` exemptions for AWS CLI.

### InstallCLIv1

Installs AWS CLI version 1.x from the specified source.

### InstallCLIv2

Installs AWS CLI version 2.x from the specified source.

### InstallFromDir

Installs AWS utilities from a specified directory.

### InstallInstanceConnect

Installs AWS InstanceConnect from a specified RPM or Git repository.

### InstallSSMagent

Installs AWS SSM Agent from a specified RPM.

### EnableServices

Enables specified systemd services in the resultant AMI.

### InstallCfnBootstrap

Installs AWS CFN Bootstrap from a specified tar.gz file.

### ProfileSetupAwsCli

Sets up environment variables for AWS CLI in `/etc/profile.d/aws_envs.sh`.

## Notes

- Ensure that the script has executable permissions before running it.
- The script requires root privileges to install packages and modify system configurations.

## License

This script is provided under the MIT License. See the LICENSE file for more details.

