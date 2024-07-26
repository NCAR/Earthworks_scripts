#!/usr/bin/env bash
THIS_FILE="${THIS_FILE:-helper_funcs.sh}"
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
  echo "  [-rst|--do-restart]   : Attempt a restart run via RESUBMIT option"
  echo "  [-nc|--no-create]     : Skip the create and setup steps"
  echo "  [-nb|--no-build]      : Skip the build step"
  echo "  [-nr|--no-run]        : Skip the run step"
  echo "  [-dr|--dry-run]       : Only print run info and case names, then exit"
  echo "                          This is equivalent to providing \"-nc -nb -nr\""
  echo "  [-ow|--overwrite]     : If a case already exists, delete it first (no effect"
  echo "                          with --no-create provided)"
  echo "  [-cp|--caseprefix str]: Prepend this value to case names if provided"
  echo "  [-id|--inputdata path]: Use this path instead of the default for DIN_LOC_ROOT"
  echo "  [-q|--quiet]          : Reduce output level, can be supplied twice to suppres"
  echo "                          most output"
  echo ""
  exit $RET
}


function get_nodes(){
  # Get the node count for the run from preview_run output
  # NOTE: requires ./case.setup to have been run and to be inside a case
  local NNODES=$(./preview_run | grep -e "nodes:" | awk -F: '{gsub(/[ \t]+/,"",$2)} {print $2}')
  echo "$NNODES"
}

function get_pcols(){
  # Exit early if NGPUS_PER_NODE isn't a positive integer
  if [ "${NGPUS_PER_NODE}" -ne "${NGPUS_PER_NODE}" ] ; then
    # Not a number
    echo -1
    return
  else
    if [ "0" -ge "${NGPUS_PER_NODE}" ] ; then
      echo -1
      return
    fi
  fi

  local ncells nnodes ngpus
  ncells="${NCELLS}"
  [ "${ncells}" -ne "${ncells}" ] && (echo -1 && return)
  nnodes="$(get_nodes)"
  [ "${nnodes}" -ne "${nnodes}" ] && (echo -1 && return)
  ngpus="${NGPUS_PER_NODE}"
  [ "${ngpus}" -ne "${ngpus}" ] && (echo -1 && return)

  echo "$((${ncells} / ( ${nnodes} * $ngpus ) ))"
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
      if [ "${RESS::1}" = "\"" ] ; then
        RESS[0]="${RESS[0]:1}"; shift; ARG="$1"
        while [ "${ARG: -1}" != "\"" ]; do
          RESS=( ${RESS[@]} "${ARG:: -1}" ); shift; ARG="$1"
        done
        RESS=( ${RESS[@]} "${ARG}" )
      elif [ "${RESS::1}" = "\'" ] ; then
        RESS[0]="${RESS[0]:1}"; shift; ARG="$1"
        while [ "${ARG: -1}" != "\'" ]; do
          RESS=( ${RESS[@]} "${ARG}" ); shift; ARG="$1"
        done
        RESS=( ${RESS[@]} "${ARG:: -1}" )
      elif [ "${RESS::1}" = "(" ] ; then
        RESS[0]="${RESS[0]:1}"; shift; ARG="$1"
        while [ "${ARG: -1}" != ")" ]; do
          RESS=( ${RESS[@]} "${ARG}" ); shift; ARG="$1"
        done
        RESS=( ${RESS[@]} "${ARG:: -1}" )
      fi
      ;;
    --compiler=*)
      C_SUITES=( "${ARG#*=}" )
      if [ "${C_SUITES::1}" = "\"" ] ; then
        C_SUITES[0]="${C_SUITES[0]:1}"; shift; ARG="$1"
        while [ "${ARG: -1}" != "\"" ]; do
          C_SUITES=( ${C_SUITES[@]} "${ARG:: -1}" ); shift; ARG="$1"
        done
        C_SUITES=( ${C_SUITES[@]} "${ARG}" )
      elif [ "${C_SUITES::1}" = "\'" ] ; then
        C_SUITES[0]="${C_SUITES[0]:1}"; shift; ARG="$1"
        while [ "${ARG: -1}" != "\'" ]; do
          C_SUITES=( ${C_SUITES[@]} "${ARG}" ); shift; ARG="$1"
        done
        C_SUITES=( ${C_SUITES[@]} "${ARG:: -1}" )
      elif [ "${C_SUITES::1}" = "(" ] ; then
        C_SUITES[0]="${C_SUITES[0]:1}"; shift; ARG="$1"
        while [ "${ARG: -1}" != ")" ]; do
          C_SUITES=( ${C_SUITES[@]} "${ARG}" ); shift; ARG="$1"
        done
        C_SUITES=( ${C_SUITES[@]} "${ARG:: -1}" )
      fi
      ;;
    --ntasks=*)
      NTASKSS=( "${ARG#*=}" )
      if [ "${NTASKSS::1}" = "\"" ] ; then
        NTASKSS[0]="${NTASKSS[0]:1}"; shift; ARG="$1"
        while [ "${ARG: -1}" != "\"" ]; do
          NTASKSS=( ${NTASKSS[@]} "${ARG:: -1}" ); shift; ARG="$1"
        done
        NTASKSS=( ${NTASKSS[@]} "${ARG}" )
      elif [ "${NTASKSS::1}" = "\'" ] ; then
        NTASKSS[0]="${NTASKSS[0]:1}"; shift; ARG="$1"
        while [ "${ARG: -1}" != "\'" ]; do
          NTASKSS=( ${NTASKSS[@]} "${ARG}" ); shift; ARG="$1"
        done
        NTASKSS=( ${NTASKSS[@]} "${ARG:: -1}" )
      elif [ "${NTASKSS::1}" = "(" ] ; then
        NTASKSS[0]="${NTASKSS[0]:1}"; shift; ARG="$1"
        while [ "${ARG: -1}" != ")" ]; do
          NTASKSS=( ${NTASKSS[@]} "${ARG}" ); shift; ARG="$1"
        done
        NTASKSS=( ${NTASKSS[@]} "${ARG:: -1}" )
      fi
      ;;
    --stopopt)
      STOP_OPT="$2"; shift
      ;;
    --stopn)
      STOP_N="$2"; shift
      ;;
    -rst|--do-restart)
      DO_RESTART=true
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
      PRE="$2"; shift
      ;;
    -id|--inputdata)  
      INPUTDATA="$2"; shift
      ;;
    -g|--gpus)
      GPU_PER_NODE="4"
      GPU_TYPE="a100"
      GPU_OFFLOAD="openacc"
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

