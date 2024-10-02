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
