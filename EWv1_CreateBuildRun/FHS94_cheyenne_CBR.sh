#!/usr/bin/env bash
THIS_FILE="FHS94_cheyenne_CBR.sh"
# This script allows for easy creation of FHS94 cases on the Cheyenne
# Supercomputer using an already downloaded copy of the EarthWorks repo. Users
# should edit the desired sections to create/compiler/run their desired tests.
# Consult the `usage` function below or run this  with --help for more info.


###############################################################################
# EDIT HERE for easy customization of default values
###############################################################################
# Location of the EarthWorks clone to use
SRCROOT="../EarthWorks"
# Location to put cases and cases_out directories
CASES_DIR="../cases/"
# For compiler, provide an array of valid compilers in C_SUITES
C_SUITES="intel"
# For resolutions, provide an array of valid CESM grids in the RESS variable
RESS="120"

## Controls for this script
# VERBOSITY is used to control the output of vexec function below
#  2 -> echo command and display command output
#  1 -> echo command and suppress command output
#  0 -> only run the command (silent)
VERBOSITY=2
# If set to false, skip the associated section
DO_CREATE=true     # Also includes setup
DO_BUILD=true
DO_RUN=true
# Remove any CASEROOTS before anything else in create section
OVERWRITE=false

## Other configuration variables
COMP="FHS94"
MACH="cheyenne"
A_KEY="UCSU0085"
PRE="" # Case prefix for uniqueness
NTASKS=""   # Set to a non-empty value to overwrite the default pecount for the cases
# End EDIT HERE ###############################################################


