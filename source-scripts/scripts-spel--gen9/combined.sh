scripts from spel 
amigen9-build.sh
base.sh
builder-prep-9.sh
cleanup.sh
dep.sh
free-root.sh
pivot-root.sh
retry.sh
zerodisk.sh


gen9
AWSutils.sh
DiskSetup.sh
DualMode-GRUBsetup.sh
MkChrootTree.sh
OSpackages.sh
PostBuild.sh
README.md
Umount.sh
XdistroSetup.sh
err_exit.bashlib
no_sel.bashlib

# --- Start of amigen9-build.sh ---
#!/bin/bash
# shellcheck disable=SC2034,SC2046
#
# Execute AMIGen9 scripts to prepare an EC2 instance for the AMI Create Image
# task.
#
##############################################################################
PROGNAME="$(basename "$0")"
AMIGENBOOTSIZE="${SPEL_AMIGENBOOTDEVSZ:-768}"
AMIGENBOOTLABL="${SPEL_AMIGENBOOTDEVLBL:-boot_disk}"
AMIGENBRANCH="${SPEL_AMIGENBRANCH:-main}"
AMIGENCHROOT="${SPEL_AMIGENCHROOT:-/mnt/ec2-root}"
AMIGENFSTYPE="${SPEL_AMIGENFSTYPE:-xfs}"
#AMIGENICNCTURL="${SPEL_AMIGENICNCTURL}"
AMIGENMANFST="${SPEL_AMIGENMANFST}"
AMIGENPKGGRP="${SPEL_AMIGENPKGGRP:-core}"
AMIGENREPOS="${SPEL_AMIGENREPOS}"
AMIGENREPOSRC="${SPEL_AMIGENREPOSRC}"
AMIGENROOTNM="${SPEL_AMIGENROOTNM}"
AMIGENSOURCE="${SPEL_AMIGEN9SOURCE:-https://github.com/plus3it/AMIgen9.git}"
#AMIGENSSMAGENT="${SPEL_AMIGENSSMAGENT}"
AMIGENSTORLAY="${SPEL_AMIGENSTORLAY}"
AMIGENTIMEZONE="${SPEL_TIMEZONE:-UTC}"
AMIGENUEFISIZE="${SPEL_AMIGENUEFIDEVSZ:-128}"
AMIGENUEFILABL="${SPEL_AMIGENUEFIDEVLBL:-UEFI_DISK}"
AMIGENVGNAME="${SPEL_AMIGENVGNAME}"
#AWSCFNBOOTSTRAP="${SPEL_AWSCFNBOOTSTRAP}"
#AWSCLIV1SOURCE="${SPEL_AWSCLIV1SOURCE}"
#AWSCLIV2SOURCE="${SPEL_AWSCLIV2SOURCE:-https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip}"
CLOUDPROVIDER="${SPEL_CLOUDPROVIDER:-aws}"
EXTRARPMS="${SPEL_EXTRARPMS}"
FIPSDISABLE="${SPEL_FIPSDISABLE}"
GRUBTMOUT="${SPEL_GRUBTMOUT:-5}"
HTTP_PROXY="${SPEL_HTTP_PROXY}"
USEDEFAULTREPOS="${SPEL_USEDEFAULTREPOS:-true}"
USEROOTDEVICE="${SPEL_USEROOTDEVICE:-true}"


ELBUILD="/tmp/el-build"

# Make interactive-execution more-verbose unless explicitly told not to
if [[ $( tty -s ) -eq 0 ]] && [[ -z ${DEBUG:-} ]]
then
    DEBUG="true"
fi


# Error handler function
function err_exit {
    local ERRSTR
    local ISNUM
    local SCRIPTEXIT

    ERRSTR="${1}"
    ISNUM='^[0-9]+$'
    SCRIPTEXIT="${2:-1}"

    if [[ ${DEBUG} == true ]]
    then
        # Our output channels
        logger -i -t "${PROGNAME}" -p kern.crit -s -- "${ERRSTR}"
    else
        logger -i -t "${PROGNAME}" -p kern.crit -- "${ERRSTR}"
    fi

    # Only exit if requested exit is numerical
    if [[ ${SCRIPTEXIT} =~ ${ISNUM} ]]
    then
        exit "${SCRIPTEXIT}"
    fi
}

# Setup per-builder values
case $( rpm -qf /etc/os-release --qf '%{name}' ) in
    centos-linux-release | centos-stream-release )
        BUILDER=centos-9stream

        DEFAULTREPOS=(
            baseos
            appstream
            extras-common
        )
        ;;
    redhat-release-server|redhat-release)
        BUILDER=rhel-9

        DEFAULTREPOS=(
            rhel-9-appstream-rhui-rpms
            rhel-9-baseos-rhui-rpms
            rhui-client-config-server-9
        )
        ;;
    oraclelinux-release)
        BUILDER=ol-9

        DEFAULTREPOS=(
            ol9_UEKR7
            ol9_appstream
            ol9_baseos_latest
        )
        ;;
    *)
        echo "Unknown OS. Aborting" >&2
        exit 1
        ;;
esac
DEFAULTREPOS+=()

# Default to enabling default repos
ENABLEDREPOS=$(IFS=,; echo "${DEFAULTREPOS[*]}")

if [[ "$USEDEFAULTREPOS" != "true" ]]
then
    # Enable AMIGENREPOS exclusively when instructed not to use default repos
    ENABLEDREPOS="${AMIGENREPOS}"
elif [[ -n "${AMIGENREPOS:-}" ]]
then
    # When using default repos, also enable AMIGENREPOS if present
    ENABLEDREPOS+=,"${AMIGENREPOS}"
fi

export FIPSDISABLE


retry()
{
    # Make an arbitrary number of attempts to execute an arbitrary command,
    # passing it arbitrary parameters. Convenient for working around
    # intermittent errors (which occur often with poor repo mirrors).
    #
    # Returns the exit code of the command.
    local n=0
    local try=$1
    local cmd="${*: 2}"
    local result=1
    [[ $# -le 1 ]] && {
        echo "Usage $0 <number_of_retry_attempts> <Command>"
        exit $result
    }

    echo "Will try $try time(s) :: $cmd"

    if [[ "${SHELLOPTS}" == *":errexit:"* ]]
    then
        set +e
        local ERREXIT=1
    fi

    until [[ $n -ge $try ]]
    do
        sleep $n
        $cmd
        result=$?
        if [[ $result -eq 0 ]]
        then
            break
        else
            ((n++))
            echo "Attempt $n, command failed :: $cmd"
        fi
    done

    if [[ "${ERREXIT}" == "1" ]]
    then
        set -e
    fi

    return $result
}  # ----------  end of function retry  ----------

# Run the builder-scripts
function BuildChroot {
    local STATUS_MSG

    # Prepare the build device
    PrepBuildDevice

    # Invoke disk-partitioner
    bash -euxo pipefail "${ELBUILD}"/$( ComposeDiskSetupString ) || \
        err_exit "Failure encountered with DiskSetup.sh"

    # Invoke chroot-env disk-mounter
    bash -euxo pipefail "${ELBUILD}"/$( ComposeChrootMountString ) || \
        err_exit "Failure encountered with MkChrootTree.sh"

    # Invoke OS software installer
    bash -euxo pipefail "${ELBUILD}"/$( ComposeOSpkgString ) || \
        err_exit "Failure encountered with OSpackages.sh"

    # Invoke CSP-specific utilities scripts
    case "${CLOUDPROVIDER}" in
        # Invoke AWSutils installer
        aws)
            bash -euxo pipefail "${ELBUILD}"/$( ComposeAWSutilsString ) || \
                err_exit "Failure encountered with AWSutils.sh"
            ;;
        azure)
            (
                export HTTP_PROXY
                bash -euxo pipefail "${ELBUILD}/AzureUtils.sh" || \
                    err_exit "Failure encountered with AzureUtils.sh"
            )
            ;;
        *)
            # Concat exit-message string
            STATUS_MSG="Unsupported value [${CLOUDPROVIDER}] for CLOUDPROVIDER."
            STATUS_MSG="${STATUS_MSG} No provider-specific utilities"
            STATUS_MSG="${STATUS_MSG} will be installed"

            # Log but do not fail-out
            err_exit "${STATUS_MSG}" NONE
            ;;
    esac

    # Post-installation configurator
    bash -euxo pipefail "${ELBUILD}"/$( PostBuildString ) || \
        err_exit "Failure encountered with PostBuild.sh"

    # Collect insallation-manifest
    CollectManifest

    # Invoke unmounter
    bash -euxo pipefail "${ELBUILD}"/Umount.sh -c "${AMIGENCHROOT}" || \
        err_exit "Failure encountered with Umount.sh"
}

# Create a record of the build
function CollectManifest {
    echo "Saving the release info to the manifest"
    grep "PRETTY_NAME=" "${AMIGENCHROOT}/etc/os-release" | \
        cut --delimiter '"' -f2 > /tmp/manifest.txt

    if [[ "${CLOUDPROVIDER}" == "aws" ]]
    then
        if [[ -n "$AWSCLIV1SOURCE" ]]
        then
            echo "Saving the aws-cli-v1 version to the manifest"
            [[ -o xtrace ]] && XTRACE='set -x' || XTRACE='set +x'
            set +x
            (chroot "${AMIGENCHROOT}" /usr/local/bin/aws1 --version) 2>&1 | \
                tee -a /tmp/manifest.txt
            eval "$XTRACE"
        fi
        if [[ -n "$AWSCLIV2SOURCE" ]]
        then
            echo "Saving the aws-cli-v2 version to the manifest"
            [[ -o xtrace ]] && XTRACE='set -x' || XTRACE='set +x'
            set +x
            (chroot "${AMIGENCHROOT}" /usr/local/bin/aws2 --version) 2>&1 | \
                tee -a /tmp/manifest.txt
            eval "$XTRACE"
        fi
        if [[ -n "$AWSCFNBOOTSTRAP" ]]
        then
            echo "Saving the cfn bootstrap version to the manifest"
            [[ -o xtrace ]] && XTRACE='set -x' || XTRACE='set +x'
            set +x
            (chroot "${AMIGENCHROOT}" python3 -m pip list) | \
                grep aws-cfn-bootstrap | tee -a /tmp/manifest.txt
            eval "$XTRACE"
        fi
    elif [[ "${CLOUDPROVIDER}" == "azure" ]]
    then
        echo "Saving the waagent version to the manifest"
        [[ -o xtrace ]] && XTRACE='set -x' || XTRACE='set +x'
        set +x
        (chroot "${AMIGENCHROOT}" /usr/sbin/waagent --version) 2>&1 | \
            tee -a /tmp/manifest.txt
        eval "$XTRACE"
    fi

    echo "Saving the RPM manifest"
    rpm --root "${AMIGENCHROOT}" -qa | sort -u >> /tmp/manifest.txt
}

# Pick options for the AWSutils install command
function ComposeAWSutilsString {
    local AWSUTILSSTRING

    AWSUTILSSTRING="AWSutils.sh "

    # Set services to enable
    #AWSUTILSSTRING+="-t amazon-ssm-agent "

    # Set location for chroot-env
    if [[ ${AMIGENCHROOT} == "/mnt/ec2-root" ]]
    then
        err_exit "Using default chroot-env location [${AMIGENCHROOT}]" NONE
    else
        AWSUTILSSTRING+="-m ${AMIGENCHROOT} "
    fi

    # Whether to install AWS CLIv1
    if [[ -n "${AWSCLIV1SOURCE}" ]]
    then
        AWSUTILSSTRING+="-C ${AWSCLIV1SOURCE} "
    fi

    # Whether to install AWS CLIv2
    if [[ -n "${AWSCLIV2SOURCE}" ]]
    then
        AWSUTILSSTRING+="-c ${AWSCLIV2SOURCE} "
    fi

    # Whether to install AWS SSM-agent
    if [[ -z ${AMIGENSSMAGENT:-} ]]
    then
        err_exit "Skipping install of AWS SSM-agent" NONE
    else
        AWSUTILSSTRING+="-s ${AMIGENSSMAGENT} "
    fi

    # Whether to install AWS InstanceConnect
    if [[ -z ${AMIGENICNCTURL:-} ]]
    then
        err_exit "Skipping install of AWS SSM-agent" NONE
    else
        AWSUTILSSTRING+="-i ${AMIGENICNCTURL} "
    fi

    # Whether to install cfnbootstrap
    if [[ -z "${AWSCFNBOOTSTRAP:-}" ]]
    then
        err_exit "Skipping install of AWS CFN Bootstrap" NONE
    else
        AWSUTILSSTRING+="-n ${AWSCFNBOOTSTRAP} "
    fi

    # Return command-string for AWSutils-script
    echo "${AWSUTILSSTRING}"
}

# Pick options for chroot-mount command
function ComposeChrootMountString {
    local MOUNTCHROOTCMD

    MOUNTCHROOTCMD="MkChrootTree.sh "

    # Set location for chroot-env
    if [[ ${AMIGENCHROOT} == "/mnt/ec2-root" ]]
    then
        err_exit "Using default chroot-env location [${AMIGENCHROOT}]" NONE
    else
        MOUNTCHROOTCMD+="-m ${AMIGENCHROOT} "
    fi

    # Set the filesystem-type to use for OS filesystems
    if [[ ${AMIGENFSTYPE} == "xfs" ]]
    then
        err_exit "Using default fstype [xfs] for boot filesysems" NONE
    else
        MOUNTCHROOTCMD+="-f ${AMIGENFSTYPE} "
    fi

    # Set requested custom storage layout as necessary
    if [[ -z ${AMIGENSTORLAY:-} ]]
    then
        err_exit "Using script-default for boot-volume layout" NONE
    else
        MOUNTCHROOTCMD+="-p ${AMIGENSTORLAY} "
    fi

    # Set device to mount
    if [[ -z ${AMIGENBUILDDEV:-} ]]
    then
        err_exit "Failed to define device to partition"
    else
        MOUNTCHROOTCMD+="-d ${AMIGENBUILDDEV}"
    fi

    # Return command-string for mount-script
    echo "${MOUNTCHROOTCMD}"
}

## # Pick options for disk-setup command
function ComposeDiskSetupString {
    local DISKSETUPCMD

    DISKSETUPCMD="DiskSetup.sh "

    # Set the size for the /boot partition
    if [[ -z ${AMIGENBOOTSIZE:-} ]]
    then
        err_exit "Setting /boot size to 512MiB" NONE
        DISKSETUPCMD+="-B 512 "
    else
        DISKSETUPCMD+="-B ${AMIGENBOOTSIZE} "
    fi

    # Set the value of the fs-label for the /boot partition
    if [[ -z ${AMIGENBOOTLABL:-} ]]
    then
        err_exit "Setting /boot fs-label to 'boot_disk'." NONE
        DISKSETUPCMD+="-l boot_disk "
    else
        DISKSETUPCMD+="-l ${AMIGENBOOTLABL} "
    fi

    # Set the size for the /boot/efi partition
    if [[ -z ${AMIGENUEFISIZE:-} ]]
    then
        err_exit "Setting /boot/efi size to 256MiB" NONE
        DISKSETUPCMD+="-U 256 "
    else
        DISKSETUPCMD+="-U ${AMIGENUEFISIZE} "
    fi

    # Set the value of the fs-label for the /boot partition
    if [[ -z ${AMIGENUEFILABL:-} ]]
    then
        err_exit "Setting /boot/efi fs-label to 'UEFI_DISK'." NONE
        DISKSETUPCMD+="-L UEFI_DISK "
    else
        DISKSETUPCMD+="-L ${AMIGENUEFILABL} "
    fi

    # Set the filesystem-type to use for OS filesystems
    if [[ ${AMIGENFSTYPE} == "xfs" ]]
    then
        err_exit "Using default fstype [xfs] for boot filesysems" NONE
    fi
    DISKSETUPCMD+="-f ${AMIGENFSTYPE} "

    # Set requested custom storage layout as necessary
    if [[ -z ${AMIGENSTORLAY:-} ]]
    then
        err_exit "Using script-default for boot-volume layout" NONE
    else
        DISKSETUPCMD+="-p ${AMIGENSTORLAY} "
    fi

    # Set LVM2 or bare disk-formatting
    if [[ -n ${AMIGENVGNAME:-} ]]
    then
        DISKSETUPCMD+="-v ${AMIGENVGNAME} "
    elif [[ -n ${AMIGENROOTNM:-} ]]
    then
        DISKSETUPCMD+="-r ${AMIGENROOTNM} "
    fi

    # Set device to carve
    if [[ -z ${AMIGENBUILDDEV:-} ]]
    then
        err_exit "Failed to define device to partition"
    else
        DISKSETUPCMD+="-d ${AMIGENBUILDDEV}"
    fi

    # Return command-string for disk-setup script
    echo "${DISKSETUPCMD}"
}

# Pick options for the OS-install command
function ComposeOSpkgString {
    local OSPACKAGESTRING

    OSPACKAGESTRING="OSpackages.sh "

    # Set location for chroot-env
    if [[ ${AMIGENCHROOT} == "/mnt/ec2-root" ]]
    then
        err_exit "Using default chroot-env location [${AMIGENCHROOT}]" NONE
    else
        OSPACKAGESTRING+="-m ${AMIGENCHROOT} "
    fi

    # Pick custom yum repos
    if [[ -z ${ENABLEDREPOS:-} ]]
    then
        err_exit "Using script-default yum repos" NONE
    else
        OSPACKAGESTRING+="-a ${ENABLEDREPOS} "
    fi

    # Custom repo-def RPMs to install
    if [[ -z ${AMIGENREPOSRC:-} ]]
    then
        err_exit "Installing no custom repo-config RPMs" NONE
    else
        OSPACKAGESTRING+="-r ${AMIGENREPOSRC} "
    fi

    # Add custom manifest file
    if [[ -z ${AMIGENMANFST:-} ]]
    then
        err_exit "Installing no custom manifest" NONE
    else
        OSPACKAGESTRING+="-M ${AMIGENREPOSRC} "
    fi

    # Add custom pkg group
    if [[ -z ${AMIGENPKGGRP:-} ]]
    then
        err_exit "Installing no custom package group" NONE
    else
        OSPACKAGESTRING+="-g ${AMIGENPKGGRP} "
    fi

    # Add extra rpms
    if [[ -z ${EXTRARPMS:-} ]]
    then
        err_exit "Installing no extra rpms" NONE
    else
        OSPACKAGESTRING+="-e ${EXTRARPMS} "
    fi

    # Customization for Oracle Linux
    if [[ $BUILDER == "ol-9" ]]
    then
        # Exclude Unbreakable Enterprise Kernel
        OSPACKAGESTRING+="-x kernel-uek,redhat*,*rhn*,*spacewalk*,*ulninfo* "

        # DNF hack
        OSPACKAGESTRING+="--setup-dnf ociregion=,ocidomain=oracle.com "
    fi

    # Return command-string for OS-script
    echo "${OSPACKAGESTRING}"
}

