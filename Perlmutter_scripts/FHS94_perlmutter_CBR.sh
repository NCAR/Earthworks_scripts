#!/usr/bin/env bash
THIS_FILE="FHS94_perlmutter_CBR.sh"
# This script allows for easy creation of FHS94 cases on the Derecho
# Supercomputer using an already downloaded copy of the EarthWorks repo. Users
# should edit the desired sections to create/compiler/run their desired tests.
# Consult the `usage` function below or run this  with --help for more info.

 #Eg: ./FHS94_perlmutter_CBR.sh -ow -cp mpas_gpu_ew_test_jan31 --res=120 --compiler=nvhpc --srcroot ../../EarthWorks/ --casesdir ../../cases
###############################################################################
# EDIT HERE for easy customization of default values
###############################################################################
# Location of the EarthWorks clone to use
SRCROOT="../ew_cam_137"
# Location to put cases and cases_out directories
CASES_DIR="../cases/"
# Location where case's bld and run directory will be created
OUTPUTROOT="${SCRATCH}"
# For compiler, provide an array of valid compilers in C_SUITES
C_SUITES="nvhpc"
# For resolutions, provide an array of valid CESM grids in the RESS variable
RESS="60"
# For pecount, provide an array of valid CESM pecounts in the NTASKSS variable
NTASKSS="64"

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
COMP="FHS94"
MACH="perlmutter"
A_KEY="m4180"
#GPUS_PER_NODE="1"
#GPU_TYPE="a100"
#GPU_OFFLOAD="openacc"
PRE="" # Case prefix for uniqueness
STOP_OPT=ndays    # For STOP_OPTION xml variable in a case
STOP_N=10         # For STOP_N xml variables in a case
INPUTDATA="/pscratch/sd/s/ssuresh/inputdata"      # To look for other needed files
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
      ;;
    60)
      [ $NTASKS -eq 0 ] && NTASKS="$((64*2))"
      ;;
    30)
      [ $NTASKS -eq 0 ] && NTASKS="$((64*4))"
      ;;
    15)
      [ $NTASKS -eq 0 ] && NTASKS="$((64*16))"
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
    CCMD="$CCMD --case $CASEROOT --project $A_KEY --mach $MACH"
    CCMD="$CCMD --compiler $C_SUITE --res $GRID --compset ${COMP_LONG:-$COMP}"
    #CCMD="$CCMD --ngpus-per-node $GPUS_PER_NODE --gpu-type $GPU_TYPE --gpu-offload $GPU_OFFLOAD"
    CCMD="$CCMD --driver nuopc --run-unsupported"
    CCMD="$CCMD -i ${INPUTDATA}"
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
    # End Setup case ##########################################################
  fi # DO_CREATE


  if [ "$DO_BUILD" = true ]; then
    ###########################################################################
    # Build case: Start job to build case
    ###########################################################################
    cd $CASEROOT
    vexec "./case.build --skip-provenance-check"
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
