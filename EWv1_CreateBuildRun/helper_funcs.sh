#!/usr/bin/env bash
THIS_FILE="helper_funcs.sh"
# This script contains the helper functions for the other scripts in this
# directory as well as the argument parsing and print statements about the run

# NOTE: This script is not meant to be run on it's own (only source'd by the
# other scripts).


###############################################################################
# Helper functions
###############################################################################
function vexec() {
  # Verbose execute, echo argument then run as a command
  [ $VERBOSITY -ge 1 ] && echo -e "+ $1"
  [ $VERBOSITY -ge 2 ] && $1 || $1 > /dev/null 2>&1
}

function print_arr() {
  # Override IFS to a comma and echo input array
  local IFS=", "
  echo "$*"
}

function usage() {
  # Print information about how to use this script
  # usage [{return val} {messages...}]
  local RET=0
  if [ $# -gt 0 ]; then
    RET=$1; shift
  fi
  if [ $# -gt 0 ]; then
    echo "$@"
    echo ""
  fi

  echo "The script loops through the resolutions and compiler suites provided"
  echo "to test the ${COMP} compset using the EarthWorks Repo. It takes the following"
  echo "steps in sequence when executing (no parallel builds)"
  echo "  Create: a new CIME case is created and setup"
  echo "  Build:  the case is built  using case.build"
  echo "  Run:    the case.submit utility is used to start the case run"
  echo "Any of these steps can be skipped, but each step assumes the previous step has"
  echo "been completed."
  echo ""
  echo "usage: $THIS_FILE [--srcroot <path>] [--casesdir <path>]"
  echo "         [--res=<r_array>] [--compiler=<c_array>] [--ntasks=<nt_array>]"
  echo "         [--stopopt opt_str] [--stopn N]"
  echo "         [-nc|--no-create] [-nb|-no-build]   [-nr|--no-run]"
  echo "         [-dr|--dry-run]   [-ow|--overwrite] [-q|--quiet]"
  echo "options:"
  echo "  [--srcroot <path>]    : Path to a clone of the EarthWorks repo, default value:"
  echo "                          \"$SRCROOT\""
  echo "  [--casesdir <path>]   : Directory to put cases in, default value:"
  echo "                          \"$CASES_DIR\""
  echo "  [--res=<res array>]   : Different resoltions to run the case at (must be part"
  echo "                          of case RES statement below)"
  echo "  [--compiler=<c_array>]: Different compilers to create cases with"
  echo "  [--ntasks=<nt_array>] : Different # of tasks (pecounts) to create cases with"
  echo "                          A negative value implies default pecount from CIME"
  echo "  [--stopopt opt_str]   : Value to supply for the STOP_OPTION xml variable"
  echo "                          (applies to all cases). Default value: \"$STOP_OPT\""
  echo "  [--stopn N]           : Number of STOP_OPTION units to run for (applies to "
  echo "                          all cases). Default value:\"$STOP_N\""
  echo "  [-nc|--no-create]     : Skip the create and setup steps"
  echo "  [-nb|--no-build]      : Skip the build step"
  echo "  [-nr|--no-run]        : Skip the run step"
  echo "  [-dr|--dry-run]       : Only print run info and case names, then exit"
  echo "                          This is equivalent to providing \"-nc -nb -nr\""
  echo "  [-ow|--overwrite]     : If a case already exists, delete it first (no effect"
  echo "                          with --no-create provided)"
  echo "  [-cp|--caseprefix str]: Prepend this value to case names if provided"
  echo "  [-q|--quiet]          : Reduce output level, can be supplied twice to suppres"
  echo "                          most output"
  echo ""
  exit $RET
}
# End Helper functions ########################################################


###############################################################################
# Parse and check command line arguments
###############################################################################
ARGS=()
while [ $# -ge 1 ]; do
  ARG="$1"
  case "$ARG" in
    -h|--help)
      usage 0
      ;;
    --srcroot)
      if [ -n "$2" -a -d "$2" ] ; then
        SRCROOT="$2"; shift
      else
        usage 1 "ERROR: --srcroot must be followed by a valid directory"
      fi
      ;;
    --casesdir)
      if [ -n "$2" ]; then
        CASES_DIR="$2"; shift
      else
        usage 1 "ERROR: --casesdir must be followed by a path"
      fi
      ;;
    --res=*)
      RESS=( "${ARG#*=}" )
      ;;
    --compiler=*)
      C_SUITES=( "${ARG#*=}" )
      ;;
    --ntasks=*)
      NTASKSS=( "${ARG#*=}" )
      ;;
    --stopopt)
      STOP_OPT="$2"; shift
      ;;
    --stopn)
      STOP_N="$2"; shift
      ;;
    -nc|--no-create)
      DO_CREATE=false
      ;;
    -nb|--no-build)
      DO_BUILD=false
      ;;
    -nr|--no-run)
      DO_RUN=false
      ;;
    -dr|--dry-run)
      DRY_RUN=true
      ;;
    -ow|--overwrite)
      OVERWRITE=true
      ;;
    -cp|--caseprefix)
      PRE=$2; shift
      ;;
    -q|--quiet)
      if [ $VERBOSITY -gt 0 ]; then
        VERBOSITY=$(($VERBOSITY - 1))
      else
        VERBOSITY=0
      fi
      ;;
    --) # Other arguments may follow --, but break main loop
      shift
      break
      ;;
    -?*) # Not a valid flag, but looks like one
      usage 1 "ERROR invalid flag $ARG provided"
      ;;
    *) # Default case, append to ARGS variable
      ARGS=(${ARGS[@]} $ARG)
      ;;
  esac
  shift