function PostBuildString {
    local POSTBUILDCMD

    POSTBUILDCMD="PostBuild.sh "

    # Set the filesystem-type to use for OS filesystems
    if [[ ${AMIGENFSTYPE} == "xfs" ]]
    then
        err_exit "Using default fstype [xfs] for boot filesysems" NONE
    fi
    POSTBUILDCMD+="-f ${AMIGENFSTYPE} "

    # Set location for chroot-env
    if [[ ${AMIGENCHROOT} == "/mnt/ec2-root" ]]
    then
        err_exit "Using default chroot-env location [${AMIGENCHROOT}]" NONE
    else
        POSTBUILDCMD+="-m ${AMIGENCHROOT} "
    fi

    # Set AMI starting time-zone
    if [[ ${AMIGENTIMEZONE} == "UTC" ]]
    then
        err_exit "Using default AMI timezone [${AMIGENCHROOT}]" NONE
    else
        POSTBUILDCMD+="-z ${AMIGENTIMEZONE} "
    fi

    # Set image GRUB_TIMEOUT value
    POSTBUILDCMD+="--grub-timeout ${GRUBTMOUT}"

    # Return command-string for OS-script
    echo "${POSTBUILDCMD}"
}

function PrepBuildDevice {
    local ROOT_DEV
    local ROOT_DISK
    local DISKS

    # Select the disk to use for the build
    err_exit "Detecting the root device..." NONE
    ROOT_DEV="$( grep ' / ' /proc/mounts | cut -d " " -f 1 )"
    if [[ ${ROOT_DEV} == /dev/nvme* ]]
    then
      ROOT_DISK="${ROOT_DEV//p*/}"
      IFS=" " read -r -a DISKS <<< "$(echo /dev/nvme*n1)"
    else
      err_exit "ERROR: This script supports nvme device naming. Could not determine root disk from device name: ${ROOT_DEV}"
    fi

    if [[ "$USEROOTDEVICE" = "true" ]]
    then
      AMIGENBUILDDEV="${ROOT_DISK}"
    elif [[ ${#DISKS[@]} -gt 2 ]]
    then
      err_exit "ERROR: This script supports at most 2 attached disks. Detected ${#DISKS[*]} disks"
    else
      AMIGENBUILDDEV="$(echo "${DISKS[@]/$ROOT_DISK}" | tr -d '[:space:]')"
    fi
    err_exit "Using ${AMIGENBUILDDEV} as the build device." NONE

    # Make sure the disk has a GPT label
    err_exit "Checking ${AMIGENBUILDDEV} for a GPT label..." NONE
    if ! blkid "$AMIGENBUILDDEV"
    then
        err_exit "No label detected. Creating GPT label on ${AMIGENBUILDDEV}..." NONE
        parted -s "$AMIGENBUILDDEV" -- mklabel gpt
        blkid "$AMIGENBUILDDEV"
        err_exit "Created empty GPT configuration on ${AMIGENBUILDDEV}" NONE
    else
        err_exit "GPT label detected on ${AMIGENBUILDDEV}" NONE
    fi
}

##########################
## Main program section ##
##########################

set -x
set -e
set -o pipefail

echo "Restarting networkd/resolved for DNS resolution"
systemctl restart systemd-networkd systemd-resolved

# Ensure build-tools directory exists
if [[ ! -d ${ELBUILD} ]]
then
    err_exit "Creating build-tools directory [${ELBUILD}]..." NONE
    install -dDm 000755 "${ELBUILD}" || \
        err_exit "Failed creating build-tools directory"
fi

# Pull build-tools from git clone-source
git clone --branch "${AMIGENBRANCH}" "${AMIGENSOURCE}" "${ELBUILD}"

# Execute build-tools
BuildChroot

# --- End of amigen9-build.sh ---

# --- Start of base.sh ---
#!/bin/bash

# Get major version
EL=$(rpm -qa --queryformat '%{VERSION}\n' '(redhat|sl|slf|centos|oraclelinux)-release(|-server|-workstation|-client|-computenode)')

# Setup repos
echo "installing the epel repo"
yum -y install "https://dl.fedoraproject.org/pub/epel/epel-release-latest-${EL}.noarch.rpm" >/dev/null

# Update the box
echo "installing updates"
yum clean all >/dev/null
bash /tmp/retry.sh 5 yum -y update >/dev/null

# Install common deps
echo "installing common dependencies"
bash /tmp/retry.sh 5 yum -y install virt-what unzip >/dev/null

# Install python3 (from epel)
yum -y install python36

# Tweak sshd to prevent DNS resolution (speed up logins)
echo "disabling dns resolution in sshd"
if [[ $(grep -q '^UseDNS' /etc/ssh/sshd_config)$? -eq 0 ]]
then
    sed -i -e 's/^UseDNS.*/UseDNS no/' /etc/ssh/sshd_config
else
    sed -i "$ a\UseDNS no" /etc/ssh/sshd_config
fi

# --- End of base.sh ---

# --- Start of builder-prep-9.sh ---
#!/bin/bash
# shellcheck disable=SC2034,SC2046
#
# Execute AMIGen9 scripts to prepare an EC2 instance for the AMI Create Image
# task.
#
##############################################################################
PROGNAME="$(basename "$0")"
AMIGENREPOS="${SPEL_AMIGENREPOS}"
AMIGENREPOSRC="${SPEL_AMIGENREPOSRC}"
AMIGENSOURCE="${SPEL_AMIGEN9SOURCE:-https://github.com/plus3it/AMIgen9.git}"
EXTRARPMS="${SPEL_EXTRARPMS}"
HTTP_PROXY="${SPEL_HTTP_PROXY}"
USEDEFAULTREPOS="${SPEL_USEDEFAULTREPOS:-true}"


read -r -a BUILDDEPS <<< "${SPEL_BUILDDEPS:-lvm2 yum-utils unzip git dosfstools python3-pip}"

ELBUILD="/tmp/el-build"

# Make interactive-execution more-verbose unless explicitly told not to
if [[ $( tty -s ) -eq 0 ]] && [[ -z ${DEBUG:-} ]]
then
    DEBUG="true"
fi


# Error handler function
function err_exit {
    local ERRSTR
    local ISNUM
    local SCRIPTEXIT

    ERRSTR="${1}"
    ISNUM='^[0-9]+$'
    SCRIPTEXIT="${2:-1}"

    if [[ ${DEBUG} == true ]]
    then
        # Our output channels
        logger -i -t "${PROGNAME}" -p kern.crit -s -- "${ERRSTR}"
    else
        logger -i -t "${PROGNAME}" -p kern.crit -- "${ERRSTR}"
    fi

    # Only exit if requested exit is numerical
    if [[ ${SCRIPTEXIT} =~ ${ISNUM} ]]
    then
        exit "${SCRIPTEXIT}"
    fi
}

# Setup per-builder values
case $( rpm -qf /etc/os-release --qf '%{name}' ) in
    centos-linux-release | centos-stream-release )
        BUILDER=centos-9stream

        DEFAULTREPOS=(
            baseos
            appstream
            extras-common
        )
        ;;
    redhat-release-server|redhat-release)
        BUILDER=rhel-9

        DEFAULTREPOS=(
            rhel-9-appstream-rhui-rpms
            rhel-9-baseos-rhui-rpms
            rhui-client-config-server-9
        )
        ;;
    oraclelinux-release)
        BUILDER=ol-9

        DEFAULTREPOS=(
            ol9_UEKR7
            ol9_appstream
            ol9_baseos_latest
        )
        ;;
    *)
        echo "Unknown OS. Aborting" >&2
        exit 1
        ;;
esac
DEFAULTREPOS+=()

# Default to enabling default repos
ENABLEDREPOS=$(IFS=,; echo "${DEFAULTREPOS[*]}")

if [[ "$USEDEFAULTREPOS" != "true" ]]
then
    # Enable AMIGENREPOS exclusively when instructed not to use default repos
    ENABLEDREPOS="${AMIGENREPOS}"
elif [[ -n "${AMIGENREPOS:-}" ]]
then
    # When using default repos, also enable AMIGENREPOS if present
    ENABLEDREPOS+=,"${AMIGENREPOS}"
fi


