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
