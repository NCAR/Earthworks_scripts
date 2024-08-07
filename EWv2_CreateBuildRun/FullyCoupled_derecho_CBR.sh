#!/usr/bin/env bash
THIS_FILE="FullyCoupled_derecho_CBR.sh"
# This script allows for easy creation of FullyCoupled cases on the Derecho
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
COMP="FullyCoupled"
COMP_LONG="2000_CAM60_CLM50%SP_MPASSI_MPASO_SROF_SGLC_SWAV"
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
  GRID=$(printf "mpasa%03d_oQU%03d" $RES $RES)
  echo -e "--- Start loop for $CASE ---\n"

  case $RES in
    120)
      [ $NTASKS -eq 0 ] && NTASKS="128"
      NCELLS=40962

      ATM_NCPL=48
      ATM_DT="600.0D0"
      OCN_CONFIG_DT="00:30:00"
      SI_CONFIG_DT="1800.0D0"

      OCN_MOC_ENABLE=".true."
      OCN_USE_GM=".true."
      OCN_USE_REDI=".true."
      ;;
    60)
      [ $NTASKS -eq 0 ] && NTASKS="$((128*4))"
      NCELLS=163842
      
      ATM_NCPL=96
      ATM_DT="300.0D0"
      OCN_CONFIG_DT="00:15:00"
      SI_CONFIG_DT="900.0D0"

      OCN_MOC_ENABLE=".true."
      OCN_USE_GM=".true."
      OCN_USE_REDI=".true."
      ;;
    30)
      [ $NTASKS -eq 0 ] && NTASKS="$((128*16))"
      NCELLS=655362
      
      ATM_NCPL=192
      ATM_DT="225.0D0"
      OCN_CONFIG_DT="00:07:30"
      SI_CONFIG_DT="450.0D0"

      OCN_MOC_ENABLE=".false."
      OCN_USE_GM=".true."
      OCN_USE_REDI=".true."
      ;;
    15)
      [ $NTASKS -eq 0 ] && NTASKS="$((128*32))"
      NCELLS=2621442

      ATM_NCPL=240
      ATM_DT="120.0D0"
      OCN_CONFIG_DT="00:04:00"
      SI_CONFIG_DT="240.0D0"

      OCN_MOC_ENABLE=".false."
      OCN_USE_GM=".false."
      OCN_USE_REDI=".false."
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
    ./xmlchange --append CAM_CONFIG_OPTS="-dyn mpas"
    ./xmlchange DOUT_S=false
    ./xmlchange DEBUG=false
    ./xmlchange STOP_OPTION=$STOP_OPT
    ./xmlchange STOP_N=$STOP_N
    if [ "$DO_RESTART" = true ]; then
      ./xmlchange REST_OPTION=$STOP_OPT,REST_N=$STOP_N,RESUBMIT=1
    else
      ./xmlchange REST_OPTION='ndays',REST_N=1
    fi
    # Run type options
    ./xmlchange NCPL_BASE_PERIOD='day'
    ./xmlchange ATM_NCPL=$ATM_NCPL


cat << __EOF_NL_CAM >> user_nl_cam
mpas_dt = $ATM_DT
__EOF_NL_CAM

cat << __EOF_NL_OCN >> user_nl_mpaso
&time_integration
 config_dt = '$OCN_CONFIG_DT'
 config_time_integrator = 'split_explicit'
/

config_am_mocstreamfunction_enable = ${OCN_MOC_ENABLE}
config_use_gm = ${OCN_USE_GM}
config_use_redi = ${OCN_USE_REDI}

config_cvmix_kpp_use_theory_wave = .true.
config_am_mocstreamfunction_compute_interval = '0000-00-00_01:00:00'
config_am_mocstreamfunction_compute_on_startup = .false.
config_am_mocstreamfunction_max_bin = -1.0e34
config_am_mocstreamfunction_min_bin = -1.0e34
config_am_mocstreamfunction_num_bins = 180
config_am_mocstreamfunction_output_stream = 'mocStreamfunctionOutput'
config_am_mocstreamfunction_region_group = 'all'
config_am_mocstreamfunction_transect_group = 'all'
config_am_mocstreamfunction_write_on_startup = .false.
__EOF_NL_OCN

cat << __EOF_NL_SI >> user_nl_mpassi
&seaice_model
 config_dt = $SI_CONFIG_DT
/
config_initial_latitude_north = 90.0
config_initial_latitude_south = -90.0
__EOF_NL_SI

    if [ $VERBOSITY -ge 2 ] ; then
      vexec "cat user_nl_cam"
      vexec "cat user_nl_mpaso"
      vexec "cat user_nl_mpassi"
      echo ""
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