retry()
{
    # Make an arbitrary number of attempts to execute an arbitrary command,
    # passing it arbitrary parameters. Convenient for working around
    # intermittent errors (which occur often with poor repo mirrors).
    #
    # Returns the exit code of the command.
    local n=0
    local try=$1
    local cmd="${*: 2}"
    local result=1
    [[ $# -le 1 ]] && {
        echo "Usage $0 <number_of_retry_attempts> <Command>"
        exit $result
    }

    echo "Will try $try time(s) :: $cmd"

    if [[ "${SHELLOPTS}" == *":errexit:"* ]]
    then
        set +e
        local ERREXIT=1
    fi

    until [[ $n -ge $try ]]
    do
        sleep $n
        $cmd
        result=$?
        if [[ $result -eq 0 ]]
        then
            break
        else
            ((n++))
            echo "Attempt $n, command failed :: $cmd"
        fi
    done

    if [[ "${ERREXIT}" == "1" ]]
    then
        set -e
    fi

    return $result
}  # ----------  end of function retry  ----------


# Disable strict hostkey checking
function DisableStrictHostCheck {
    local HOSTVAL

    if [[ ${1:-} == '' ]]
    then
        err_exit "No connect-string passed to function [${0}]"
    else
        HOSTVAL="$( sed -e 's/^.*@//' -e 's/:.*$//' <<< "${1}" )"
    fi

    # Git host-target parameters
    err_exit "Disabling SSH's strict hostkey checking for ${HOSTVAL}" NONE
    (
        printf "Host %s\n" "${HOSTVAL}"
        printf "  Hostname %s\n" "${HOSTVAL}"
        printf "  StrictHostKeyChecking off\n"
    ) >> "${HOME}/.ssh/config" || \
    err_exit "Failed disabling SSH's strict hostkey checking"
}



##########################
## Main program section ##
##########################

set -x
set -e
set -o pipefail

# Install supplementary tooling
if [[ ${#BUILDDEPS[@]} -gt 0 ]]
then
    err_exit "Installing build-host dependencies" NONE
    yum -y install "${BUILDDEPS[@]}" || \
        err_exit "Failed installing build-host dependencies"

    err_exit "Verifying build-host dependencies" NONE
    rpm -q "${BUILDDEPS[@]}" || \
        err_exit "Verification failed"
fi

if [[ -n "${HTTP_PROXY:-}" ]]
then
    echo "Setting Git Config Proxy"
    git config --global http.proxy "${HTTP_PROXY}"
    echo "Set git config to use proxy"
fi

if [[ -n "${EPELREPO:-}" ]]
then
    yum-config-manager --enable "$EPELREPO" > /dev/null
fi

echo "Installing custom repo packages in the builder box"
IFS="," read -r -a BUILDER_AMIGENREPOSRC <<< "$AMIGENREPOSRC"
for RPM in "${BUILDER_AMIGENREPOSRC[@]}"
do
    {
        STDERR=$( yum -y install "$RPM" 2>&1 1>&$out );
    } {out}>&1 || echo "$STDERR" | grep "Error: Nothing to do"
done

echo "Enabling repos in the builder box"
yum-config-manager --disable "*" > /dev/null
yum-config-manager --enable "$ENABLEDREPOS" > /dev/null

echo "Installing specified extra packages in the builder box"
IFS="," read -r -a BUILDER_EXTRARPMS <<< "$EXTRARPMS"
for RPM in "${BUILDER_EXTRARPMS[@]}"
do
    {
        STDERR=$( yum -y install "$RPM" 2>&1 1>&$out );
    } {out}>&1 || echo "$STDERR" | grep "Error: Nothing to do"
done

# Disable strict host-key checking when doing git-over-ssh
if [[ ${AMIGENSOURCE} =~ "@" ]]
then
    DisableStrictHostCheck "${AMIGENSOURCE}"
fi

# --- End of builder-prep-9.sh ---

# --- Start of cleanup.sh ---
#!/bin/bash

# Remove deps no longer needed
REMOVE_DEPS="virt-what"
yum -y remove --setopt=clean_requirements_on_remove=1 ${REMOVE_DEPS} >/dev/null

# Generate RPM manifest
cat /etc/redhat-release > /tmp/manifest.txt
rpm -qa | sort -u >> /tmp/manifest.txt

# Remove yum artifacts
yum --enablerepo=* clean all >/dev/null
rm -rf /var/cache/yum
rm -rf /var/lib/yum

# Removing leftover leases and persistent rules
echo "cleaning up dhcp leases"
rm -f /var/lib/dhclient/*

# Make sure Udev doesn't block our network
echo "cleaning up udev rules"
rm -f /etc/udev/rules.d/70-persistent-net.rules
mkdir /etc/udev/rules.d/70-persistent-net.rules
rm -rf /dev/.udev/
rm -f /lib/udev/rules.d/75-persistent-net-generator.rules

# Ensure unique SSH hostkeys
echo "generating new ssh hostkeys"
shred -uz /etc/ssh/*key*
service sshd restart

# Clean out miscellaneous log files
for FILE in boot.log btmp cloud-init.log cloud-init-output.log cron dmesg \
    dmesg.old dracut.log lastlog maillog messages secure spooler tallylog \
    wtmp yum.log rhsm/rhsmcertd.log rhsm/rhsm.log sa/sa22
do
    if [[ -e /var/log/$FILE ]];
    then
        cat /dev/null > /var/log/${FILE}
    fi
done

# Clean out audit logs
find -L /var/log/audit -type f -print0 | xargs -0 shred -uz

# Clean out root's history buffers and files
echo "cleaning shell history"
history -c ; cat /dev/null > /root/.bash_history

# --- End of cleanup.sh ---

# --- Start of dep.sh ---
#!/bin/bash
#
# Setup the the box. This runs as root


# You can install anything you need here.

# --- End of dep.sh ---

# --- Start of free-root.sh ---
#!/bin/bash
#
# Script to more-thorougly clear out processes that may be holding the boot-
# disk open
#
################################################################################

set -x
set -e

echo "Restarting systemd"
systemctl daemon-reexec

# The auditd (UpStart) service may or may not be running...
if [[ $( service auditd status > /dev/null 2>&1 )$? -eq 0 ]]
then
  echo "Killing auditd"
  service auditd stop
else
  echo "The auditd service is not running"
fi

echo "Kill all non-essential services"
for SERVICE in $(
  systemctl list-units --type=service --state=running | \
  awk '/loaded active running/{ print $1 }' | \
  grep -Ev '(audit|sshd|user@)'
)
do
  echo "Killing ${SERVICE}"
  systemctl stop "${SERVICE}"
done

echo "Sleeping to allow everything to stop"
sleep 10

if [[ $( mountpoint -q /oldroot )$? -eq 0 ]]
then
  echo "Killing processes locking /oldroot"
  fuser -vmk /oldroot
else
  echo "NO-OP: /oldroot is not a mount"
fi

# --- End of free-root.sh ---

# --- Start of pivot-root.sh ---
#!/bin/bash

##############################################################################
#
# Pivot the root partition to a tmpfs mount point so that the root volume can
# be re-partitioned.
#
##############################################################################

set -x
set -e

# Get fuser
echo "Installing psmisc RPM..."
yum -y install psmisc

# Get rid of anything that might be in the /boot hierarchy
for BOOT_DIR in /boot{/efi,}
do
  if  [[ -d ${BOOT_DIR} ]] &&
      [[ $( mountpoint "${BOOT_DIR}" ) == "${BOOT_DIR} is a mountpoint" ]]
  then
    fuser -vmk "${BOOT_DIR}" || true
    umount "${BOOT_DIR}"
  fi
done


# Create tmpfs mount
echo "Creating /tmproot..."
install -Ddm 000755 /tmp/tmproot
echo "Mounting tmpfs to /tmp/tmproot..."
mount none /tmp/tmproot -t tmpfs

# Copy everything to the tmpfs mount
echo "Copying / to /tmp/tmproot..."
cp -ax / /tmp/tmproot

echo "Copying dev-nodes to /tmp/tmproot..."
cp -a /dev /tmp/tmproot

# Switch / to tmpfs
echo "Creating /tmp/tmproot/oldroot..."
mkdir /tmp/tmproot/oldroot

echo "Prepare for pivot_root action..."
mount --make-rprivate /

echo "Execute pivot_root..."
pivot_root /tmp/tmproot /tmp/tmproot/oldroot

echo "Move sub-mounts into /oldroot..."
mount --move /oldroot/dev /dev
mount --move /oldroot/proc /proc
mount --move /oldroot/sys /sys
mount --move /oldroot/run /run
if [[ $( mountpoint /oldroot/tmp ) =~ "is a mountpoint" ]]
then
  mount --move /oldroot/tmp /tmp
fi

# Unmount everything we can on /oldroot
MOUNTS=$(
    cut -d ' ' -f 2 /proc/mounts | \
    grep '/oldroot/' | \
    sort -ru
)
if [[ ${#MOUNTS} -ne 0 ]]
then
  echo "Attempting to clear stragglers found in /proc/mounts"

  echo "$MOUNTS" | while IFS= read -r MOUNT
  do
    echo "Attempting to dismount ${MOUNT}... "
    umount "$MOUNT" || true
  done
else
  echo "Found no stragglers in /proc/mounts"
fi

# Restart sshd to relink it to /tmp/tmproot
if systemctl is-active --quiet firewalld ; then systemctl stop firewalld ; fi
systemctl restart sshd

# Kill ssh processes, releasing any locks on /oldroot, and forcing packer to reconnect
pkill --signal HUP sshd

# --- End of pivot-root.sh ---

# --- Start of retry.sh ---
#!/bin/bash
# Make an arbitrary number of attempts to execute an arbitrary command,
# passing it arbitrary parameters. Convenient for working around
# intermittent errors (which occur often with poor repo mirrors).
#
# Returns the exit code of the command.

retry()
{
    local n=0
    local try=$1
    local cmd="${*: 2}"
    local result=1
    [[ $# -le 1 ]] && {
        echo "Usage $0 <number_of_retry_attempts> <Command>"
        exit $result
    }

    echo "Will try $try time(s) :: $cmd"

    if [[ "${SHELLOPTS}" == *":errexit:"* ]]
    then
        set +e
        local ERREXIT=1
    fi

    until [[ $n -ge $try ]]
    do
        sleep $n
        $cmd
        result=$?
        if [[ $result -eq 0 ]]
        then
            break
        else
            ((n++))
            echo "Attempt $n, command failed :: $cmd"
        fi
    done

    if [[ "${ERREXIT}" == "1" ]]
    then
        set -e
    fi

    return $result
}  # ----------  end of function retry  ----------

retry "$@"
exit $?

# --- End of retry.sh ---

# --- Start of zerodisk.sh ---
#!/bin/bash

# Zero out the free space to save space in the final image:
echo "zeroing out free space"
dd if=/dev/zero of=/EMPTY bs=1M || true
rm -f /EMPTY

# Sync to ensure that the delete completes before this moves on.
sync
sync
sync

# --- End of zerodisk.sh ---

# --- Start of AWSutils.sh ---
#!/bin/bash
set -eu -o pipefail
#
# Install, configure and activate AWS utilities
#
#######################################################################
PROGNAME=$(basename "$0")
PROGDIR="$( dirname "${0}" )"
CHROOTMNT="${CHROOT:-/mnt/ec2-root}"
CLIV1SOURCE="${CLIV1SOURCE:-UNDEF}"
CLIV2SOURCE="${CLIV2SOURCE:-UNDEF}"
ICONNECTSRC="${ICONNECTSRC:-UNDEF}"
DEBUG="${DEBUG:-UNDEF}"
SSMAGENT="${SSMAGENT:-UNDEF}"
UTILSDIR="${UTILSDIR:-UNDEF}"

# shellcheck disable=SC1091
# Import shared error-exit function
source "${PROGDIR}/err_exit.bashlib"

# Ensure appropriate SEL mode is set
source "${PROGDIR}/no_sel.bashlib"

# Print out a basic usage message
function UsageMsg {
  local SCRIPTEXIT
  SCRIPTEXIT="${1:-1}"

  (
    echo "Usage: ${0} [GNU long option] [option] ..."
    echo "  Options:"
    printf '\t%-4s%s\n' '-C' 'Where to get AWS CLIv1 (Installs to /usr/local/bin)'
    printf '\t%-4s%s\n' '-c' 'Where to get AWS CLIv2 (Installs to /usr/bin)'
    printf '\t%-4s%s\n' '-d' 'Directory containing installable utility-RPMs'
    printf '\t%-4s%s\n' '-h' 'Print this message'
    printf '\t%-4s%s\n' '-i' 'Where to get AWS InstanceConnect (RPM or git URL)'
    printf '\t%-4s%s\n' '-m' 'Where chroot-dev is mounted (default: "/mnt/ec2-root")'
    printf '\t%-4s%s\n' '-n' 'Where to get AWS CFN Bootstrap (Installs tar.gz via Python Pip)'
    printf '\t%-4s%s\n' '-s' 'Where to get AWS SSM Agent (Installs via RPM)'
    printf '\t%-4s%s\n' '-t' 'Systemd services to enable with systemctl'
    echo "  GNU long options:"
    printf '\t%-20s%s\n' '--cfn-bootstrap' 'See "-n" short-option'
    printf '\t%-20s%s\n' '--cli-v1' 'See "-C" short-option'
    printf '\t%-20s%s\n' '--cli-v2' 'See "-c" short-option'
    printf '\t%-20s%s\n' '--help' 'See "-h" short-option'
    printf '\t%-20s%s\n' '--instance-connect' 'See "-i" short-option'
    printf '\t%-20s%s\n' '--mountpoint' 'See "-m" short-option'
    printf '\t%-20s%s\n' '--ssm-agent' 'See "-s" short-option'
    printf '\t%-20s%s\n' '--systemd-services' 'See "-t" short-option'
    printf '\t%-20s%s\n' '--utils-dir' 'See "-d" short-option'
  )
  exit "${SCRIPTEXIT}"
}

# Make sure Python3 is present when needed
function EnsurePy3 {
  # Install python as necessary
  if [[ -x ${CHROOTMNT}/bin/python3 ]]
  then
    err_exit "Python dependency met" NONE
  else
    err_exit "Installing python3..." NONE
    yum --installroot="${CHROOTMNT}" install --quiet -y python3 || \
      err_exit "Failed installing python3"
  fi
}

# Make sure `fapolicyd` exemptions are pre-staged
function ExemptFapolicyd {
  local RULE_DIR
  local RULE_FILE

  RULE_DIR="/etc/fapolicyd/rules.d"
  RULE_FILE="${RULE_DIR}/30-aws.rules"

  chroot "${CHROOTMNT}" install -dDm 0755 -o root -g root "${RULE_DIR}"
  chroot "${CHROOTMNT}" install -bDm 0644 -o root -g root <(
    printf "allow perm=any all : dir=/usr/local/aws-cli/v2/ "
    printf "type=application/x-executable trust 1\n"
    printf "allow perm=any all : dir=/usr/local/aws-cli/v2/ "
    printf "type=application/x-sharedlib trust 1\n"
  ) "${RULE_FILE}"
}

# Install AWS CLI version 1.x
function InstallCLIv1 {
  local INSTALLDIR
  local BINDIR
  local TMPDIR

  INSTALLDIR="/usr/local/aws-cli/v1"
  BINDIR="/usr/local/bin"
  TMPDIR=$(chroot "${CHROOTMNT}" /bin/bash -c "mktemp -d")

  if [[ ${CLIV1SOURCE} == "UNDEF" ]]
  then
    err_exit "AWS CLI v1 not requested for install. Skipping..." NONE
  elif [[ ${CLIV1SOURCE} == http[s]://*zip ]]
  then
    # Make sure Python3 is present
    EnsurePy3

    err_exit "Fetching ${CLIV1SOURCE}..." NONE
    curl -sL "${CLIV1SOURCE}" -o "${CHROOTMNT}${TMPDIR}/awscli-bundle.zip" || \
      err_exit "Failed fetching ${CLIV1SOURCE}"

    err_exit "Dearchiving awscli-bundle.zip..." NONE
    (
      cd "${CHROOTMNT}${TMPDIR}"
      unzip -q awscli-bundle.zip
    ) || \
      err_exit "Failed dearchiving awscli-bundle.zip"

    err_exit "Installing AWS CLIv1..." NONE
    chroot "${CHROOTMNT}" /bin/bash -c "python3 ${TMPDIR}/awscli-bundle/install -i '${INSTALLDIR}' -b '${BINDIR}/aws'" || \
      err_exit "Failed installing AWS CLIv1"

    err_exit "Creating AWS CLIv1 symlink ${BINDIR}/aws1..." NONE
    chroot "${CHROOTMNT}" ln -sf "${INSTALLDIR}/bin/aws" "${BINDIR}/aws1" || \
      err_exit "Failed creating ${BINDIR}/aws1"

    err_exit "Cleaning up install files..." NONE
    rm -rf "${CHROOTMNT}${TMPDIR}" || \
      err_exit "Failed cleaning up install files"
  elif [[ ${CLIV1SOURCE} == pip,* ]]
  then
    # Make sure Python3 is present
    EnsurePy3

    chroot "${CHROOTMNT}" /usr/bin/pip3 install --upgrade "${CLIV1SOURCE/pip*,}"
  fi
}

# Install AWS CLI version 2.x
function InstallCLIv2 {
  local INSTALLDIR
  local BINDIR
  local TMPDIR

  INSTALLDIR="/usr/local/aws-cli"  # installer appends v2/current
  BINDIR="/usr/local/bin"
  TMPDIR=$(chroot "${CHROOTMNT}" /bin/bash -c "mktemp -d")

  if [[ ${CLIV2SOURCE} == "UNDEF" ]]
  then
    err_exit "AWS CLI v2 not requested for install. Skipping..." NONE
  elif [[ ${CLIV2SOURCE} == http[s]://*zip ]]
  then
    err_exit "Fetching ${CLIV2SOURCE}..." NONE
    curl -sL "${CLIV2SOURCE}" -o "${CHROOTMNT}${TMPDIR}/awscli-exe.zip" || \
      err_exit "Failed fetching ${CLIV2SOURCE}"

    err_exit "Dearchiving awscli-exe.zip..." NONE
    (
      cd "${CHROOTMNT}${TMPDIR}"
      unzip -q awscli-exe.zip
    ) || \
      err_exit "Failed dearchiving awscli-exe.zip"

    err_exit "Installing AWS CLIv2..." NONE
    chroot "${CHROOTMNT}" /bin/bash -c "${TMPDIR}/aws/install --update -i '${INSTALLDIR}' -b '${BINDIR}'" || \
      err_exit "Failed installing AWS CLIv2"

    err_exit "Creating AWS CLIv2 symlink ${BINDIR}/aws2..." NONE
    chroot "${CHROOTMNT}" ln -sf "${INSTALLDIR}/v2/current/bin/aws" "${BINDIR}/aws2" || \
      err_exit "Failed creating ${BINDIR}/aws2"

    err_exit "Cleaning up install files..." NONE
    rm -rf "${CHROOTMNT}${TMPDIR}" || \
      err_exit "Failed cleaning up install files"
  fi
}

# Install AWS utils from "directory"
function InstallFromDir {
  true
}

# Install AWS InstanceConnect
function InstallInstanceConnect {
  local BUILD_DIR
  local ICRPM
  local SELPOL

  BUILD_DIR="/tmp/aws-ec2-instance-connect-config"
  SELPOL="ec2-instance-connect"

  if [[ ${ICONNECTSRC} == "UNDEF" ]]
  then
    err_exit "AWS Instance-Connect not requested for install. Skipping..." NONE
    return 0
  elif [[ ${ICONNECTSRC} == *.rpm ]]
  then
    err_exit "Installing v${ICONNECTSRC} via yum..." NONE
    yum --installroot="${CHROOTMNT}" --quiet install -y "${ICONNECTSRC}" || \
      err_exit "Failed installing v${ICONNECTSRC}"
  elif [[ ${ICONNECTSRC} == *.git ]]
  then
    err_exit "Installing InstanceConnect from Git" NONE

    # Build the RPM
    if [[ $( command -v make )$? -ne 0 ]]
    then
      err_exit "No make-utility found in PATH"
    fi

    # Fetch via git
    err_exit "Fetching ${ICONNECTSRC}..." NONE
    git clone "${ICONNECTSRC}" "${BUILD_DIR}" || \
      err_exit "Failed fetching ${ICONNECTSRC}"

    err_exit "Making InstanceConnect RPM..." NONE
    ( cd "${BUILD_DIR}" && make rpm ) || \
      err_exit "Failed to make InstanceConnect RPM"

    # Install the RPM
    ICRPM="$( stat -c '%n' "${BUILD_DIR}"/*noarch.rpm 2> /dev/null )"
    if [[ -n ${ICRPM} ]]
    then
      err_exit "Installing ${ICRPM}..." NONE
      yum --installroot="${CHROOTMNT}" install -y "${ICRPM}" || \
        err_exit "Failed installing ${ICRPM}"
    else
      err_exit "Unable to find RPM in ${BUILD_DIR}"
    fi

  fi

  # Ensure service is enabled
  if [[ $( chroot "${CHROOTMNT}" bash -c "(
          systemctl cat ec2-instance-connect > /dev/null 2>&1
        )" )$? -eq 0 ]]
  then
    err_exit "Enabling ec2-instance-connect service..." NONE
    chroot "${CHROOTMNT}" systemctl enable ec2-instance-connect || \
      err_exit "Failed enabling ec2-instance-connect service"
  else
    err_exit "Could not find ec2-instance-connect in ${CHROOTMNT}"
  fi

  # Ensure SELinux is properly configured
  #  Necessary pending resolution of:
  #  - https://github.com/aws/aws-ec2-instance-connect-config/issues/2
  #  - https://github.com/aws/aws-ec2-instance-connect-config/issues/19
  err_exit "Creating SELinux policy for InstanceConnect..." NONE
  (
    printf 'module ec2-instance-connect 1.0;\n\n'
    printf 'require {\n'
    printf '\ttype ssh_keygen_exec_t;\n'
    printf '\ttype sshd_t;\n'
    printf '\ttype http_port_t;\n'
    printf '\tclass process setpgid;\n'
    printf '\tclass tcp_socket name_connect;\n'
    printf '\tclass file map;\n'
    printf '\tclass file { execute execute_no_trans open read };\n'
    printf '}\n\n'
    printf '#============= sshd_t ==============\n\n'
    printf 'allow sshd_t self:process setpgid;\n'
    printf 'allow sshd_t ssh_keygen_exec_t:file map;\n'
    printf 'allow sshd_t ssh_keygen_exec_t:file '
    printf '{ execute execute_no_trans open read };\n'
    printf 'allow sshd_t http_port_t:tcp_socket name_connect;\n'
  ) > "${CHROOTMNT}/tmp/${SELPOL}.te" || \
    err_exit "Failed creating SELinux policy for InstanceConnect"

  err_exit "Compiling/installing SELinux policy for InstanceConnect..." NONE
  chroot "${CHROOTMNT}" /bin/bash -c "
      cd /tmp
      checkmodule -M -m -o ${SELPOL}.mod ${SELPOL}.te
      semodule_package -o ${SELPOL}.pp -m ${SELPOL}.mod
      semodule -i ${SELPOL}.pp && rm ${SELPOL}.*
    " || \
    err_exit "Failed compiling/installing SELinux policy for InstanceConnect"

}

# Install AWS utils from "directory"
function InstallSSMagent {

  if [[ ${SSMAGENT} == "UNDEF" ]]
  then
    err_exit "AWS SSM-Agent not requested for install. Skipping..." NONE
  elif [[ ${SSMAGENT} == *.rpm ]]
  then
    err_exit "Installing AWS SSM-Agent RPM..." NONE
    yum --installroot="${CHROOTMNT}" install -y "${SSMAGENT}" || \
      err_exit "Failed installing AWS SSM-Agent RPM"

    err_exit "Ensuring AWS SSM-Agent is enabled..." NONE
    chroot "${CHROOTMNT}" systemctl enable amazon-ssm-agent.service || \
      err_exit "Failed ensuring AWS SSM-Agent is enabled"
  fi
}

# Force systemd services to be enabled in resultant AMI
function EnableServices {
  if [[ -z "${SYSTEMDSVCS:-}" ]]
  then
    err_exit "Systemd services not requested for enablement. Skipping..." NONE
    return
  fi

  for SVC in "${SYSTEMDSVCS[@]}"
  do
    printf "Attempting to enable %s in %s... " "${SVC}.service" "${CHROOTMNT}"
    chroot "${CHROOTMNT}" /usr/bin/systemctl enable "${SVC}.service" || err_exit "FAILED"
    echo "SUCCESS"
  done
}

# Install AWS CFN Bootstrap
function InstallCfnBootstrap {
  if [[ -z ${CFNBOOTSTRAP:-} ]]
  then
    err_exit "AWS CFN Bootstrap not requested for install. Skipping..." NONE
  elif [[ ${CFNBOOTSTRAP} == *.tar.gz ]]
  then
    local TMPDIR
    TMPDIR=$(chroot "${CHROOTMNT}" mktemp -d)

    err_exit "Installing rpm dependencies for AWS CFN Bootstrap install..." NONE
    yum --installroot="${CHROOTMNT}" install -y tar || \
      err_exit "Failed installing rpm dependencies"

    err_exit "Fetching ${CFNBOOTSTRAP}..." NONE
    curl -sL "${CFNBOOTSTRAP}" -o "${CHROOTMNT}${TMPDIR}/aws-cfn-bootstrap.tar.gz" || \
      err_exit "Failed fetching ${CFNBOOTSTRAP}"

    err_exit "Installing AWS CFN Bootstrap..." NONE
    chroot "${CHROOTMNT}" python3 -m pip install "${TMPDIR}/aws-cfn-bootstrap.tar.gz" || \
      err_exit "Failed installing AWS CFN Bootstrap"

    err_exit "Setting up directory structure for cfn-hup service..." NONE
    chroot "${CHROOTMNT}" install -Ddm 000755 /opt/aws/apitools/cfn-init/init/redhat/ /opt/aws/bin || \
      err_exit "Failing setting up cfn-hup directories"

    err_exit "Extracting cfn-hup service definition file..." NONE
    chroot "${CHROOTMNT}" tar -C /opt/aws/apitools/cfn-init/ -xzv --wildcards --no-anchored --strip-components=1 -f "${TMPDIR}/aws-cfn-bootstrap.tar.gz" redhat/cfn-hup || \
      err_exit "Failed to extract cfn-hup service definition"

    err_exit "Ensure no invalid file-ownership on binary... " NONE
    chroot "${CHROOTMNT}" chown root:root /opt/aws/apitools/cfn-init/init/redhat/cfn-hup || \
      err_exit "Failed setting user/group on .../cfn-hup"

    err_exit "Creating symlink for cfn-hup service..." NONE
    chroot "${CHROOTMNT}" ln -sf /opt/aws/apitools/cfn-init/init/redhat/cfn-hup /etc/init.d/cfn-hup || \
      err_exit "Failed creating symlink for cfn-hup service"

    err_exit "Making sure cfn-hup service is executable..." NONE
    chmod +x "${CHROOTMNT}/opt/aws/apitools/cfn-init/init/redhat/cfn-hup" || \
      err_exit "Failed making cfn-hup service executable"

    err_exit "Using alternatives to configure cfn-hup symlink and initscript..." NONE
    chroot "${CHROOTMNT}" alternatives --verbose --install /opt/aws/bin/cfn-hup cfn-hup /usr/local/bin/cfn-hup 1 --initscript cfn-hup || \
      err_exit "Failed configuring cfn-hup symlink and initscript"

    err_exit "Cleaning up install files..." NONE
    rm -rf "${CHROOTMNT}${TMPDIR}" || \
      err_exit "Failed cleaning up install files"
  fi
}

# shellcheck disable=SC2016,SC1003
function ProfileSetupAwsCli {
  install -bDm 0644 -o root -g root <(
    printf '# Point AWS utils/libs to the OS CA-trust bundle\n'
    printf 'AWS_CA_BUNDLE=/etc/pki/tls/certs/ca-bundle.crt\n'
    printf 'REQUESTS_CA_BUNDLE="${AWS_CA_BUNDLE}"\n'
    printf '\n'
    printf '# Try to snarf an IMDSv2 token\n'
    printf 'IMDS_TOKEN="$(\n'
    printf '  curl -sk \\\n'
    printf '    -X PUT "http://169.254.169.254/latest/api/token" \\\n'
    printf '    -H "X-aws-ec2-metadata-token-ttl-seconds: 21600"\n'
    printf ')"\n'
    printf '\n'
    printf '# Use token if available\n'
    printf 'if [[ -n ${IMDS_TOKEN} ]]\n'
    printf 'then\n'
    printf '  AWS_DEFAULT_REGION="$(\n'
    printf '    curl -sk \\\n'
    printf '      -H "X-aws-ec2-metadata-token: ${IMDS_TOKEN}" \\\n'
    printf '        http://169.254.169.254/latest/meta-data/placement/region\n'
    printf '  )"\n'
    printf 'else\n'
    printf '  AWS_DEFAULT_REGION="$(\n'
    printf '    curl -sk http://169.254.169.254/latest/meta-data/placement/region\n'
    printf '  )"\n'
    printf 'fi\n'
    printf '\n'
    printf '# Export AWS region if non-null\n'
    printf 'if [[ -n ${AWS_DEFAULT_REGION} ]]\n'
    printf 'then\n'
    printf '  export AWS_DEFAULT_REGION AWS_CA_BUNDLE REQUESTS_CA_BUNDLE\n'
    printf 'else\n'
    printf '  echo "Failed setting AWS-supporting shell-envs"\n'
    printf 'fi\n'
  ) "${CHROOTMNT}/etc/profile.d/aws_envs.sh"
}


######################
## Main program-flow
######################
OPTIONBUFR=$( getopt \
  -o C:c:d:hi:m:n:s:t:\
  --long cfn-bootstrap:,cli-v1:,cli-v2:,help,instance-connect:,mountpoint:,ssm-agent:,systemd-services:,utils-dir: \
  -n "${PROGNAME}" -- "$@")

eval set -- "${OPTIONBUFR}"

###################################
# Parse contents of ${OPTIONBUFR}
###################################
while true
do
  case "$1" in
    -C|--cli-v1)
        case "$2" in
          "")
            err_exit "Error: option required but not specified"
            shift 2;
            exit 1
            ;;
          *)
            CLIV1SOURCE="${2}"
            shift 2;
            ;;
        esac
        ;;
    -c|--cli-v2)
        case "$2" in
          "")
            err_exit "Error: option required but not specified"
            shift 2;
            exit 1
            ;;
          *)
            CLIV2SOURCE="${2}"
            shift 2;
            ;;
        esac
        ;;
    -d|--utils-dir)
        case "$2" in
          "")
            err_exit "Error: option required but not specified"
            shift 2;
            exit 1
            ;;
          *)
            UTILSDIR="${2}"
            shift 2;
            ;;
        esac
        ;;
    -h|--help)
        UsageMsg 0
        ;;
    -i|--instance-connect)
        case "$2" in
          "")
            err_exit "Error: option required but not specified"
            shift 2;
            exit 1
            ;;
          *)
            ICONNECTSRC="${2}"
            shift 2;
            ;;
        esac
        ;;
    -m|--mountpoint)
        case "$2" in
          "")
            err_exit "Error: option required but not specified"
            shift 2;
            exit 1
            ;;
          *)
            CHROOTMNT="${2}"
            shift 2;
            ;;
        esac
        ;;
    -n|--cfn-bootstrap)
        case "$2" in
          "")
            err_exit "Error: option required but not specified"
            shift 2;
            exit 1
            ;;
          *)
            CFNBOOTSTRAP="${2}"
            shift 2;
            ;;
        esac
        ;;
    -s|--ssm-agent)
        case "$2" in
          "")
            err_exit "Error: option required but not specified"
            shift 2;
            exit 1
            ;;
          *)
            SSMAGENT="${2}"
            shift 2;
            ;;
        esac
        ;;
    -t|--systemd-services)
        case "$2" in
          "")
            echo "Error: option required but not specified" > /dev/stderr
            shift 2;
            exit 1
            ;;
          *)
            IFS=, read -ra SYSTEMDSVCS <<< "$2"
            shift 2;
            ;;
        esac
        ;;
    --)
      shift
      break
      ;;
    *)
      err_exit "Internal error!"
      exit 1
      ;;
  esac
done

###############
# Do the work

# Install AWS CLIv1
InstallCLIv1

# Install AWS CLIv2
InstallCLIv2

# Install AWS SSM-Agent
InstallSSMagent

# Install AWS InstanceConnect
InstallInstanceConnect

# Install AWS utils from directory
InstallFromDir

# Install AWS CFN Bootstrap
InstallCfnBootstrap

# Set up fapolicyd Exemption
ExemptFapolicyd

# Enable services
EnableServices

# Set up /etc/profile.d file for AWS CLI
ProfileSetupAwsCli

# --- End of AWSutils.sh ---

# --- Start of DiskSetup.sh ---
#!/bin/bash
set -eu -o pipefail
#
# Script to automate basic setup of CHROOT device
#
#################################################################
PROGNAME="$( basename "$0" )"
PROGDIR="$( dirname "${0}" )"
BOOTDEVSZMIN="768"
BOOTDEVSZ="${BOOTDEVSZ:-${BOOTDEVSZMIN}}"
UEFIDEVSZ="${UEFIDEVSZ:-128}"
CHROOTDEV="${CHROOTDEV:-UNDEF}"
DEBUG="${DEBUG:-UNDEF}"
FSTYPE="${FSTYPE:-xfs}"
LABEL_BOOT="${LABEL_BOOT:-boot_disk}"
LABEL_UEFI="${LABEL_UEFI:-UEFI_DISK}"

# Import shared error-exit function
source "${PROGDIR}/err_exit.bashlib"

# Ensure appropriate SEL mode is set
source "${PROGDIR}/no_sel.bashlib"

# Print out a basic usage message
function UsageMsg {
  local SCRIPTEXIT

  SCRIPTEXIT="${1:-1}"

  (
    echo "Usage: ${0} [GNU long option] [option] ..."
    echo "  Options:"
    printf '\t%-4s%s\n' '-B' 'Boot-partition size (default: 768MiB)'
    printf '\t%-4s%s\n' '-d' 'Base dev-node used for build-device'
    printf '\t%-4s%s\n' '-f' 'Filesystem-type used for root filesystems (default: xfs)'
    printf '\t%-4s%s\n' '-h' 'Print this message'
    printf '\t%-4s%s\n' '-l' ' for /boot filesystem (default: boot_disk)'
    printf '\t%-4s%s\n' '-L' ' for /boot/efi filesystem (default: UEFI_DISK)'
    printf '\t%-4s%s\n' '-p' 'Comma-delimited string of colon-delimited partition-specs'
    printf '\t%-6s%s\n' '' 'Default layout:'
    printf '\t%-8s%s\n' '' '/:rootVol:4'
    printf '\t%-8s%s\n' '' 'swap:swapVol:2'
    printf '\t%-8s%s\n' '' '/home:homeVol:1'
    printf '\t%-8s%s\n' '' '/var:varVol:2'
    printf '\t%-8s%s\n' '' '/var/tmp:varTmpVol:2'
    printf '\t%-8s%s\n' '' '/var/log:logVol:2'
    printf '\t%-8s%s\n' '' '/var/log/audit:auditVol:100%FREE'
    printf '\t%-4s%s\n' '-r' 'Label to apply to root-partition if not using LVM (default: root_disk)'
    printf '\t%-4s%s\n' '-v' 'Name assigned to root volume-group (default: VolGroup00)'
    printf '\t%-4s%s\n' '-U' 'UEFI-partition size (default: 256MiB)'
    echo "  GNU long options:"
    printf '\t%-20s%s\n' '--boot-size' 'See "-B" short-option'
    printf '\t%-20s%s\n' '--disk' 'See "-d" short-option'
    printf '\t%-20s%s\n' '--fstype' 'See "-f" short-option'
    printf '\t%-20s%s\n' '--help' 'See "-h" short-option'
    printf '\t%-20s%s\n' '--label-boot' 'See "-l" short-option'
    printf '\t%-20s%s\n' '--label-uefi' 'See "-L" short-option'
    printf '\t%-20s%s\n' '--partition-string' 'See "-p" short-option'
    printf '\t%-20s%s\n' '--rootlabel' 'See "-r" short-option'
    printf '\t%-20s%s\n' '--uefi-size' 'See "-U" short-option'
    printf '\t%-20s%s\n' '--vgname' 'See "-v" short-option'
  )
  exit "${SCRIPTEXIT}"
}

# Partition as LVM
function CarveLVM {
  local ITER
  local MOUNTPT
  local PARTITIONARRAY
  local PARTITIONSTR
  local VOLFLAG
  local VOLNAME
  local VOLSIZE

  # Whether to use flag-passed partition-string or default values
  if [ -z ${GEOMETRYSTRING+x} ]
  then
    # This is fugly but might(??) be easier for others to follow/update
    PARTITIONSTR="/:rootVol:4"
    PARTITIONSTR+=",swap:swapVol:2"
    PARTITIONSTR+=",/home:homeVol:1"
    PARTITIONSTR+=",/var:varVol:2"
    PARTITIONSTR+=",/var/tmp:varTmpVol:2"
    PARTITIONSTR+=",/var/log:logVol:2"
    PARTITIONSTR+=",/var/log/audit:auditVol:100%FREE"
  else
    PARTITIONSTR="${GEOMETRYSTRING}"
  fi

  # Convert ${PARTITIONSTR} to iterable array
  IFS=',' read -r -a PARTITIONARRAY <<< "${PARTITIONSTR}"

  # Clear the target-disk of partitioning and other structural data
  CleanChrootDiskPrtTbl

  # Lay down the base partitions
  err_exit "Laying down new partition-table..." NONE
  parted -s "${CHROOTDEV}" -- mktable gpt \
    mkpart primary "${FSTYPE}" 1049k 2m \
    mkpart primary fat16 4096s $(( 2 + UEFIDEVSZ ))m \
    mkpart primary xfs $((
      2 + UEFIDEVSZ ))m $(( ( 2 + UEFIDEVSZ ) + BOOTDEVSZ
    ))m \
    mkpart primary xfs $(( ( 2 + UEFIDEVSZ ) + BOOTDEVSZ ))m 100% \
    set 1 bios_grub on \
    set 2 esp on \
    set 3 bls_boot on \
    set 4 lvm on || \
      err_exit "Failed laying down new partition-table"

  ## Create LVM objects

  # Let's only attempt this if we're a secondary EBS
  if [[ ${CHROOTDEV} == /dev/xvda ]] || [[ ${CHROOTDEV} == /dev/nvme0n1 ]]
  then
    err_exit "Skipping explicit pvcreate opertion... " NONE
  else
    err_exit "Creating LVM2 PV ${CHROOTDEV}${PARTPRE:-}4..." NONE
    pvcreate "${CHROOTDEV}${PARTPRE:-}4" || \
      err_exit "PV creation failed. Aborting!"
  fi

  # Create root VolumeGroup
  err_exit "Creating LVM2 volume-group ${VGNAME}..." NONE
  vgcreate -y "${VGNAME}" "${CHROOTDEV}${PARTPRE:-}4" || \
    err_exit "VG creation failed. Aborting!"

  # Create LVM2 volume-objects by iterating ${PARTITIONARRAY}
  ITER=0
  while [[ ${ITER} -lt ${#PARTITIONARRAY[*]} ]]
  do
    MOUNTPT="$( cut -d ':' -f 1 <<< "${PARTITIONARRAY[${ITER}]}")"
    VOLNAME="$( cut -d ':' -f 2 <<< "${PARTITIONARRAY[${ITER}]}")"
    VOLSIZE="$( cut -d ':' -f 3 <<< "${PARTITIONARRAY[${ITER}]}")"

    # Create LVs
    if [[ ${VOLSIZE} =~ FREE ]]
    then
      # Make sure 'FREE' is given as last list-element
      if [[ $(( ITER += 1 )) -eq ${#PARTITIONARRAY[*]} ]]
      then
        VOLFLAG="-l"
        VOLSIZE="100%FREE"
      else
        echo "Using 'FREE' before final list-element. Aborting..."
        kill -s TERM " ${TOP_PID}"
      fi
    else
      VOLFLAG="-L"
      VOLSIZE+="g"
    fi
    lvcreate --yes -W y "${VOLFLAG}" "${VOLSIZE}" -n "${VOLNAME}" "${VGNAME}" || \
      err_exit "Failure creating LVM2 volume '${VOLNAME}'"

    # Create FSes on LVs
    if [[ ${MOUNTPT} == swap ]]
    then
      err_exit "Creating swap filesystem..." NONE
      mkswap "/dev/${VGNAME}/${VOLNAME}" || \
        err_exit "Failed creating swap filesystem..."
    else
      err_exit "Creating filesystem for ${MOUNTPT}..." NONE
      mkfs -t "${FSTYPE}" "${MKFSFORCEOPT}" "/dev/${VGNAME}/${VOLNAME}" || \
        err_exit "Failure creating filesystem for '${MOUNTPT}'"
    fi

    (( ITER+=1 ))
  done

}

# Partition with no LVM
function CarveBare {
  # Clear the target-disk of partitioning and other structural data
  CleanChrootDiskPrtTbl

  # Lay down the base partitions
  err_exit "Laying down new partition-table..." NONE
  parted -s "${CHROOTDEV}" -- mklabel gpt \
    mkpart primary "${FSTYPE}" 1049k 2m \
    mkpart primary fat16 4096s $(( 2 + UEFIDEVSZ ))m \
    mkpart primary xfs $((
      2 + UEFIDEVSZ ))m $(( ( 2 + UEFIDEVSZ ) + BOOTDEVSZ
    ))m \
    mkpart primary xfs $(( ( 2 + UEFIDEVSZ ) + BOOTDEVSZ ))m 100% \
    set 1 bios_grub on \
    set 2 esp on \
    set 3 bls_boot on || \
    err_exit "Failed laying down new partition-table"

  # Create FS on partitions
  err_exit "Creating filesystem on ${CHROOTDEV}${PARTPRE:-}4..." NONE
  mkfs -t "${FSTYPE}" "${MKFSFORCEOPT}" -L "${ROOTLABEL}" \
    "${CHROOTDEV}${PARTPRE:-}4" || \
    err_exit "Failed creating filesystem"
}

function CleanChrootDiskPrtTbl {
  local HAS_PARTS
  local PART_NUM
  local PDEV

  HAS_PARTS="$(
    parted -s "${CHROOTDEV}" print | \
    sed -e '1,/^Number/d' \
        -e '/^$/d'
  )"

  # Ensure there's actually partitions to clear
  if [[ -z ${HAS_PARTS:-} ]]
  then
    echo "Disk has no partitions to clear"
    return
  fi

  # Iteratively nuke partitions from NVMe devices
  if [[ ${CHROOTDEV} == "/dev/nvme"* ]]
  then
    for PDEV in $( blkid | grep "${CHROOTDEV}" | sed 's/:.*$//' )
    do
      PART_NUM="${PDEV//*p/}"

      printf "Deleting partition %s from %s... " "${PART_NUM}" "${CHROOTDEV}"
      parted -sf "${CHROOTDEV}" rm "${PART_NUM}"
      echo SUCCESS
    done
  # Iteratively nuke partitions from Xen Virtual Disk devices
  elif [[ ${CHROOTDEV} == "/dev/xvd"* ]]
  then
    for PDEV in $( blkid | grep "${CHROOTDEV}" | sed 's/:.*$//' )
    do
      PART_NUM="${PDEV//*xvd?/}"

      printf "Deleting partition %s from %s... " "${PART_NUM}" "${CHROOTDEV}"
      parted -sf "${CHROOTDEV}" rm "${PART_NUM}"
      echo SUCCESS
    done
  fi

  # Ask kernel to update its partition-map of target-disk
  partprobe "${CHROOTDEV}"


  # Null-out any lingering disk structs
  err_exit "Clearing existing partition-tables..." NONE
  dd if=/dev/zero of="${CHROOTDEV}" bs=512 count=1000 > /dev/null 2>&1 || \
    err_exit "Failed clearing existing partition-tables"

  # Ask kernel, again, to update its partition-map of target-disk
  partprobe "${CHROOTDEV}" || true
}

function SetupBootParts {

  # Make filesystem for /boot/efi
  err_exit "Creating filesystem on ${CHROOTDEV}${PARTPRE:-}2..." NONE
  mkfs -t vfat -n "${LABEL_UEFI}" "${CHROOTDEV}${PARTPRE:-}2" || \
    err_exit "Failed creating filesystem"

  # Make filesystem for /boot
  err_exit "Creating filesystem on ${CHROOTDEV}${PARTPRE:-}3..." NONE
  mkfs -t "${FSTYPE}" "${MKFSFORCEOPT}" -L "${LABEL_BOOT}" \
    "${CHROOTDEV}${PARTPRE:-}3" || \
    err_exit "Failed creating filesystem"
}


######################
## Main program-flow
######################
OPTIONBUFR=$( getopt \
  -o b:B:d:f:hl:L:p:r:U:v: \
  --long boot-size:,disk:,fstype:,help,label-boot:,label-uefi:,partition-string:,rootlabel:,uefi-size:,vgname: \
  -n "${PROGNAME}" -- "$@")

eval set -- "${OPTIONBUFR}"

###################################
# Parse contents of ${OPTIONBUFR}
###################################
while true
do
  case "$1" in
    -B|--boot-size)
        case "$2" in
          "")
            err_exit "Error: option required but not specified"
            shift 2;
            exit 1
            ;;
          *)
            BOOTDEVSZ=${2}
            if [[ ${BOOTDEVSZ} -lt ${BOOTDEVSZMIN} ]]
            then
              err_exit "Requested size for '/boot' filesystem is too small" 1
            fi
            shift 2;
            ;;
        esac
        ;;
    -d|--disk)
        case "$2" in
          "")
            err_exit "Error: option required but not specified"
            shift 2;
            exit 1
            ;;
          *)
            CHROOTDEV=${2}
            shift 2;
            ;;
        esac
        ;;
    -f|--fstype)
        case "$2" in
          "")
            err_exit "Error: option required but not specified"
            shift 2;
            exit 1
            ;;
          ext3|ext4)
            FSTYPE=${2}
            MKFSFORCEOPT="-F"
            shift 2;
            ;;
          xfs)
            FSTYPE=${2}
            MKFSFORCEOPT="-f"
            shift 2;
            ;;
          *)
            err_exit "Error: unrecognized/unsupported FSTYPE. Aborting..."
            shift 2;
            exit 1
            ;;
        esac
        ;;
    -h|--help)
        UsageMsg 0
        ;;
    -l|--label-boot)
        case "$2" in
          "")
            err_exit "Error: option required but not specified"
            shift 2;
            exit 1
            ;;
          *)
            LABEL_BOOT=${2}
            shift 2;
            ;;
        esac
        ;;
    -L|--label-uefi)
        case "$2" in
          "")
            err_exit "Error: option required but not specified"
            shift 2;
            exit 1
            ;;
          *)
            LABEL_UEFI=${2}
            shift 2;
            ;;
        esac
        ;;
    -p|--partition-string)
        case "$2" in
          "")
            err_exit "Error: option required but not specified"
            shift 2;
            exit 1
            ;;
          *)
            GEOMETRYSTRING=${2}
            shift 2;
            ;;
        esac
        ;;
    -r|--rootlabel)
        case "$2" in
          "")
            err_exit "Error: option required but not specified"
            shift 2;
            exit 1
            ;;
          *)
            ROOTLABEL=${2}
            shift 2;
            ;;
        esac
        ;;
    -U|--uefi-size)
        case "$2" in
          "")
            err_exit "Error: option required but not specified"
            shift 2;
            exit 1
            ;;
          *)
            UEFIDEVSZ=${2}
            shift 2;
            ;;
        esac
        ;;
    -v|--vgname)
        case "$2" in
          "")
            err_exit "Error: option required but not specified"
            shift 2;
            exit 1
            ;;
          *)
          VGNAME=${2}
            shift 2;
            ;;
        esac
        ;;
    --)
      shift
      break
      ;;
    *)
      err_exit "Internal error!"
      exit 1
      ;;
  esac
done

# Bail if not root
if [[ ${EUID} != 0 ]]
then
  err_exit "Must be root to execute disk-carving actions"
fi

# See if our carve-target is an NVMe
if [[ ${CHROOTDEV} == "UNDEF" ]]
then
  err_exit "Failed to specify partitioning-target. Aborting"
elif [[ ${CHROOTDEV} =~ /dev/nvme ]]
then
  PARTPRE="p"
else
  PARTPRE=""
fi

# Determine how we're formatting the disk
if [[ -z ${ROOTLABEL+xxx} ]] && [[ -n ${VGNAME+xxx} ]]
then
  CarveLVM
elif [[ -n ${ROOTLABEL+xxx} ]] && [[ -z ${VGNAME+xxx} ]]
then
  CarveBare
elif [[ -z ${ROOTLABEL+xxx} ]] && [[ -z ${VGNAME+xxx} ]]
then
  err_exit "Failed to specifiy a partitioning-method. Aborting"
else
  err_exit "The '-r'/'--rootlabel' and '-v'/'--vgname' flag-options are mutually-exclusive. Exiting." 0
fi

# Take care of /boot/... paritions
SetupBootParts

# --- End of DiskSetup.sh ---

# --- Start of DualMode-GRUBsetup.sh ---
#!/bin/bash
set -eo pipefail
set -x

EFI_HOME="$( rpm -ql grub2-common | grep '/EFI/' )"
GRUB_HOME=/boot/grub2

# Re-Install RPMs as necessary
if [[ $( rpm --quiet -q grub2-pc )$? -eq 0 ]]
then
  dnf -y reinstall grub2-pc
else
  dnf -y install grub2-pc
fi

# Move "${EFI_HOME}/grub.cfg" as necessary
if [[ -e ${EFI_HOME}/grub.cfg ]]
then
  mv "${EFI_HOME}/grub.cfg" /boot/grub2
fi

# Make our /boot-hosted GRUB2 grub.cfg file
grub2-mkconfig -o /boot/grub2/grub.cfg

# Nuke grubenv file as necessary
if [[ -e /boot/grub2/grubenv ]]
then
  rm -f /boot/grub2/grubenv
fi

# Create fresh grubenv file
grub2-editenv /boot/grub2/grubenv create

# Populate fresh grubenv file:
#   Use `grub2-editenv` command to list parm/vals already stored in the
#   "${EFI_HOME}/grubenv"and dupe them into the BIOS-boot GRUB2 env config
while read -r line
do
  key="$( echo "$line" | cut -f1 -d'=' )"
  value="$( echo "$line" | cut -f2- -d'=' )"
  grub2-editenv /boot/grub2/grubenv set "${key}"="${value}"
done <<< "$( grub2-editenv "${EFI_HOME}/grubenv" list )"

if [[ -e ${EFI_HOME}/grubenv ]]
then
  rm -f "${EFI_HOME}/grubenv"
fi


BOOT_UUID="$( grub2-probe --target=fs_uuid "${GRUB_HOME}" )"
GRUB_DIR="$( grub2-mkrelpath "${GRUB_HOME}" )"

# Ensure EFI grub.cfg is correctly populated
cat << EOF > "${EFI_HOME}/grub.cfg"
connectefi scsi
search --no-floppy --fs-uuid --set=dev ${BOOT_UUID}
set prefix=(\$dev)${GRUB_DIR}
export \$prefix
configfile \$prefix/grub.cfg
EOF

# Clear out stale grub2-efi.cfg file as necessary
if [[ -e /etc/grub2-efi.cfg ]]
then
  rm -f /etc/grub2-efi.cfg
fi

# Link the BIOS- and EFI-boot GRUB-config files
ln -s ../boot/grub2/grub.cfg /etc/grub2-efi.cfg

# Calculate the /boot-hosting root-device
GRUB_TARG="$( df -P /boot/grub2 | awk 'NR>=2 { print $1 }' )"

# Trim off partition-info
case "${GRUB_TARG}" in
  /dev/nvme*)
    GRUB_TARG="${GRUB_TARG//p*/}"
    ;;
  /dev/xvd*)
    GRUB_TARG="${GRUB_TARG::-1}"
    ;;
  *)
    echo "Unsupported disk-type. Aborting..."
    exit 1
    ;;
esac

# Install the /boot/grub2/i386-pc content
grub2-install --target i386-pc "${GRUB_TARG}"

# --- End of DualMode-GRUBsetup.sh ---

# --- Start of MkChrootTree.sh ---
#!/bin/bash
set -eu -o pipefail
#
# Setup build-chroot's physical and virtual storage
#
#######################################################################
PROGNAME=$(basename "$0")
PROGDIR="$( dirname "${0}" )"
CHROOTDEV=""
CHROOTMNT="${CHROOT:-/mnt/ec2-root}"
DEBUG="${DEBUG:-UNDEF}"
DEFGEOMARR=(
  /:rootVol:4
  swap:swapVol:2
  /home:homeVol:1
  /var:varVol:2
  /var/tmp:varTmpVol:2
  /var/log:logVol:2
  /var/log/audit:auditVol:100%FREE
)
DEFGEOMSTR="${DEFGEOMSTR:-$( IFS=$',' ; echo "${DEFGEOMARR[*]}" )}"
FSTYPE="${DEFFSTYPE:-xfs}"
GEOMETRYSTRING="${DEFGEOMSTR}"
SAVIFS="${IFS}"
read -ra VALIDFSTYPES <<< "$( awk '!/^nodev/{ print $1}' /proc/filesystems | tr '\n' ' ' )"


# Import shared error-exit function
source "${PROGDIR}/err_exit.bashlib"

# Ensure appropriate SEL mode is set
source "${PROGDIR}/no_sel.bashlib"

# Print out a basic usage message
function UsageMsg {
  local SCRIPTEXIT
  local PART

  SCRIPTEXIT="${1:-1}"

  (
    echo "Usage: ${0} [GNU long option] [option] ..."
    echo "  Options:"
    printf '\t%-4s%s\n' '-d' 'Device to contain the OS partition(s) (e.g., "/dev/xvdf")'
    printf '\t%-4s%s\n' '-f' 'Filesystem-type used chroot-dev device(s) (default: "xfs")'
    printf '\t%-4s%s\n' '-h' 'Print this message'
    printf '\t%-4s%s\n' '-m' 'Where to mount chroot-dev (default: "/mnt/ec2-root")'
    printf '\t%-4s%s\n' '-p' 'Comma-delimited string of colon-delimited partition-specs'
    printf '\t%-6s%s\n' '' 'Default layout:'
    for PART in "${DEFGEOMARR[@]}"
    do
      printf '\t%-8s%s\n' '' "${PART}"
    done
    echo "  GNU long options:"
    printf '\t%-20s%s\n' '--disk' 'See "-d" short-option'
    printf '\t%-20s%s\n' '--fstype' 'See "-f" short-option'
    printf '\t%-20s%s\n' '--help' 'See "-h" short-option'
    printf '\t%-20s%s\n' '--mountpoint' 'See "-m" short-option'
    printf '\t%-20s%s\n' '--no-lvm' 'LVM2 objects not used'
    printf '\t%-20s%s\n' '--partition-string' 'See "-p" short-option'
  )
  exit "${SCRIPTEXIT}"
}

# Try to ensure good chroot mount-point exists
function ValidateTgtMnt {
  # Ensure chroot mount-point exists
  if [[ -d ${CHROOTMNT} ]]
  then
    if [[ $( mountpoint -q "${CHROOTMNT}" )$? -eq 0 ]]
    then
      err_exit "Selected mount-point [${CHROOTMNT}] already in use. Aborting."
    else
      err_exit "Requested mount-point available for use. Proceeding..." NONE
    fi
  elif [[ -e ${CHROOTMNT} ]] && [[ ! -d ${CHROOTMNT} ]]
  then
    err_exit "Selected mount-point [${CHROOTMNT}] is not correct type. Aborting"
  else
    err_exit "Requested mount-point [${CHROOTMNT}] not found. Creating... " NONE
    install -Ddm 000755 "${CHROOTMNT}" || \
      err_exit "Failed to create mount-point"
    err_exit "Succeeded creating mount-point [${CHROOTMNT}]" NONE
  fi
}

# Mount VG elements
function DoLvmMounts {
  local    ELEM
  local -A MOUNTINFO
  local    MOUNTPT
  local    PARTITIONARRAY
  local    PARTITIONSTR

  PARTITIONSTR="${GEOMETRYSTRING}"

  # Convert ${PARTITIONSTR} to iterable partition-info array
  IFS=',' read -ra PARTITIONARRAY <<< "${PARTITIONSTR}"
  IFS="${SAVIFS}"

  # Create associative-array with mountpoints as keys
  for ELEM in "${PARTITIONARRAY[@]}"
  do
    MOUNTINFO[${ELEM//:*/}]=${ELEM#*:}
  done

  # Ensure all LVM volumes are active
  vgchange -a y "${VGNAME}" || err_exit "Failed to activate LVM"

  # Mount volumes
  for MOUNTPT in $( echo "${!MOUNTINFO[*]}" | tr " " "\n" | sort )
  do

    # Ensure mountpoint exists
    if [[ ! -d ${CHROOTMNT}/${MOUNTPT} ]]
    then
      install -dDm 000755 "${CHROOTMNT}/${MOUNTPT}"
    fi

    # Mount the filesystem
    if [[ ${MOUNTPT} == /* ]]
    then
      err_exit "Mounting '${CHROOTMNT}${MOUNTPT}'..." NONE
      mount -t "${FSTYPE}" "/dev/${VGNAME}/${MOUNTINFO[${MOUNTPT}]//:*/}" \
        "${CHROOTMNT}${MOUNTPT}" || \
          err_exit "Unable to mount /dev/${VGNAME}/${MOUNTINFO[${MOUNTPT}]//:*/}"
    else
      err_exit "Skipping '${MOUNTPT}'..." NONE
    fi
  done

}

# mount /boot and /boot/efi partitions
function MountBootFSes {

    # Create /boot mountpoint as needed
    if [[ ! -d "${CHROOTMNT}/boot" ]]
    then
        mkdir "${CHROOTMNT}/boot"
    fi

    # Mount BIOS-boot partition
    mount -t "${FSTYPE}" "${CHROOTDEV}${PARTPRE}3" "${CHROOTMNT}/boot"

    # Create /boot/efi mountpoint as needed
    if [[ ! -d "${CHROOTMNT}/boot/efi" ]]
    then
        mkdir "${CHROOTMNT}/boot/efi"
    fi

    # Mount UEFI-boot partition
    mount -t vfat "${CHROOTDEV}${PARTPRE}2" "${CHROOTMNT}/boot/efi"
}

# Create block/character-special files
function PrepSpecialDevs {

  local   BINDDEV
  local -a CHARDEVS
  local   DEVICE
  local   DEVMAJ
  local   DEVMIN
  local   DEVPRM
  local   DEVOWN

  CHARDEVS=(
      /dev/null:1:3:000666
      /dev/zero:1:5:000666
      /dev/random:1:8:000666
      /dev/urandom:1:9:000666
      /dev/tty:5:0:000666:tty
      /dev/console:5:1:000600
      /dev/ptmx:5:2:000666:tty
    )
  # Prep for loopback mounts
  mkdir -p "${CHROOTMNT}"/{proc,sys,dev/{pts,shm}}

  # Create character-special files
  for DEVSTR in "${CHARDEVS[@]}"
  do
    DEVICE=$( cut -d: -f 1 <<< "${DEVSTR}" )
    DEVMAJ=$( cut -d: -f 2 <<< "${DEVSTR}" )
    DEVMIN=$( cut -d: -f 3 <<< "${DEVSTR}" )
    DEVPRM=$( cut -d: -f 4 <<< "${DEVSTR}" )
    DEVOWN=$( cut -d: -f 5 <<< "${DEVSTR}" )

    # Create any missing device-nodes as needed
    if [[ -e ${CHROOTMNT}${DEVICE} ]]
    then
      err_exit "${CHROOTMNT}${DEVICE} exists" NONE
    else
      err_exit "Making ${CHROOTMNT}${DEVICE}... " NONE
      mknod -m "${DEVPRM}" "${CHROOTMNT}${DEVICE}" c "${DEVMAJ}" "${DEVMIN}" || \
        err_exit "Failed making ${CHROOTMNT}${DEVICE}"

      # Set an alternate group-owner where appropriate
      if [[ ${DEVOWN:-} != '' ]]
      then
        err_exit "Setting ownership on ${CHROOTMNT}${DEVICE}..." NONE
        chown root:"${DEVOWN}" "${CHROOTMNT}${DEVICE}" || \
          err_exit "Failed setting ownership on ${CHROOTMNT}${DEVICE}..."
      fi
    fi
  done

  # Bind-mount pseudo-filesystems
  grep -v "${CHROOTMNT}" /proc/mounts | \
    sed '{
      /^none/d
      /\/tmp/d
      /rootfs/d
      /dev\/sd/d
      /dev\/xvd/d
      /dev\/nvme/d
      /\/user\//d
      /\/mapper\//d
      /^cgroup/d
    }' | awk '{ print $2 }' | sort -u | while read -r BINDDEV
  do
    # Create mountpoints in chroot-env
    if [[ ! -d ${CHROOTMNT}${BINDDEV} ]]
    then
      err_exit "Creating mountpoint: ${CHROOTMNT}${BINDDEV}" NONE
      install -Ddm 000755 "${CHROOTMNT}${BINDDEV}" || \
        err_exit "Failed creating mountpoint: ${CHROOTMNT}${BINDDEV}"
    fi

    err_exit "Mounting ${CHROOTMNT}${BINDDEV}..." NONE
    mount -o bind "${BINDDEV}" "${CHROOTMNT}${BINDDEV}" || \
      err_exit "Failed mounting ${CHROOTMNT}${BINDDEV}"
  done
}



######################
## Main program-flow
######################
OPTIONBUFR=$( getopt \
  -o d:f:hm:p: \
  --long disk:,fstype:,help,mountpoint:,no-lvm,partition-string: \
  -n "${PROGNAME}" -- "$@")

eval set -- "${OPTIONBUFR}"

###################################
# Parse contents of ${OPTIONBUFR}
###################################
while true
do
  case "$1" in
    -d|--disk)
        case "$2" in
          "")
            err_exit "Error: option required but not specified"
            shift 2;
            exit 1
            ;;
          *)
            CHROOTDEV="${2}"
            shift 2;
            ;;
        esac
        ;;
    -f|--fstype)
        case "$2" in
          "")
            err_exit "Error: option required but not specified"
            shift 2;
            exit 1
            ;;
          *)
            FSTYPE="${2}"
            if [[ $( grep -qw "${FSTYPE}" <<< "${VALIDFSTYPES[*]}" ) -ne 0 ]]
            then
              err_exit "Invalid fstype [${FSTYPE}] requested"
            fi
            shift 2;
            ;;
        esac
        ;;
    -h|--help)
        UsageMsg 0
        ;;
    -m|--mountpoint)
        case "$2" in
          "")
            err_exit "Error: option required but not specified"
            shift 2;
            exit 1
            ;;
          *)
            CHROOTMNT=${2}
            shift 2;
            ;;
        esac
        ;;
    --no-lvm)
        NOLVM="true"
        shift 1;
        ;;
    -p|--partition-string)
        case "$2" in
          "")
            err_exit "Error: option required but not specified"
            shift 2;
            exit 1
            ;;
          *)
            GEOMETRYSTRING=${2}
            shift 2;
            ;;
        esac
        ;;
    --)
      shift
      break
      ;;
    *)
      err_exit "Internal error!"
      exit 1
      ;;
  esac
