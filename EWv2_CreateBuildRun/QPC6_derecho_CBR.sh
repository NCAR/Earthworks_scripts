#!/usr/bin/env bash
THIS_FILE="QPC6_derecho_CBR.sh"
# This script allows for easy creation of QPC6 cases on the Derecho
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
# Location where case's bld and run directory will be created
OUTPUTROOT="${SCRATCH}"
# For compiler, provide an array of valid compilers in C_SUITES
C_SUITES="intel"
# For resolutions, provide an array of valid CESM grids in the RESS variable
RESS="120"
# For pecount, provide an array of valid CESM pecounts in the NTASKSS variable
NTASKSS=""

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
# Use RESUBMIT to do a restart run
DO_RESTART=false
# Remove any CASEROOTS before anything else in create section
OVERWRITE=false

## Other configuration variables
COMP="QPC6"
MACH="derecho"
A_KEY="UCSU0085"
# These can be unset to not use them in the create_newcase
unset GPU_PER_NODE GPU_TYPE GPU_OFFLOAD
# OR request GPUs by using --gpus or uncommenting these lines
## GPU_PER_NODE="4"
## GPU_TYPE="a100"
## GPU_OFFLOAD="openacc"
PRE="" # Case prefix for uniqueness
STOP_OPT=ndays    # For STOP_OPTION xml variable in a case
STOP_N=10         # For STOP_N xml variables in a case
INPUTDATA="/glade/campaign/univ/ucsu0085/inputdata/"      # To look for other needed files
# Physics columns per MPI task adjust at your own risk!
# If you don't set this to a positive integer, CPU runs will use the default and
#  GPU runs will be set according to resolution, nodes, and number of GPUs
PCOLS="-1"
# End EDIT HERE ###############################################################


# Bring in helper functions, parse command-line arguments and print run info
source $(dirname "$0")/helper_funcs.sh


###############################################################################
# Setup enviornment: load modules, set system paths, etc
###############################################################################

[ ! -d $CASES_DIR ] && "mkdir -p $CASES_ROOT"
# End Setup environment #######################################################


for C_SUITE in ${C_SUITES[@]}; do
for RES in ${RESS[@]}; do
for NTASKS in ${NTASKSS[@]:-"0"}; do
  #############################################################################
  # End Set loop vars
  #############################################################################
  CASE=$(printf "%s%s.mpasa%03d.%s.%s" "${PRE:+${PRE}_}" "$COMP" "$RES" "$MACH" "$C_SUITE")
  [ $NTASKS -ne 0 ] && CASE="${CASE}.${NTASKS}"
  CASEROOT="${CASES_DIR}/${CASE}"
  GRID=$(printf "mpasa%03d_mpasa%03d" $RES $RES)
  echo -e "--- Start loop for $CASE ---\n"

  case $RES in
    120)
      [ $NTASKS -eq 0 ] && NTASKS="64"
      NCELLS=40962
      ;;
    60)
      [ $NTASKS -eq 0 ] && NTASKS="$((64*2))"
      NCELLS=163842
      ;;
    30)
      [ $NTASKS -eq 0 ] && NTASKS="$((64*4))"
      NCELLS=655362
      ;;
    15)
      [ $NTASKS -eq 0 ] && NTASKS="$((64*16))"
      NCELLS=2621442
      ;;
    *)
      echo -e "ERROR: value '$RES' is not a valid resolution"
      continue
      ;;
  esac
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
    CCMD="$CCMD -i ${INPUTDATA}"
    if [ -n "${GPU_PER_NODE}" ]; then
      if [ "nvhpc" == "$C_SUITE" ] ; then
        CCMD="$CCMD --ngpus-per-node $GPU_PER_NODE --gpu-type $GPU_TYPE --gpu-offload $GPU_OFFLOAD"
      else
        echo "NOTE: GPU flags only make sense for nvhpc compiler; not adding GPU flags to create_newcase for C_SUITE=${C_SUITE}"
      fi
    fi
    [ $NTASKS -ne 0 ] && CCMD="$CCMD --pecount $NTASKS"

    vexec "$CCMD"
    if [ "$?" -ne 0 ]; then
      echo "ERROR: create_newcase failed"
      echo -e "--- End loop for $CASE ---\n"
      continue
    fi
    # End Create case #########################################################


    ###########################################################################
    # Setup case: change XML variables, edit namelists, case.setup
    ###########################################################################
    cd $CASEROOT
    ./xmlchange --append CAM_CONFIG_OPTS="-analytic_ic -nlev 32"
    ./xmlchange DOUT_S=false
    ./xmlchange STOP_OPTION=$STOP_OPT
    ./xmlchange STOP_N=$STOP_N
    if [ "$DO_RESTART" = true ]; then
      ./xmlchange REST_OPTION=$STOP_OPT,REST_N=$STOP_N,RESUBMIT=1
    fi


    vexec "./case.setup"
    if [ "$?" -ne 0 ]; then
      echo "ERROR: case.setup failed"
      echo -e "--- End loop for $CASE ---\n"
      continue
    fi

    # Automatically set PCOLS if not already defined or if not greater than 0
    if [ -z "$PCOLS" -o "0" -ge "$PCOLS" ] ; then
      PCOLS=$(get_pcols)
    fi
    # Now only add pcols to CAM_CONFIG_OPTS if PCOLS and NGPUS_PER_NODE greater than 0
    if [ "0" -lt "$PCOLS" -a "0" -lt "${NGPUS_PER_NODE}" ] ; then
      echo "NOTE: setting pcols to \"$PCOLS\" for GPU run"
      ./xmlchange --append CAM_CONFIG_OPTS=" -pcols $PCOLS"
    fi

    # End Setup case ##########################################################
  fi # DO_CREATE


  if [ "$DO_BUILD" = true ]; then
    ###########################################################################
    # Build case: Start job to build case
    ###########################################################################
    cd $CASEROOT
    if [ -n "${GPU_PER_NODE}" ] && [ "nvhpc" == "${C_SUITE}" ] ; then
        vexec "qcmd -A $A_KEY -l select=1:ngpus=1 -- ./case.build --skip-provenance-check"
    else
        vexec "qcmd -A $A_KEY -- ./case.build --skip-provenance-check"
    fi
    if [ "$?" -ne 0 ]; then
      echo "ERROR: case.build failed"
      echo -e "--- End loop for $CASE ---\n"
      continue
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
      echo -e "--- End loop for $CASE ---\n"
      continue
    fi
    # End Run case ############################################################
  fi # DO_RUN

  echo -e "--- End loop for $CASE ---\n"
done #for NTASKS in NTASKSS
done #for RES in $RESS
done # for C_SUITE in $C_SUITES