DO_STR=""
if [ "$DRY_RUN" = true ] ; then
  DO_STR="DRY_RUN=$DRY_RUN, exiting early after printing case names"
else
  DO_STR="CREATE=$DO_CREATE\tBUILD=$DO_BUILD\tRUN=$DO_RUN"
fi
if [ "${DO_RESTART}" = true ]; then
  DO_STR="${DO_STR}\tRESTART=true"
fi
if [ "${OVERWRITE}" = true ]; then
  DO_STR="${DO_STR}\tOVERWRITE=true"
fi


echo -e "Submitting EarthWorks jobs to test ${COMP} compset on $HOSTNAME for $USER"
echo -e "Starting at $(date)"
echo -e "Using:"
echo -e "\tEarthWorks Repo at                   \"$SRCROOT\""
echo -e "\tCreating cases in                    \"$CASES_DIR\""
echo -e "\tCase bld and run directories will be \"${OUTPUTROOT}/\${CASENAME}\""
echo -e "\tRunning with compilers               \"$(print_arr ${C_SUITES[@]})\""
if [ -n "$GPU_PER_NODE" ]; then
  echo -e "\tRequesting GPUs                      \"GPU_PER_NODE=${GPU_PER_NODE} GPU_TYPE=${GPU_TYPE} GPU_OFFLOAD=${GPU_OFFLOAD}\""
fi
echo -e "\tOn MPAS-A grids (km)                 \"$(print_arr ${RESS[@]})\""
echo -e "\t${DO_STR}"
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