done

# *MUST* supply a disk-device
if [[ -z ${CHROOTDEV:-} ]]
then
  err_exit "No block-device specified. Aborting"
elif [[ ! -b ${CHROOTDEV} ]]
then
  err_exit "No such block-device [${CHROOTDEV}]. Aborting"
else
  if [[ ${CHROOTDEV} =~ /dev/nvme ]]
  then
    PARTPRE="p"
  else
    PARTPRE=""
  fi
fi

# Ensure build-target mount-hierarchy is available
ValidateTgtMnt

## Mount partition(s) from second slice
# Locate LVM2 volume-group name
read -r VGNAME <<< "$( pvs --noheading -o vg_name "${CHROOTDEV}${PARTPRE}4" )"

# Do partition-mount if 'no-lvm' explicitly requested
if [[ ${NOLVM:-} == "true" ]]
then
  mount -t "${FSTYPE}" "${CHROOTDEV}${PARTPRE}4" "${CHROOTMNT}"
# Bail if not able to find a LVM2 vg-name
elif [[ -z ${VGNAME:-} ]]
then
  err_exit "No LVM2 volume group found on ${CHROOTDEV}${PARTPRE}4 and" NONE
  err_exit "The '--no-lvm' option not set. Aborting"
# Attempt mount of LVM2 volumes
else
  DoLvmMounts