done # while [ $# -ge 1 ]

SRCROOT=$(readlink --canonicalize "$SRCROOT")
CASES_DIR=$(readlink --canonicalize "$CASES_DIR")

if [ ! -d $SRCROOT ]; then
  "ERROR: SRCROOT=\"$SRCROOT\" isn't a valid directory"
  exit 1
fi
if [ ! -d $SRCROOT/cime/scripts ]; then
  echo "ERROR: \"SRCROOT/cime/scripts\" not found. Make sure to run manage_externals/checkout_externals in SRCROOT"
  exit 1
fi
for NT in ${NTASKSS[@]:-"-1"}; do
  case ${NT#[+-]} in
    *[!0-9]*) echo "ERROR: non-integer \"$NT\" encountered in NTASKSS array"; exit 1 ;;
    *) ;; # Do nothing otherwise
  esac
done
# Not doing any steps is equivalent to a dry-run
if [ "$DO_CREATE" = false ] && [ "$DO_BUILD" = false ] && [ "$DO_RUN" = false ]; then
  DRY_RUN=true
fi
# End Parse and check command line arguments ##################################


###############################################################################
# Print some info about the run of this script
###############################################################################
echo -e "Submitting EarthWorks jobs to test ${COMP} compset on $HOSTNAME for $USER"
echo -e "Starting at $(date)"
echo -e "Using:"
echo -e "\tEarthWorks Repo at                   \"$SRCROOT\""
echo -e "\tCreating cases in                    \"$CASES_DIR\""
echo -e "\tCase bld and run directories will be \"${OUTPUTROOT}/\${CASENAME}\""
echo -e "\tRunning with compilers               \"$(print_arr ${C_SUITES[@]})\""
echo -e "\tOn MPAS-A grids (km)                 \"$(print_arr ${RESS[@]})\""
if [ "$DRY_RUN" = true ] ; then
  echo -e "\n\tDRY_RUN=$DRY_RUN, exiting early after printing case names"
else
  if [ "$OVERWRITE" = true ]; then
    echo -e "\tCREATE=$DO_CREATE\tBUILD=$DO_BUILD\tRUN=$DO_RUN\tOVERWRITE=true"
  else
    echo -e "\tCREATE=$DO_CREATE\tBUILD=$DO_BUILD\tRUN=$DO_RUN"
  fi
fi
if [ ${#ARGS[@]} -gt 0 ]; then
	echo -e "Unrecognized and ignored args: ${ARGS[@]}"
fi
echo ""
echo -e  "CASENAMEs:  ${PRE:+PRE_}COMPSET.GRID.MACHINE.COMPILER${NTASKSS:+.NTASKS}"
for C in ${C_SUITES[@]}; do
for R in ${RESS[@]}; do
for NT in ${NTASKSS[@]:-"-1"}; do
  if [ -n "$NT" ] && [ $NT -gt 0 ]; then
    printf "        %s%s.mpasa%03d.%s.%s.%s\n" "${PRE:+${PRE}_}" "$COMP" "$R" "$MACH" "$C" "$NT"
  else
    printf "        %s%s.mpasa%03d.%s.%s\n" "${PRE:+${PRE}_}" "$COMP" "$R" "$MACH" "$C"
  fi
done
done
done
echo -e "-------------------------------------------------------------------------\n\n"
# End Print some info about the run of this script ############################

# End early if DRY_RUN has been set
if [ "$DRY_RUN" = true ] ; then
  exit 0
fi
