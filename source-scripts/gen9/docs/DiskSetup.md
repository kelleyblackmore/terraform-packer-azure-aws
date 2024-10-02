#!/bin/bash
# DiskSetup.sh Documentation

This document provides an overview and usage instructions for the `DiskSetup.sh` script. The script automates the basic setup of a CHROOT device, including partitioning and filesystem creation.

## Table of Contents

- [DiskSetup.sh Documentation](#disksetupsh-documentation)
  - [Table of Contents](#table-of-contents)
  - [Overview](#overview)
  - [Usage](#usage)
  - [Options](#options)
  - [Functions](#functions)
    - [UsageMsg](#usagemsg)
    - [CarveLVM](#carvelvm)
    - [CarveBare](#carvebare)
    - [CleanChrootDiskPrtTbl](#cleanchrootdiskprttbl)
    - [SetupBootParts](#setupbootparts)
  - [Main Program Flow](#main-program-flow)
  - [Example](#example)

## Overview

The `DiskSetup.sh` script is designed to automate the setup of a CHROOT device. It supports both LVM and non-LVM partitioning methods and includes options for customizing partition sizes, filesystem types, and labels.

## Usage

To run the script, use the following command:

```sh
sudo ./DiskSetup.sh [options]
```

## Options

The script supports the following options:

- `-B, --boot-size`: Boot-partition size (default: 768MiB)
- `-d, --disk`: Base dev-node used for build-device
- `-f, --fstype`: Filesystem-type used for root filesystems (default: xfs)
- `-h, --help`: Print the usage message
- `-l, --label-boot`: Label for /boot filesystem (default: boot_disk)
- `-L, --label-uefi`: Label for /boot/efi filesystem (default: UEFI_DISK)
- `-p, --partition-string`: Comma-delimited string of colon-delimited partition-specs
- `-r, --rootlabel`: Label to apply to root-partition if not using LVM (default: root_disk)
- `-U, --uefi-size`: UEFI-partition size (default: 256MiB)
- `-v, --vgname`: Name assigned to root volume-group (default: VolGroup00)

## Functions

### UsageMsg

Prints a basic usage message and exits the script.

### CarveLVM

Partitions the disk using LVM. It creates LVM physical volumes, volume groups, and logical volumes based on the specified or default partition string.

### CarveBare

Partitions the disk without using LVM. It creates filesystems directly on the partitions.

### CleanChrootDiskPrtTbl

Clears the target disk of existing partitions and other structural data.

### SetupBootParts

Creates filesystems for the /boot and /boot/efi partitions.

## Main Program Flow

1. Parse command-line options.
2. Check if the script is run as root.
3. Determine the partitioning method (LVM or non-LVM).
4. Partition the disk and create filesystems.
5. Set up /boot and /boot/efi partitions.

## Example

To partition a disk with LVM and set the root volume group name to `MyVolGroup`, use the following command:

```sh
sudo ./DiskSetup.sh --disk /dev/sda --vgname MyVolGroup
```

To partition a disk without LVM and set the root partition label to `my_root`, use the following command:

```sh
sudo ./DiskSetup.sh --disk /dev/sda --rootlabel my_root
```

For more detailed usage information, run:

```sh
sudo ./DiskSetup.sh --help
```