fi

# Mount BIOS and UEFI boot-devices
MountBootFSes

# Make block/character-special files
PrepSpecialDevs


# --- End of MkChrootTree.sh ---

# --- Start of OSpackages.sh ---
#!/bin/bash
#OSPackages.sh
set -eu -o pipefail
#
# Install primary OS packages into chroot-env
#
#######################################################################
PROGNAME=$(basename "$0")
PROGDIR="$( dirname "${0}" )"
CHROOTMNT="${CHROOT:-/mnt/ec2-root}"
DEBUG="${DEBUG:-UNDEF}"
GRUBPKGS_ARM=(
      grub2-efi-aa64
      grub2-efi-aa64-modules
      grub2-tools
      grub2-tools-extra
      grub2-tools-minimal
      shim-aa64
      shim-unsigned-aarch64
)
GRUBPKGS_X86=(
      grub2-efi-x64
      grub2-efi-x64-modules
      grub2-pc-modules
      grub2-tools
      grub2-tools-efi
      grub2-tools-minimal
      shim-x64
)
MINXTRAPKGS=(
  chrony
  cloud-init
  cloud-utils-growpart
  dhcp-client
  dracut-config-generic
  efibootmgr
  firewalld
  gdisk
  grubby
  kernel
  kexec-tools
  libnsl
  lvm2
  python3-pip
  rng-tools
  unzip
)
EXCLUDEPKGS=(
  alsa-firmware
  alsa-tools-firmware
  biosdevname
  insights-client
  iprutils
  iwl100-firmware
  iwl1000-firmware
  iwl105-firmware
  iwl135-firmware
  iwl2000-firmware
  iwl2030-firmware
  iwl3160-firmware
  iwl5000-firmware
  iwl5150-firmware
  iwl6000g2a-firmware
  iwl6050-firmware
  iwl7260-firmware
  rhc
)
RPMFILE=${RPMFILE:-UNDEF}
RPMGRP=${RPMGRP:-core}


# shellcheck disable=SC1091
# Import shared error-exit function
source "${PROGDIR}/err_exit.bashlib"

# Ensure appropriate SEL mode is set
source "${PROGDIR}/no_sel.bashlib"