###############################################################################
# Helper functions, parse command line args, and overwrite default values
###############################################################################
function vexec() {
  # Verbose execute, echo argument then run as a command
  [ $VERBOSITY -ge 1 ] && echo -e "+ $1"
  [ $VERBOSITY -ge 2 ] && $1 || $1 > /dev/null 2>&1
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
  echo "usage: $THIS_FILE [--srcroot=<path>] [--casesdir=<path>]"
  echo "         [--res=<r_array>] [--compiler=<c_array>]"
  echo "         [-nc|--no-create] [-nb|-no-build] [-nr|--no-run]"
  echo "         [-ow|--overwrite] [-q|--quiet]"
  echo "options:"
  #echo "  SRCROOT               : (Required) Path to a clone of the EarthWorks repo"
  echo "  [--srcroot <path>]    : Path to a clone of the EarthWorks repo, default value:"
  echo "                          \"$SRCROOT\""
  echo "  [--casesdir <path>]   : Directory to put cases in, default value:"
  echo "                          \"$CASES_DIR\""
  echo "  [--res=<res array>]   : Different resoltions to run the case at (must be part"
  echo "                          of case RES statement below)"
  echo "  [--compiler=<c_array>]: Different compilers to create cases with"
  echo "  [-nc|--no-create]     : Skip the create and setup steps"
  echo "  [-nb|--no-build]      : Skip the build step"
  echo "  [-nr|--no-run]        : Skip the run step"
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
      RESS=${ARG#*=}
      ;;
    --compiler=*)
      C_SUITES=${ARG#*=}
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
      ARGS=(${ARGS[@]} $ARGS)
      ;;
  esac
  shift
done # while [ $# -ge 1 ]

SRCROOT=$(readlink --canonicalize "$SRCROOT")
CASES_DIR=$(readlink --canonicalize "$CASES_DIR")

if [ ! -d $SRCROOT ]; then
  usage 1 "ERROR: SRCROOT=\"$SRCROOT\" isn't a valid directory"
fi
if [ ! -d $SRCROOT/cime/scripts ]; then
  echo "ERROR: Provided SRCROOT=\"$SRCROOT\" either isn't valid or needs to run checkout_externals"
  exit 1
fi
# End Parse and check command line arguments ##################################


# Print some info about the run of this script
echo -e "Submitting EarthWorks jobs to test ${COMP} compset on $HOSTNAME for $USER"
echo -e "Starting at $(date)"
echo -e "Using:"
echo -e "\tEarthWorks Repo at                 \"$SRCROOT\""
echo -e "\tCreating cases in                  \"$CASES_DIR\""
echo -e "\tRunning with compiler              \"${C_SUITES[@]}\""
echo -e "\tOn MPAS-A grids (km)               \"${RESS[@]}\""
if [ "$OVERWRITE" = true ]; then
  echo -e "\tCREATE=$DO_CREATE\tBUILD=$DO_BUILD\tRUN=$DO_RUN\tOVERWRITE=true"
else
  echo -e "\tCREATE=$DO_CREATE\tBUILD=$DO_BUILD\tRUN=$DO_RUN"
fi
if [ ${#ARGS[@]} -gt 0 ]; then
	echo -e "Unrecognized and ignored args: ${ARGS[@]}"
fi
echo ""
echo -e  "Cases:  ${PRE:+PRE_}COMPSET.GRID.MACHINE.COMPILER${NTASKS:+.NTASKS}"
for C in ${C_SUITES[@]}; do
for R in ${RESS[@]}; do
  printf "        %s%s.mpasa%03d.%s.%s%s\n" "${PRE:+${PRE}_}" "$COMP" "$R" "$MACH" "$C" "${NTASKS:+.$NTASKS}"
done
done
echo -e "-------------------------------------------------------------------------\n\n"


###############################################################################
# Setup enviornment: load modules, set system paths, etc
###############################################################################
module load python/3     # Python 3 is needed by CIME

[ ! -d $CASES_DIR ] && "mkdir -p $CASES_ROOT"
# End Setup environment #######################################################


for C_SUITE in ${C_SUITES[@]}; do
for RES in ${RESS[@]}; do
  #############################################################################
  # End Set loop vars
  #############################################################################
  CASE=$(printf "%s%s.mpasa%03d.%s.%s%s" "${PRE:+${PRE}_}" "$COMP" "$R" "$MACH" "$C" "${NTASKS:+.$NTASKS}")
  CASEROOT="${CASES_DIR}/${CASE}"
  GRID=$(printf "mpasa%03d_mpasa%03d" $RES $RES)
  echo -e "--- Start loop for $CASE ---\n"

  case $RES in
    120)
      ATM_BLCK_PRE="/glade/u/home/gdicker/mpas_resources/meshes/x1.40962_mesh/x1.40962.graph.info.part."
      ;;
    60)
      ATM_BLCK_PRE="/glade/u/home/gdicker/mpas_resources/meshes/x1.163842_mesh/x1.163842.graph.info.part."
      ;;
    30)
      ATM_BLCK_PRE="/glade/u/home/gdicker/mpas_resources/meshes/x1.655362_mesh/x1.655362.graph.info.part."
      ;;
    *)
      echo -e "ERROR: value '$RES' is not a valid resolution"
      continue
      ;;
  esac
  LEN_DISP=$(printf "%d000" $RES)
  ATM_DT="$(( 900 / (120 / $RES) )).0D0"  # DT is set relative to the 120km resolution
  # End Set loop vars #########################################################

  if [ "$DO_CREATE" = true ]; then
    ###########################################################################
    # Create case:
    ###########################################################################
    if [ "$OVERWRITE" = true ]; then vexec "rm -rf $CASEROOT $TMPDIR/$CASE/"; fi
    CCMD="$SRCROOT/cime/scripts/create_newcase"
    CCMD="$CCMD --case $CASEROOT --project $A_KEY"
    CCMD="$CCMD --compiler $C_SUITE --res $GRID --compset ${COMP_LONG:-$COMP}"
    CCMD="$CCMD --driver nuopc --run-unsupported"
    [ -z $NTASKS ] || CCMD="$CCMD --pecount $NTASKS"

    vexec "$CCMD"
    if [ "$?" -ne 0 ]; then
      echo "ERROR: create_newcase failed"
      exit 1
    fi
    # End Create case #########################################################


    ###########################################################################
    # Setup case: change XML variables, edit namelists, case.setup
    ###########################################################################
    cd $CASEROOT
    ./xmlchange CAM_CONFIG_OPTS="-phys held_suarez -analytic_ic -nlev 32"
    ./xmlchange DOUT_S=false
    ./xmlchange STOP_OPTION=ndays
    ./xmlchange STOP_N=10

cat << __EOF_NL_CAM >> user_nl_cam
mpas_block_decomp_file_prefix = '$ATM_BLCK_PRE'
mpas_len_disp = $LEN_DISP
mpas_dt = $ATM_DT
__EOF_NL_CAM

    if [ $VERBOSITY -ge 2 ] ; then
      vexec "cat user_nl_cam"
    fi

    vexec "./case.setup"
    if [ "$?" -ne 0 ]; then
      echo "ERROR: case.setup failed"
      exit 1
    fi
    # End Setup case ##########################################################
  fi # DO_CREATE


  if [ "$DO_BUILD" = true ]; then
    ###########################################################################
    # Build case: Start job to build case
    ###########################################################################
    cd $CASEROOT
    vexec "qcmd -A $A_KEY -- ./case.build --skip-provenance-check"
    if [ "$?" -ne 0 ]; then
      echo "ERROR: case.build failed"
      exit 1
    fi
    # End Build case ##########################################################
  fi # DO_BUILD


  if [ "$DO_RUN" = true ]; then
    ###########################################################################
    # Run case:
    ###########################################################################
    cd $CASEROOT
    vexec "./check_input_data"

    vexec "./case.submit"
    if [ "$?" -ne 0 ]; then
      echo "ERROR: case.submit failed"
      exit 1
    fi
    # End Run case ############################################################
  fi # DO_RUN

  echo -e "--- End loop for $CASE ---\n"
done #for RES in $RESS
done # for C_SUITE in $C_SUITES