# Print out a basic usage message
function UsageMsg {
  local SCRIPTEXIT

  SCRIPTEXIT="${1:-1}"

  (
    echo "Usage: ${0} [GNU long option] [option] ..."
    echo "  Options:"
    printf '\t%-4s%s\n' '-a' 'List of repository-names to activate'
    printf '\t%-6s%s' '' 'Default activation: '
    GetDefaultRepos
    printf '\t%-4s%s\n' '-e' 'Extra RPMs to install from enabled repos'
    printf '\t%-4s%s\n' '-g' 'RPM-group to intall (default: "core")'
    printf '\t%-4s%s\n' '-h' 'Print this message'
    printf '\t%-4s%s\n' '-M' 'File containing list of RPMs to install'
    printf '\t%-4s%s\n' '-m' 'Where to mount chroot-dev (default: "/mnt/ec2-root")'
    printf '\t%-4s%s\n' '-r' 'List of repo-def repository RPMs or RPM-URLs to install'
    printf '\t%-4s%s\n' '-X' 'Declare to be a cross-distro build'
    printf '\t%-4s%s\n' '-x' 'List of RPMs to exclude from build-list'
    printf '\t%-20s%s\n' '--cross-distro' 'See "-X" short-option'
    printf '\t%-20s%s\n' '--exclude-rpms' 'See "-x" short-option'
    printf '\t%-20s%s\n' '--extra-rpms' 'See "-e" short-option'
    printf '\t%-20s%s\n' '--help' 'See "-h" short-option'
    printf '\t%-20s%s\n' '--mountpoint' 'See "-m" short-option'
    printf '\t%-20s%s\n' '--pkg-manifest' 'See "-M" short-option'
    printf '\t%-20s%s\n' '--repo-activation' 'See "-a" short-option'
    printf '\t%-20s%s\n' '--repo-rpms' 'See "-r" short-option'
    printf '\t%-20s%s\n' '--rpm-group' 'See "-g" short-option'
    printf '\t%-20s%s\n' '--setup-dnf' 'Addresses (OL8) distribution-specific DNF config-needs'
  )
  exit "${SCRIPTEXIT}"
}

# Default yum repository-list for selected OSes
function GetDefaultRepos {
  local -a BASEREPOS

  # Make sure we can use `rpm` command
  if [[ $(rpm -qa --quiet 2> /dev/null)$? -ne 0 ]]
  then
    err_exit "The rpm command not functioning correctly"
  fi

  case $( rpm -qf /etc/os-release --qf '%{name}' ) in
    almalinux-release)
      BASEREPOS=(
        appstream
        baseos
        extras
      )
      ;;
    centos-stream-release)
      BASEREPOS=(
        appstream
        baseos
        extras-common
      )
      ;;
    oraclelinux-release)
      BASEREPOS=(
        ol9_UEKR7
        ol9_appstream
        ol9_baseos_latest
      )
      ;;
    redhat-release-server|redhat-release)
      BASEREPOS=(
        rhel-9-appstream-rhui-rpms
        rhel-9-baseos-rhui-rpms
        rhui-client-config-server-9
      )
      ;;
    rocky-release)
      BASEREPOS=(
        appstream
        baseos
        extras
      )
      ;;
    *)
      echo "Unknown OS. Aborting" >&2
      exit 1
      ;;
  esac

  ( IFS=',' ; echo "${BASEREPOS[*]}" )
}

# Install base/setup packages in chroot-dev
function PrepChroot {
  local -a BASEPKGS
  local   DNF_ELEM
  local   DNF_FILE
  local   DNF_VALUE

  # Create an array of packages to install
  BASEPKGS=(
    yum-utils
  )

  # Don't try to be helpful if doing cross-distro (i.e., "bootstrapper-build")
  if [[ -z ${ISCROSSDISTRO:-} ]]
  then
    mapfile -t -O "${#BASEPKGS[@]}" BASEPKGS < <(
      rpm --qf '%{name}\n' -qf /etc/os-release ; \
      rpm --qf '%{name}\n' -qf  /etc/yum.repos.d/* 2>&1 | grep -v "not owned" | sort -u ; \
    )
  fi

  # Ensure DNS lookups work in chroot-dev
  if [[ ! -e ${CHROOTMNT}/etc/resolv.conf ]]
  then
    err_exit "Installing ${CHROOTMNT}/etc/resolv.conf..." NONE
    install -Dm 000644 /etc/resolv.conf "${CHROOTMNT}/etc/resolv.conf"
  fi

  # Ensure etc/rc.d/init.d exists in chroot-dev
  if [[ ! -e ${CHROOTMNT}/etc/rc.d/init.d ]]
  then
    install -dDm 000755 "${CHROOTMNT}/etc/rc.d/init.d"
  fi

  # Ensure etc/init.d exists in chroot-dev
  if [[ ! -e ${CHROOTMNT}/etc/init.d ]]
  then
    ln -t "${CHROOTMNT}/etc" -s ./rc.d/init.d
  fi

  # Satisfy weird, OL8-dependecy:
  # * Ensure the /etc/dnf and /etc/yum contents are present
  if [[ -n "${DNF_ARRAY:-}" ]]
  then
    err_exit "Execute DNF hack..." NONE
    for DNF_ELEM in "${DNF_ARRAY[@]}"
    do
      DNF_FILE=${DNF_ELEM//=*/}
      DNF_VALUE=${DNF_ELEM//*=/}

      err_exit "Creating ${CHROOTMNT}/etc/dnf/vars/${DNF_FILE}... " NONE
      install -bDm 0644 <(
        printf "%s" "${DNF_VALUE}"
      ) "${CHROOTMNT}/etc/dnf/vars/${DNF_FILE}" || err_exit Failed
      err_exit "Success" NONE
    done
  fi

  # Clean out stale RPMs
  if [[ $( stat /tmp/*.rpm > /dev/null 2>&1 )$? -eq 0 ]]
  then
    err_exit "Cleaning out stale RPMs..." NONE
    rm -f /tmp/*.rpm || \
      err_exit "Failed cleaning out stale RPMs"
  fi

  # Stage our base RPMs
  if [[ -n ${OSREPOS:-} ]]
  then
    dnf download \
      --disablerepo "*" \
      --enablerepo  "${OSREPOS}" \
      -y \
      --destdir /tmp "${BASEPKGS[@]}"
  else
    dnf download -y --destdir /tmp "${BASEPKGS[@]}"
  fi

  if [[ ${REPORPMS:-} != '' ]]
  then
    FetchCustomRepos
  fi

  # Initialize RPM db in chroot-dev
  err_exit "Initializing RPM db..." NONE
  rpm --root "${CHROOTMNT}" --initdb || \
    err_exit "Failed initializing RPM db"

  # Install staged RPMs
  err_exit "Installing staged RPMs..." NONE
  rpm --force --root "${CHROOTMNT}" -ivh --nodeps --nopre /tmp/*.rpm || \
    err_exit "Failed installing staged RPMs"

  # Install dependences for base RPMs
  err_exit "Installing base RPM's dependences..." NONE
  yum --disablerepo="*" --enablerepo="${OSREPOS}" \
    --installroot="${CHROOTMNT}" -y reinstall "${BASEPKGS[@]}" || \
    err_exit "Failed installing base RPM's dependences"

  # Ensure yum-utils are installed in chroot-dev
  err_exit "Ensuring yum-utils are installed..." NONE
  yum --disablerepo="*" --enablerepo="${OSREPOS}" \
    --installroot="${CHROOTMNT}" -y install yum-utils || \
    err_exit "Failed installing yum-utils"
}

# Install selected package-set into chroot-dev
function MainInstall {
  local YUMCMD

  YUMCMD="yum --nogpgcheck --installroot=${CHROOTMNT} "
  YUMCMD+="--disablerepo=* --enablerepo=${OSREPOS} install -y "

  # If RPM-file not specified, use a group from repo metadata
  if [[ ${RPMFILE} == "UNDEF" ]]
  then
    # Expand the "core" RPM group and store as array
    mapfile -t INCLUDEPKGS < <(
      yum groupinfo "${RPMGRP}" 2>&1 | \
      sed -n '/Mandatory/,/Optional Packages:/p' | \
      sed -e '/^ [A-Z]/d' -e 's/^[[:space:]]*[-=+[:space:]]//'
    )

    # Don't assume that just because the operator didn't pass
    # a manifest-file that the repository is properly run and has
    # the group metadata that it ought to have
    if [[ ${#INCLUDEPKGS[*]} -eq 0 ]]
    then
      err_exit "Oops: unable to parse metadata from repos"
    fi
  # Try to read from local file
  elif [[ -s ${RPMFILE} ]]
  then
    err_exit "Reading manifest-file" NONE
    mapfile -t INCLUDEPKGS < "${RPMFILE}"
  # Try to read from URL
  elif [[ ${RPMFILE} =~ http([s]{1}|):// ]]
  then
    err_exit "Reading manifest from ${RPMFILE}" NONE
    mapfile -t INCLUDEPKGS < <( curl -sL "${RPMFILE}" )
    if [[ ${#INCLUDEPKGS[*]} -eq 0 ]] ||
      [[ ${INCLUDEPKGS[*]} =~ "Not Found" ]] ||
      [[ ${INCLUDEPKGS[*]} =~ "Access Denied" ]]
    then
      err_exit "Failed reading manifest from URL"
    fi
  else
    err_exit "The manifest file does not exist or is empty"
  fi

  # Add extra packages to include-list (array)
  case $( uname -i ) in
    x86_64)
      INCLUDEPKGS=(
        "${INCLUDEPKGS[@]}"
        "${MINXTRAPKGS[@]}"
        "${EXTRARPMS[@]}"
        "${GRUBPKGS_X86[@]}"
      )
      ;;
    aarch64)
      INCLUDEPKGS=(
        "${INCLUDEPKGS[@]}"
        "${MINXTRAPKGS[@]}"
        "${EXTRARPMS[@]}"
        "${GRUBPKGS_ARM[@]}"
      )
      ;;
    *)
      err_exit "Architecture not yet supported" 1
      ;;
  esac

  # Remove excluded packages from include-list
  for EXCLUDE in "${EXCLUDEPKGS[@]}" "${EXTRAEXCLUDE[@]}"
  do
    INCLUDEPKGS=( "${INCLUDEPKGS[@]//*${EXCLUDE}*}" )
  done

  # Install packages
  YUMCMD+="$( IFS=' ' ; echo "${INCLUDEPKGS[*]}" )"
  ${YUMCMD} -x "$( IFS=',' ; echo "${EXCLUDEPKGS[*]}" )"

  # Verify installation
  err_exit "Verifying installed RPMs" NONE
  for RPM in "${INCLUDEPKGS[@]}"
  do
    if [[ ${RPM} = '' ]]
    then
      continue
    fi

    err_exit "Checking presence of ${RPM}..." NONE
    chroot "${CHROOTMNT}" bash -c "rpm -q ${RPM}" || \
    err_exit "Failed finding ${RPM}"
  done
}

# Get custom repo-RPMs
function FetchCustomRepos {
  local REPORPM

  for REPORPM in ${REPORPMS//,/ }
  do
    if [[ ${REPORPM} =~ http[s]*:// ]]
    then
      err_exit "Fetching ${REPORPM} with curl..." NONE
      ( cd /tmp && curl --connect-timeout 15 -O  -sL "${REPORPM}" ) || \
        err_exit "Fetch failed"
    else
      err_exit "Fetching ${REPORPM} with yum..." NONE
      yumdownloader --destdir=/tmp "${REPORPM}" > /dev/null 2>&1 || \
        err_exit "Fetch failed"
    fi
  done
}


######################
## Main program-flow
######################
OPTIONBUFR=$( getopt \
  -o a:e:Fg:hM:m:r:Xx: \
  --long cross-distro,exclude-rpms:,extra-rpms:,help,mountpoint:,pkg-manifest:,repo-activation:,repo-rpms:,rpm-group:,setup-dnf: \
  -n "${PROGNAME}" -- "$@")

eval set -- "${OPTIONBUFR}"

###################################
# Parse contents of ${OPTIONBUFR}
###################################
while true
do
  case "$1" in
    -a|--repo-activation)
        case "$2" in
          "")
            err_exit "Error: option required but not specified"
            shift 2;
            exit 1
            ;;
          *)
            OSREPOS=${2}
            shift 2;
            ;;
        esac
        ;;
    -e|--extra-rpms)
        case "$2" in
          "")
            echo "Error: option required but not specified" > /dev/stderr
            shift 2;
            exit 1
            ;;
          *)
            IFS=, read -ra EXTRARPMS <<< "$2"
            shift 2;
            ;;
        esac
        ;;
    -g|--rpm-group)
        case "$2" in
          "")
            err_exit "Error: option required but not specified"
            shift 2;
            exit 1
            ;;
          *)
            RPMGRP=${2}
            shift 2;
            ;;
        esac
        ;;
    -h|--help)
        UsageMsg 0
        ;;
    --setup-dnf)
        case "$2" in
          "")
            err_exit "Error: option required but not specified"
            shift 2;
            exit 1
            ;;
          *)
            IFS=, read -ra DNF_ARRAY <<< "$2"
            shift 2;
            ;;
        esac
        ;;
    -M|--pkg-manifest)
        case "$2" in
          "")
            err_exit "Error: option required but not specified"
            shift 2;
            exit 1
            ;;
          *)
            RPMFILE=${2}
            shift 2;
            ;;
        esac
        ;;
    -m|--mountpoint)
        case "$2" in
          "")
            err_exit "Error: option required but not specified"
            shift 2;
            exit 1
            ;;
          *)
            CHROOTMNT=${2}
            shift 2;
            ;;
        esac
        ;;
    -r|--repo-rpms)
        case "$2" in
          "")
            err_exit "Error: option required but not specified"
            shift 2;
            exit 1
            ;;
          *)
            REPORPMS=${2}
            shift 2;
            ;;
        esac
        ;;
    -X|--cross-distro)
        ISCROSSDISTRO=TRUE
        shift
        ;;
    -x|--exclude-rpms)
        case "$2" in
          "")
            echo "Error: option required but not specified" > /dev/stderr
            shift 2;
            exit 1
            ;;
          *)
            IFS=, read -ra EXTRAEXCLUDE <<< "$2"
            shift 2;
            ;;
        esac
        ;;
    --)
      shift
      break
      ;;
    *)
      err_exit "Internal error!"
      exit 1
      ;;
  esac
done

# Repos to activate
if [[ ${OSREPOS:-} == '' ]]
then
  OSREPOS="$( GetDefaultRepos )"
fi

# Install minimum RPM-set into chroot-dev
PrepChroot

# Install the desired RPM-group or manifest-file
MainInstall

#############################################
## Ensure AMI repo-activations are correct ##
# disable any repo that might interfere
chroot "${CHROOTMNT}" /usr/bin/yum-config-manager --disable "*"

# Enable the requested list of repos
chroot "${CHROOTMNT}" /usr/bin/yum-config-manager --enable "${OSREPOS}"

# --- End of OSpackages.sh ---

# --- Start of PostBuild.sh ---
#!/bin/bash
set -eu -o pipefail
#
# Install primary OS packages into chroot-env
#
#######################################################################
PROGNAME=$(basename "$0")
PROGDIR="$( dirname "${0}" )"
CHROOTMNT="${CHROOT:-/mnt/ec2-root}"
DEBUG="${DEBUG:-UNDEF}"
FIPSDISABLE="${FIPSDISABLE:-UNDEF}"
GRUBTMOUT="${GRUBTMOUT:-5}"
MAINTUSR="${MAINTUSR:-"maintuser"}"
NOTMPFS="${NOTMPFS:-UNDEF}"
TARGTZ="${TARGTZ:-UTC}"
SUBSCRIPTION_MANAGER="${SUBSCRIPTION_MANAGER:-disabled}"

# Import shared error-exit function
source "${PROGDIR}/err_exit.bashlib"

# Ensure appropriate SEL mode is set
source "${PROGDIR}/no_sel.bashlib"

# Print out a basic usage message
function UsageMsg {
  local SCRIPTEXIT
  SCRIPTEXIT="${1:-1}"

  (
    echo "Usage: ${0} [GNU long option] [option] ..."
    echo "  Options:"
    printf '\t%-4s%s\n' '-f' 'Filesystem-type of chroo-devs (e.g., "xfs")'
    printf '\t%-4s%s\n' '-F' 'Disable FIPS support (NOT IMPLEMENTED)'
    printf '\t%-4s%s\n' '-h' 'Print this message'
    printf '\t%-4s%s\n' '-m' 'Where chroot-dev is mounted (default: "/mnt/ec2-root")'
    printf '\t%-4s%s\n' '-X' 'Declare to be a cross-distro build'
    printf '\t%-4s%s\n' '-z' 'Initial timezone of build-target (default: "UTC")'
    echo "  GNU long options:"
    printf '\t%-20s%s\n' '--cross-distro' 'See "-X" short-option'
    printf '\t%-20s%s\n' '--fstype' 'See "-f" short-option'
    printf '\t%-20s%s\n' '--help' 'See "-h" short-option'
    printf '\t%-20s%s\n' '--mountpoint' 'See "-m" short-option'
    printf '\t%-20s%s\n' '--no-fips' 'See "-F" short-option'
    printf '\t%-20s%s\n' '--no-tmpfs' 'Disable /tmp as tmpfs behavior'
    printf '\t%-20s%s\n' '--timezone' 'See "-z" short-option'
    printf '\t%-20s%s\n' '--use-submgr' 'Do not disable subscription-manager service'
  )
  exit "${SCRIPTEXIT}"
}

# Clean yum/DNF history
function CleanHistory {
  err_exit "Executing yum clean..." NONE
  chroot "${CHROOTMNT}" yum clean --enablerepo=* -y packages || \
    err_exit "Failed executing yum clean"

  err_exit "Nuking DNF history DBs..." NONE
  chroot "${CHROOTMNT}" rm -rf /var/lib/dnf/history.* || \
    err_exit "Failed to nuke DNF history DBs"

}

# Set up fstab
function CreateFstab {
  local    CHROOTDEV
  local    CHROOTFSTYP
  local -a SWAP_DEVS

  CHROOTDEV="$( findmnt -cnM "${CHROOTMNT}" -o SOURCE )"
  CHROOTFSTYP="$( findmnt -cnM "${CHROOTMNT}" -o FSTYPE )"

  # Need to calculate fstab based on build-type
  if [[ -n ${ISCROSSDISTRO:-} ]]
  then
    err_exit "Setting up /etc/fstab for non-LVMed chroot-dev..." NONE
    if [[ ${CHROOTFSTYP:-} == "xfs" ]]
    then
      ROOTLABEL=$(
        xfs_admin -l "${CHROOTDEV}" | sed -e 's/"$//' -e 's/^.* = "//'
      )
    elif [[ ${CHROOTFSTYP:-} == ext[2-4] ]]
    then
      ROOTLABEL=$( e2label "${CHROOTDEV}" )
    else
      err_exit "Couldn't find fslabel for ${CHROOTMNT}"
    fi
    printf "LABEL=%s\t/\t%s\tdefaults\t 0 0\n" "${ROOTLABEL}" \
      "${CHROOTFSTYP}" > "${CHROOTMNT}/etc/fstab" || \
        err_exit "Failed setting up /etc/fstab"
  else
    err_exit "Setting up /etc/fstab for LVMed chroot-dev..." NONE
    grep "${CHROOTMNT}" /proc/mounts | \
      grep -w "/dev/mapper" | \
    sed -e "s/${FSTYPE}.*/${FSTYPE}\tdefaults,rw\t0 0/" \
        -e "s#${CHROOTMNT}\s#/\t#" \
        -e "s#${CHROOTMNT}##" >> "${CHROOTMNT}/etc/fstab" || \
      err_exit "Failed setting up /etc/fstab"
  fi

  # Add any swaps to fstab
  mapfile -t SWAP_DEVS < <( blkid | awk -F: '/TYPE="swap"/{ print $1 }' )
  for SWAP in "${SWAP_DEVS[@]}"
  do
    if [[ $( grep -q "$( readlink -f "${SWAP}" )" /proc/swaps )$? -eq 0 ]]
    then
      err_exit "${SWAP} is already a mounted swap-dev. Skipping" NONE
      continue
    else
      err_exit "Adding ${SWAP} to ${CHROOTMNT}/etc/fstab" NONE
      printf '%s\tnone\tswap\tdefaults\t0 0\n' "${SWAP}" \
        >> "${CHROOTMNT}/etc/fstab" || \
        err_exit "Failed adding ${SWAP} to ${CHROOTMNT}/etc/fstab"
      err_exit "Success" NONE
    fi
  done

  # Add /boot partition to fstab
  BOOT_PART="$(
    grep "${CHROOTMNT}/boot " /proc/mounts | \
    sed 's/ /:/g'
  )"
  if [[ ${BOOT_PART} =~ ":xfs:" ]]
  then
    err_exit "Adding XFS-formatted /boot filesystem to fstab" NONE
    BOOT_LABEL="$(
      xfs_admin -l "${BOOT_PART//:*/}" | \
      sed -e 's/"$//' -e 's/^.*"//'
    )"
    printf 'LABEL=%s\t/boot\txfs\tdefaults,rw\t0 0\n' "${BOOT_LABEL}" >> \
      "${CHROOTMNT}/etc/fstab" || \
      err_exit "Failed adding '/boot' to /etc/fstab"
  elif [[ ${BOOT_PART} =~ ":ext"[2-4]":" ]]
  then
    err_exit "Adding EXTn-formatted /boot filesystem to fstab" NONE
    BOOT_LABEL="$(
      e2label "${BOOT_PART//:*/}"
    )"
    # shellcheck disable=SC2001
    BOOT_FSTYP="$(
      sed 's/\s\s*/:/g' <<< "${BOOT_PART}" | \
      cut -d ':' -f 3
    )"
    printf 'LABEL=%s\t/boot\t%s\tdefaults,rw\t0 0\n' \
      "${BOOT_LABEL}" "${BOOT_FSTYP}" >> "${CHROOTMNT}/etc/fstab" || \
      err_exit "Failed adding '/boot' to /etc/fstab"
  fi

  # Add /boot/efi partition to fstab
  err_exit "Adding /boot/efi filesystem to fstab" NONE
  UEFI_PART="$(
    grep "${CHROOTMNT}/boot/efi " /proc/mounts | \
    sed 's/ /:/g'
  )"
  UEFI_LABEL="$(
    fatlabel "${UEFI_PART//:*/}"
  )"
  printf 'LABEL=%s\t/boot/efi\tvfat\tdefaults,rw\t0 0\n' "${UEFI_LABEL}" >> \
    "${CHROOTMNT}/etc/fstab" || \
    err_exit "Failed adding '/boot/efi' to /etc/fstab"

  # Set an SELinux label
  if [[ -d ${CHROOTMNT}/sys/fs/selinux ]]
  then
    err_exit "Applying SELinux label to fstab..." NONE
    chcon --reference /etc/fstab "${CHROOTMNT}/etc/fstab" || \
      err_exit "Failed applying SELinux label"
  fi

}

# Configure cloud-init
function ConfigureCloudInit {
  local CLINITUSR
  local CLOUDCFG

  CLOUDCFG="${CHROOTMNT}/etc/cloud/cloud.cfg"
  CLINITUSR="$(
    grep -E "name: (maintuser|centos|ec2-user|cloud-user|almalinux)" \
      "${CLOUDCFG}" | \
    awk '{print $2}'
  )"

  # Reset key parms in standard cloud.cfg file
  if [ "${CLINITUSR}" = "" ]
  then
    err_exit "Astandard cloud-init file: can't reset default-user config"
  else
    # Ensure passwords *can* be used with SSH
    err_exit "Allow password logins to SSH..." NONE
    sed -i -e '/^ssh_pwauth/s/\(false\|0\)$/true/' "${CLOUDCFG}" || \
      err_exit "Failed allowing password logins"

    # Delete current "system_info:" block
    err_exit "Nuking standard system_info block..." NONE
    sed -i '/^system_info/,/^  ssh_svcname/d' "${CLOUDCFG}" || \
      err_exit "Failed to nuke standard system_info block"

    # Replace deleted "system_info:" block
    (
      printf "system_info:\n"
      printf "  default_user:\n"
      printf "   name: '%s'\n" "${MAINTUSR}"
      printf "   lock_passwd: true\n"
      printf "   gecos: Local Maintenance User\n"
      printf "   groups: [wheel, adm]\n"
      printf "   sudo: ['ALL=(root) TYPE=sysadm_t ROLE=sysadm_r NOPASSWD:ALL']\n"
      printf "   shell: /bin/bash\n"
      printf "   selinux_user: staff_u\n"
      printf "  distro: rhel\n"
      printf "  paths:\n"
      printf "   cloud_dir: /var/lib/cloud\n"
      printf "   templates_dir: /etc/cloud/templates\n"
      printf "  ssh_svcname: sshd\n"
    ) >> "${CLOUDCFG}"

    # Update NS-Switch map-file for SEL-enabled environment
    err_exit "Enabling SEL lookups by nsswitch..." NONE
    printf "%-12s %s\n" sudoers: files >> "${CHROOTMNT}/etc/nsswitch.conf" || \
      err_exit "Failed enabling SEL lookups by nsswitch"
  fi
}

# Set up logging
function ConfigureLogging {
  local LOGFILE

  # Null out log files
  find "${CHROOTMNT}/var/log" -type f | while read -r LOGFILE
  do
    err_exit "Nulling ${LOGFILE}..." NONE
    cat /dev/null > "${LOGFILE}" || \
      err_exit "Faile to null ${LOGFILE}"
  done

  # Persistent journald logs
  err_exit "Persisting journald logs..." NONE
  echo 'Storage=persistent' >> "${CHROOTMNT}/etc/systemd/journald.conf" || \
    err_exit "Failed persisting journald logs"

  # Ensure /var/log/journal always exists
  err_exit "Creating journald logging-location..." NONE
  install -d -m 0755 "${CHROOTMNT}/var/log/journal" || \
    err_exit "Failed to create journald logging-location"

  err_exit "Ensuring journald logfile storage always exists..." NONE
  chroot "${CHROOTMNT}" systemd-tmpfiles --create --prefix /var/log/journal || \
    err_exit "Failed configuring systemd-tmpfiles"
}

# Configure Networking
function ConfigureNetworking {

  # Set up ifcfg-eth0 file
  err_exit "Setting up ifcfg-eth0 file..." NONE
  (
    printf 'DEVICE="eth0"\n'
    printf 'BOOTPROTO="dhcp"\n'
    printf 'ONBOOT="yes"\n'
    printf 'TYPE="Ethernet"\n'
    printf 'USERCTL="yes"\n'
    printf 'PEERDNS="yes"\n'
    printf 'IPV6INIT="no"\n'
    printf 'PERSISTENT_DHCLIENT="1"\n'
  ) > "${CHROOTMNT}/etc/sysconfig/network-scripts/ifcfg-eth0" || \
    err_exit "Failed setting up file"

  # Set up sysconfig/network file
  err_exit "Setting up network file..." NONE
  (
    printf 'NETWORKING="yes"\n'
    printf 'NETWORKING_IPV6="no"\n'
    printf 'NOZEROCONF="yes"\n'
    printf 'HOSTNAME="localhost.localdomain"\n'
  ) > "${CHROOTMNT}/etc/sysconfig/network" || \
    err_exit "Failed setting up file"

  # Ensure NetworkManager starts
  chroot "${CHROOTMNT}" systemctl enable NetworkManager
}

# Firewalld config
function FirewalldSetup {
  err_exit "Setting up baseline firewall rules..." NONE
  chroot "${CHROOTMNT}" /bin/bash -c "(
    firewall-offline-cmd --set-default-zone=drop
    firewall-offline-cmd --zone=trusted --change-interface=lo
    firewall-offline-cmd --zone=drop --add-service=ssh
    firewall-offline-cmd --zone=drop --add-service=dhcpv6-client
    firewall-offline-cmd --zone=drop --add-icmp-block-inversion
    firewall-offline-cmd --zone=drop --add-icmp-block=fragmentation-needed
    firewall-offline-cmd --zone=drop --add-icmp-block=packet-too-big
  )" || \
  err_exit "Failed etting up baseline firewall rules"
}

# Get root dev
function ClipPartition {
  local CHROOTDEV

  CHROOTDEV="${1}"

  # Get base device-name
  if [[ ${CHROOTDEV} =~ nvme ]]
  then
    CHROOTDEV="${CHROOTDEV%p*}"
  else
    CHROOTDEV="${CHROOTDEV%[0-9]}"
  fi

  echo "${CHROOTDEV}"
}

# Set up grub on chroot-dev
function GrubSetup {
  local CHROOTDEV
  local CHROOTKRN
  local GRUBCMDLINE
  local ROOTTOK
  local VGCHECK

  # Check what kernel is in the chroot-dev
  CHROOTKRN=$(
      chroot "${CHROOTMNT}" rpm --qf '%{version}-%{release}.%{arch}\n' -q kernel
    )

  # See if chroot-dev is LVM2'ed
  VGCHECK="$( grep \ "${CHROOTMNT}"\  /proc/mounts | \
      awk '/^\/dev\/mapper/{ print $1 }'
    )"

  # Determine our "root=" token
  if [[ ${VGCHECK:-} == '' ]]
  then
    CHROOTDEV="$( findmnt -cnM "${CHROOTMNT}" -o SOURCE )"
    CHROOTFSTYP="$( findmnt -cnM "${CHROOTMNT}" -o FSTYPE )"

    if [[ ${CHROOTFSTYP} == "xfs" ]]
    then
      ROOTTOK="root=LABEL=$(
        xfs_admin -l "${CHROOTDEV}" | sed -e 's/"$//' -e 's/^.* = "//'
      )"
    elif [[ ${CHROOTFSTYP} == ext[2-4] ]]
    then
      ROOTTOK="root=LABEL=$(
        e2label "${CHROOTDEV}"
      )"
    else
      err_exit "Could not determine chroot-dev's filesystem-label"
    fi

    CHROOTDEV="$( ClipPartition "${CHROOTDEV}" )"
  else
    ROOTTOK="root=${VGCHECK}"
    VGCHECK="${VGCHECK%-*}"

    # Compute PV from VG info
    CHROOTDEV="$(
        vgs --no-headings -o pv_name "${VGCHECK//\/dev\/mapper\//}" | \
        sed 's/[ 	][ 	]*//g'
      )"

    CHROOTDEV="$( ClipPartition "${CHROOTDEV}" )"

    # Make sure device is valid
    if [[ -b ${CHROOTDEV} ]]
    then
      err_exit "Found ${CHROOTDEV}" NONE
    else
      err_exit "No such device ${CHROOTDEV}"
    fi

    # Exit if computation failed
    if [[ ${CHROOTDEV:-} == '' ]]
    then
      err_exit "Failed to find PV from VG"
    fi

  fi

  # Assemble string for GRUB_CMDLINE_LINUX value
  GRUBCMDLINE="${ROOTTOK} "
  GRUBCMDLINE+="vconsole.keymap=us "
  GRUBCMDLINE+="vconsole.font=latarcyrheb-sun16 "
  GRUBCMDLINE+="console=tty1 "
  GRUBCMDLINE+="console=ttyS0,115200n8 "
  GRUBCMDLINE+="rd.blacklist=nouveau "
  GRUBCMDLINE+="net.ifnames=0 "
  GRUBCMDLINE+="nvme_core.io_timeout=4294967295 "
  if [[ ${FIPSDISABLE} == "true" ]]
  then
    GRUBCMDLINE+="fips=0"
  fi

  # Write default/grub contents
  err_exit "Writing default/grub file..." NONE
  (
    printf 'GRUB_TIMEOUT=%s\n' "${GRUBTMOUT}"
    printf 'GRUB_DISTRIBUTOR="CentOS Linux"\n'
    printf 'GRUB_DEFAULT=saved\n'
    printf 'GRUB_DISABLE_SUBMENU=true\n'
    printf 'GRUB_TERMINAL_OUTPUT="console"\n'
    printf 'GRUB_SERIAL_COMMAND="serial --speed=115200"\n'
    printf 'GRUB_CMDLINE_LINUX="%s"\n' "${GRUBCMDLINE}"
    printf 'GRUB_DISABLE_RECOVERY=true\n'
    printf 'GRUB_DISABLE_OS_PROBER=true\n'
    printf 'GRUB_ENABLE_BLSCFG=true\n'
  ) > "${CHROOTMNT}/etc/default/grub" || \
    err_exit "Failed writing default/grub file"

  # Reinstall the grub-related RPMs (just in case)
  err_exit "Reinstalling the GRUB-related RPMs ..." NONE
  dnf reinstall -y shim-x64 grub2-\* || \
    err_exit "Failed while reinstalling the GRUB-related RPMs" NONE
  err_exit "GRUB-related RPMs reinstalled"  NONE


  # Install GRUB2 bootloader when EFI not active
  if [[ ! -d /sys/firmware/efi ]]
  then
  chroot "${CHROOTMNT}" /bin/bash -c "/sbin/grub2-install ${CHROOTDEV}"
  fi

  # Install GRUB config-file(s)
  err_exit "Installing BIOS-boot GRUB components..." NONE
  chroot "${CHROOTMNT}" /bin/bash -c "grub2-install ${CHROOTDEV} \
    --target=i386-pc"|| \
    err_exit "Failed to install BIOS-boot GRUB components"
  err_exit "BIOS-boot GRUB components installed" NONE

  err_exit "Installing GRUB config-file..." NONE
  chroot "${CHROOTMNT}" /bin/bash -c "/sbin/grub2-mkconfig \
    -o /boot/grub2/grub.cfg --update-bls-cmdline" || \
    err_exit "Failed to install GRUB config-file"
  err_exit "GRUB config-file installed" NONE

  # Make intramfs in chroot-dev
  if [[ ${FIPSDISABLE} != "true" ]]
  then
    err_exit "Attempting to enable FIPS mode in ${CHROOTMNT}..." NONE
    chroot "${CHROOTMNT}" /bin/bash -c "fips-mode-setup --enable" || \
      err_exit "Failed to enable FIPS mode"
  else
    err_exit "Installing initramfs..." NONE
    chroot "${CHROOTMNT}" dracut -fv "/boot/initramfs-${CHROOTKRN}.img" \
      "${CHROOTKRN}" || \
      err_exit "Failed installing initramfs"
  fi


}

function GrubSetup_BIOS {
  err_exit "Installing helper-script..." NONE
  install -bDm 0755  "$( dirname "${0}" )/DualMode-GRUBsetup.sh" \
    "${CHROOTMNT}/root" || err_exit "Failed installing helper-script"
  err_exit "SUCCESS" NONE

  err_exit "Running helper-script..." NONE
  chroot "${CHROOTMNT}" /root/DualMode-GRUBsetup.sh || \
    err_exit "Failed running helper-script..."
  err_exit "SUCCESS" NONE

  err_exit "Cleaning up helper-script..." NONE
  rm "${CHROOTMNT}/root/DualMode-GRUBsetup.sh" || \
    err_exit "Failed removing helper-script..."
  err_exit "SUCCESS" NONE

}


# Configure SELinux
function SELsetup {
  if [[ -d ${CHROOTMNT}/sys/fs/selinux ]]
  then
    err_exit "Setting up SELinux configuration..." NONE
    chroot "${CHROOTMNT}" /bin/sh -c "
      (
        rpm -q --scripts selinux-policy-targeted | \
        sed -e '1,/^postinstall scriptlet/d' | \
        sed -e '1i #!/bin/sh'
      ) > /tmp/selinuxconfig.sh ; \
      bash -x /tmp/selinuxconfig.sh 1" || \
    err_exit "Failed cofiguring SELinux"

    err_exit "Running fixfiles in chroot..." NONE
    chroot "${CHROOTMNT}" /sbin/fixfiles -f relabel || \
      err_exit "Errors running fixfiles"
  else
    # The selinux-policy RPM's %post script currently is not doing The Right
    # Thing (TM), necessitating the creation of a /.autorelabel file in this
    # section. Have filed BugZilla ID #2208282 with Red Hat
    touch "${CHROOTMNT}/.autorelabel" || \
      err_exit "Failed creating /.autorelabel file"

    err_exit "SELinux not available" NONE
  fi
}

# Timezone setup
function TimeSetup {

  # If requested TZ exists, set it
  if [[ -e ${CHROOTMNT}/usr/share/zoneinfo/${TARGTZ} ]]
  then
    err_exit "Setting default TZ to ${TARGTZ}..." NONE
    rm -f "${CHROOTMNT}/etc/localtime" || \
      err_exit "Failed to clear current TZ default"
    chroot "${CHROOTMNT}" ln -s "/usr/share/zoneinfo/${TARGTZ}" \
      /etc/localtime || \
      err_exit "Failed setting ${TARGTZ}"
  else
    true
  fi
}

# Make /tmp a tmpfs
function SetupTmpfs {
  if [[ ${NOTMPFS:-} == "true" ]]
  then
    err_exit "Requested no use of tmpfs for /tmp" NONE
  else
    err_exit "Unmasking tmp.mount unit..." NONE
    chroot "${CHROOTMNT}" /bin/systemctl unmask tmp.mount || \
      err_exit "Failed unmasking tmp.mount unit"

    err_exit "Enabling tmp.mount unit..." NONE
    chroot "${CHROOTMNT}" /bin/systemctl enable tmp.mount || \
      err_exit "Failed enabling tmp.mount unit"

  fi
}

# Disable kdump
function DisableKdumpSvc {
  err_exit "Disabling kdump service... " NONE
  chroot "${CHROOTMNT}" /bin/systemctl disable --now kdump || \
    err_exit "Failed while disabling kdump service"

  err_exit "Masking kdump service... " NONE
  chroot "${CHROOTMNT}" /bin/systemctl mask --now kdump || \
    err_exit "Failed while masking kdump service"
}

# Initialize authselect Subsystem
function authselectInit {
  err_exit "Attempting to initialize authselect... " NONE
  chroot "${CHROOTMNT}" /bin/authselect select sssd --force || \
    err_exit "Failed initializing authselect" 1
  err_exit "Succeeded initializing authselect" NONE
}


######################
## Main program-flow
######################
OPTIONBUFR=$( getopt \
  -o Ff:hm:t:Xz: \
  --long cross-distro,fstype:,grub-timeout:,help,mountpoint:,no-fips,no-tmpfs,timezone,use-submgr \
  -n "${PROGNAME}" -- "$@")

eval set -- "${OPTIONBUFR}"

###################################
# Parse contents of ${OPTIONBUFR}
###################################
while true
do
  case "$1" in
    --use-submgr)
        SUBSCRIPTION_MANAGER="enabled"
        shift 1;
        ;;
    -F|--no-fips)
        FIPSDISABLE="true"
        shift 1;
        ;;
    -f|--fstype)
        case "$2" in
          "")
            err_exit "Error: option required but not specified"
            shift 2;
            exit 1
            ;;
          *)
            FSTYPE="${2}"
            if [[ $( grep -qw "${FSTYPE}" <<< "${VALIDFSTYPES[*]}" ) -ne 0 ]]
            then
              err_exit "Invalid fstype [${FSTYPE}] requested"
            fi
            shift 2;
            ;;
        esac
        ;;
    -g|--grub-timeout)
        case "$2" in
          "")
            err_exit "Error: option required but not specified"
            shift 2;
            exit 1
            ;;
          *)
            GRUBTMOUT="${2}"
            shift 2;
            ;;
        esac
        ;;
    --no-tmpfs)
        NOTMPFS="true"
        ;;
    -h|--help)
        UsageMsg 0
        ;;
    -m|--mountpoint)
        case "$2" in
          "")
            err_exit "Error: option required but not specified"
            shift 2;
            exit 1
            ;;
          *)
            CHROOTMNT="${2}"
            shift 2;
            ;;
        esac
        ;;
    -X|--cross-distro)
        ISCROSSDISTRO=TRUE
        shift
        break
        ;;
    -z|--timezone)
        case "$2" in
          "")
            err_exit "Error: option required but not specified"
            shift 2;
            exit 1
            ;;
          *)
            TARGTZ="${2}"
            shift 2;
            ;;
        esac
        ;;
    --)
      shift
      break
      ;;
    *)
      err_exit "Internal error!"
      exit 1
      ;;
  esac
done

###############
# Call to arms!

# Create /etc/fstab in chroot-dev
CreateFstab

# Set /tmp as a tmpfs
SetupTmpfs

# Configure logging
ConfigureLogging

# Configure networking
ConfigureNetworking

# Set up firewalld
FirewalldSetup

# Configure time services
TimeSetup

# Configure cloud-init
ConfigureCloudInit

# Do GRUB2 setup tasks
GrubSetup

# Do GRUB2 setup tasks for BIOS-boot compatibility
GrubSetup_BIOS

# Initialize authselect subsystem
authselectInit

# Wholly disable kdump service
DisableKdumpSvc

# Clean up yum/dnf history
CleanHistory

# Apply SELinux settings
SELsetup


# --- End of PostBuild.sh ---

# --- Start of README.md ---
# Introduction

This project contains the build-automation for creating LVM-enabled Enterprise
Linux 9 AMIs for use in AWS envrionments. Testing and support will be given to
RHEL 9 and CentOS 9-stream. Other EL9-derivatives should also work. However,
there are currently no plans by the project-owners to specifically verify
compatibility with other RHEL9-adjacent distributions.

## Purpose

The DISA STIGs specify that root/operating-system drive _must_ have a specific,
minimum set of partitions present. Because re-partitioning the root drive is not
practical once a system &ndash; particularly one that is cloud-hosted &ndash; is
booted, this project was undertaken to ensure that VM templates (primarily
Amazon Machine Images) would be available to create virtual machines (primarily
EC2s) that would have the STIG-mandated partitioning-scheme "from birth".

As of the RHEL 9 v1r1 STIG release, the following minimum set of partitions are
required:

* `/home` (per: V-257843/RHEL-09-231010)
* `/tmp` (per: V-257844/RHEL-09-231015)
* `/var` (per: V-257845/RHEL-09-231020)
* `/var/log` (per: V-257846RHEL-09-231025)
* `/var/log/audit` (per: V-257847/RHEL-09-231030)
* `/var/tmp` (per: V-257848 /RHEL-09-231035)

The images published by this project owner to AWS &ndash; in the commercial and
GovCloud partitions &ndash; have a filesystem layout that looks like:

~~~bash
# df -PH
Filesystem                    Size  Used Avail Use% Mounted on
devtmpfs                      4.2M     0  4.2M   0% /dev
tmpfs                         4.1G     0  4.1G   0% /dev/shm
tmpfs                         1.7G  9.0M  1.7G   1% /run
/dev/mapper/RootVG-rootVol    4.3G  1.7G  2.7G  38% /
tmpfs                         4.1G     0  4.1G   0% /tmp
/dev/mapper/RootVG-homeVol    1.1G   42M  1.1G   4% /home
/dev/nvme0n1p3                508M  231M  277M  46% /boot
/dev/mapper/RootVG-varVol     2.2G  232M  2.0G  11% /var
/dev/nvme0n1p2                256M  7.4M  249M   3% /boot/efi
/dev/mapper/RootVG-logVol     2.2G   68M  2.1G   4% /var/log
/dev/mapper/RootVG-varTmpVol  2.2G   50M  2.1G   3% /var/tmp
/dev/mapper/RootVG-auditVol   6.8G   82M  6.7G   2% /var/log/audit
tmpfs                         819M     0  819M   0% /run/user/1000
~~~

Users of this automation can customize both which partitions to make on the root
disk as well as what size and filesystem-type to make them. Consult the
`DiskSetup.sh` utility's help pages for guidance.

# Further Security Notes

Additionally, the system-images produced by this automation allows the following
system-security features to be enabled:

* FIPS 140-2 mode
* SELinux &ndash; set to either `Enforcing` (preferred) or `Permissive`
* UEFI support (to support system-owner's further ability to enable [SecureBoot](https://access.redhat.com/articles/5254641)
  and other Trusted-Computing capabilities)

This capability is offered as some organizations' security-auditors not only
require that some or all of these features be enabled, but that they be enabled
"from birth" (i.e., a configuraton-reboot to activate them is not sufficient).

As of the writing of this guide:
* FIPS mode is enabled (verify with `fips-mode-setup --check`)
* SELinux is set to `Enforcing` (verify with `getenforce`)
* UEFI is available (verify with `echo $( [[ -d /sys/firmware/efi/ ]] )$?` or
  `dmesg | grep -i EFI`)

Lastly, host-based firewall capabilities are enabled via the `firewalld`
service. The images published by this project's owners only enable two services:
`sshd` and `dhcpv6-client`. All other services and ports are blocked by default.
These settings may be validated using `firewall-cmd --list-all`.

# Software Loadout and Updates

The Red Hat images published by this project's owners make use of the `@core`
RPM package-group plus select utilities to cloud-enable the resulting images
(e.g. `cloud-init` and CSP-tooling like Amazon's SSM Agent and AWS CLI).

The Red Hat images published by this project's owners make use of the
official Red Hat repositories managed by Red Hat on behalf of the CSP. If these
repositories will not be suitable to the image-user, it will be necessary for
the image-user to create their own images. The `OSpackages.sh` script accepts
arguments that allow the configuration of custom repositories and RPMs (the
script requires custom repositories be configured by site repository-RPMs)

# CSP Enablement

The image build-automation also includes the option to bake in CSP-specific tooling.

Note: As of this writing, the only CSP-enablement included in this project has been for AWS. If enablement for other CSPs is desired, it is recommended that users of this project contribute suitable automation and documentation.

## AWS Enablement

AWS-enablement is provided through the [AWSutils.sh](AWSutils.sh) script. This script can install:

* AWS CLI v2: See the AWS CLI [Getting Started](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html) page for default, AWS-managed locations for the AWS CLI v2 installers
* AWS CloudFormation bootstrapper (cfn-bootstrap): See ["CloudFormation helper scripts reference"](https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/cfn-helper-scripts-reference.html#cfn-helper-scripts-reference-downloads) for default, AWS-managed locations for the `cfn-bootstrap` Python modules
* AWS SSM Agent: See the _AWS Systems Manager_ document's [Quick Installation Commands](https://docs.aws.amazon.com/systems-manager/latest/userguide/agent-install-rhel-8-9.html#quick-install-rhel-8-9) section for default, AWS-managed locations for the Amazon SSM Agent RPM

This scriipt can also enable arbitrary systemd services. Typically, this will just be the `amazon-ssm-agent` service.

Invoke the `./AWSutils.sh` with either the `-h` or `--help` for the list of flags necessary to specify the above installation-options.

# --- End of README.md ---

# --- Start of Umount.sh ---
#!/bin/bash
# set -euo pipefail
#
# Script to clean up all devices mounted under $CHROOT
#
#################################################################
PROGNAME=$(basename "$0")
PROGDIR="$( dirname "${0}" )"
CHROOT="${CHROOT:-/mnt/ec2-root}"
DEBUG="${DEBUG:-UNDEF}"
TARGDISK="${TARGDISK:-UNDEF}"

# Import shared error-exit function
source "${PROGDIR}/err_exit.bashlib"

# Ensure appropriate SEL mode is set
source "${PROGDIR}/no_sel.bashlib"


# Print out a basic usage message
function UsageMsg {
  local SCRIPTEXIT
  SCRIPTEXIT="${1:-1}"

  (
    echo "Usage: ${0} [GNU long option] [option] ..."
    echo "  Options:"
    printf '\t%-4s%s\n' '-c' 'Where chroot-dev is set up (default: "/mnt/ec2-root")'
    printf '\t%-4s%s\n' '-C' 'Device to clean'
    printf '\t%-4s%s\n' '-h' 'Print this message'
    echo "  GNU long options:"
    printf '\t%-20s%s\n' '--chroot' 'See "-c" short-option'
    printf '\t%-20s%s\n' '--clean' 'See "-C" short-option'
    printf '\t%-20s%s\n' '--help' 'See "-h" short-option'
  )
  exit "${SCRIPTEXIT}"
}


# Do dismount
function UnmountThem {
  local BLK

  while read -r BLK
  do
    err_exit "Unmounting ${BLK}" NONE
    umount "${BLK}" || \
      err_exit "Failed unmounting ${BLK}"
  done < <( cut -d " " -f 3 <( mount ) | grep "${CHROOT}" | sort -r )
}

# Clean things up
function DiskCleanup {
  local TARGVG

  # Look for LVM2 volume-groups on $TARGDISK
  TARGVG="$( pvs "${TARGDISK}"2 --no-heading -o vg_name | sed 's/[      ]*//g' )"

  # Remove LVM2 volume-groups as needed
  if [[ ${TARGVG:-} == "" ]]
  then
    err_exit "Found no LVM volume-groups to clean" NONE
  else
    err_exit "Nuking ${TARGVG}" NONE
    vgremove -f "${TARGVG}" || \
      err_exit "Failed nuking ${TARGVG}"
  fi

  # Null-out disk vtoc
  err_exit "Clearing label from ${TARGDISK}" NONE
  dd if=/dev/urandom of="${TARGDISK}" bs=1024 count=10240 2> /dev/null || \
    err_exit "Failed clearing label from ${TARGDISK}"
}


######################
## Main program-flow
######################
OPTIONBUFR=$( getopt \
  -o C:c:h\
  --long chroot:,clean:,help\
  -n "${PROGNAME}" -- "$@" )

eval set -- "${OPTIONBUFR}"

###################################
# Parse contents of ${OPTIONBUFR}
###################################
while true
do
  case "$1" in
    -c|--chroot)
      case "$2" in
      "")
        err_exit "Error: option required but not specified"
        shift 2;
        exit 1
      ;;
      *)
        CHROOT="${2}"
        shift 2;
        ;;
      esac
      ;;
    -C|--clean)
      case "$2" in
      "")
        err_exit "Error: option required but not specified"
        shift 2;
        exit 1
      ;;
      *)
        TARGDISK="${2}"
        shift 2;
        ;;
      esac
      ;;
    -h|--help)
        UsageMsg 0
        ;;
    --)
      shift
      break
      ;;
    *)
      err_exit "Internal error!"
      exit 1
      ;;
  esac
done

# Dismount chroot
UnmountThem

# Clean chroot-dev if requested
if [[ ${TARGDISK} == "UNDEF" ]]
then
  err_exit "Cleanup option not selected: Done" NONE
else
  DiskCleanup
fi

# --- End of Umount.sh ---

# --- Start of XdistroSetup.sh ---
#!/bin/bash
set -eu -o pipefail
#
# Script to automate basic preparation of a cross-distro
# bootstrap-builder host for a given alternate-distro
# build-target
#
#################################################################
PROGNAME=$( basename "$0" )
PROGDIR="$( dirname "${0}" )"
RUNDIR="$( dirname "$0" )"
DEBUG="${DEBUG:-UNDEF}"
HOME="${HOME:-/root}"

# Import shared error-exit function
source "${PROGDIR}/err_exit.bashlib"

# Ensure appropriate SEL mode is set
source "${PROGDIR}/no_sel.bashlib"


# Print out a basic usage message
function UsageMsg {
  local SCRIPTEXIT
  SCRIPTEXIT="${1:-1}"

  (
    echo "Usage: ${0} [GNU long option] [option] ..."
    echo "  Options:"
    printf '\t%-4s%s\n' '-d' 'Distro nickname (e.g., "Rocky")'
    printf '\t%-4s%s\n' '-h' 'Print this message'
    printf '\t%-4s%s\n' '-k' 'List of RPM-validation key-files or RPMs'
    printf '\t%-4s%s\n' '-r' 'List of repository-related RPMs'
    echo "  GNU long options:"
    printf '\t%-20s%s\n' '--distro-name' 'See "-d" short-option'
    printf '\t%-20s%s\n' '--help' 'See "-h" short-option'
    printf '\t%-20s%s\n' '--repo-rpms' 'See "-r" short-option'
    printf '\t%-20s%s\n' '--sign-keys' 'See "-k" short-option'
  )
  exit "${SCRIPTEXIT}"
}

# Install the alt-distro's GPG key(s)
function InstallGpgKeys {
  local ITEM

  for ITEM in "${PKGSIGNKEYS[@]}"
  do
    if [[ ${ITEM} == "" ]]
    then
      break
    elif [[ ${ITEM} == *.rpm ]]
    then
      echo yum install -y "${ITEM}"
    else
      printf "Installing %s to /etc/pki/rpm-gpg... " \
        "${ITEM}"
      cd /etc/pki/rpm-gpg || err_exit "Could not chdir"
      curl -sOkL "${ITEM}" || err_exit "Download failed"
      echo "Success"
      cd "${RUNDIR}"
    fi
  done
}

function StageDistroRpms {
  local ITEM

  if [[ ! -d ${HOME}/RPM/${DISTRONAME} ]]
  then
    printf "Creating %s... " "${HOME}/RPM/${DISTRONAME}"
    install -dDm 0755 "${HOME}/RPM/${DISTRONAME}" || \
      err_exit "Failed to create ${HOME}/RPM/${DISTRONAME}"
    echo "Success"
  fi

  (
    cd "${HOME}/RPM/${DISTRONAME}"

    for ITEM in "${REPORPMS[@]}"
    do
      printf "fetching %s to %s... " "${ITEM}" \
        "${HOME}/RPM/${DISTRONAME}"
      curl -sOkL "${ITEM}"
      echo "Success"
    done
  )
}



######################
## Main program-flow
######################
OPTIONBUFR=$( getopt \
  -o d:hk:r: \
  --long distro-name:,help,repo-rpms:,sign-keys:, \
  -n "${PROGNAME}" -- "$@")

eval set -- "${OPTIONBUFR}"

###################################
# Parse contents of ${OPTIONBUFR}
###################################
while true
do
  case "$1" in
    -d|--distro-name)
        case "$2" in
          "")
            err_exit "Error: option required but not specified"
            shift 2;
            exit 1
            ;;
          *)
            DISTRONAME="${2}"
            shift 2;
            ;;
        esac
        ;;
    -h|--help)
        UsageMsg 0
        ;;
    -k|--sign-keys)
        case "$2" in
          "")
            err_exit "Error: option required but not specified"
            shift 2;
            exit 1
            ;;
          *)
            IFS=, read -ra PKGSIGNKEYS <<< "$2"
            shift 2;
            ;;
        esac
        ;;
    -r|--repo-rpms)
        case "$2" in
          "")
            err_exit "Error: option required but not specified"
            shift 2;
            exit 1
            ;;
          *)
            IFS=, read -ra REPORPMS <<< "$2"
            shift 2;
            ;;
        esac
        ;;
    --)
      shift
      break
      ;;
    *)
      err_exit "Internal error!"
      exit 1
      ;;
  esac
done

# Bail if not root
if [[ ${EUID} != 0 ]]
then
  err_exit "Must be root to execute disk-carving actions"
fi

# Ensure we have our arguments
if  [[ ${#REPORPMS[*]} -eq 0 ]] ||
    [[ ${#PKGSIGNKEYS[*]} -eq 0 ]] ||
    [[ -z ${DISTRONAME} ]]
then
  UsageMsg 1
fi

InstallGpgKeys
StageDistroRpms

# --- End of XdistroSetup.sh ---

# --- Start of err_exit.bashlib ---
# Make interactive-execution more-verbose unless explicitly told not to
if [[ $( tty -s ) -eq 0 ]] && [[ ${DEBUG} == "UNDEF" ]]
then
  DEBUG="true"
fi

# Error handler function
function err_exit {
  local ERRSTR
  local ISNUM
  local SCRIPTEXIT

  ERRSTR="${1}"
  ISNUM='^[0-9]+$'
  SCRIPTEXIT="${2:-1}"

  if [[ ${DEBUG} == true ]]
  then
    # Our output channels
    logger -i -t "${PROGNAME}" -p kern.crit -s -- "${ERRSTR}"
  else
    logger -i -t "${PROGNAME}" -p kern.crit -- "${ERRSTR}"
  fi

  # Only exit if requested exit is numerical
  if [[ ${SCRIPTEXIT} =~ ${ISNUM} ]]
  then
    exit "${SCRIPTEXIT}"
  fi
}

# --- End of err_exit.bashlib ---

# --- Start of no_sel.bashlib ---
# Disable SElinux as necessary
if [[ $( getenforce ) == "Enforcing" ]]
then
  setenforce 0 || err_exit "Failed to disable SELinux enforcement" 1
fi

# --- End of no_sel.bashlib ---
