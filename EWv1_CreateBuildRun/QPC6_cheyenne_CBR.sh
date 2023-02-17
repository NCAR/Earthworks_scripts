#!/usr/bin/env bash
THIS_FILE="QPC6_cheyenne_CBR.sh"
# This script allows for easy creation of QPC6 cases on the Cheyenne
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
OUTPUTROOT="$TMPDIR"
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
# Remove any CASEROOTS before anything else in create section
OVERWRITE=false

## Other configuration variables
COMP="QPC6"
MACH="cheyenne"
A_KEY="UCSU0085"
PRE="" # Case prefix for uniqueness
STOP_OPT=ndays    # For STOP_OPTION xml variable in a case
STOP_N=10         # For STOP_N xml variables in a case
# End EDIT HERE ###############################################################


# Bring in helper functions, parse command-line arguments and print run info
source $(dirname "$0")/helper_funcs.sh


###############################################################################
# Setup enviornment: load modules, set system paths, etc
###############################################################################
module load python/3     # Python 3 is needed by CIME

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
      # [ $NTASKS -eq 0 ] && NTASKS="36"
      ATM_BLCK_PRE="/glade/u/home/gdicker/mpas_resources/meshes/x1.40962_mesh/x1.40962.graph.info.part."
      ATM_NCDATA="/glade/p/cesmdata/cseg/inputdata/atm/cam/inic/mpas/mpasa120_L32_notopo_coords_c201216.nc"
      ATM_SRF=""
      ATM_DT="450.0D0"
      ;;
    60)
      [ $NTASKS -eq 0 ] && NTASKS="$((36*4))"
      ATM_BLCK_PRE="/glade/u/home/gdicker/mpas_resources/meshes/x1.163842_mesh/x1.163842.graph.info.part."
      ATM_NCDATA="/glade/p/cesmdata/cseg/inputdata/atm/cam/inic/mpas/mpasa60_L32_notopo_coords_c211118.nc"
      ATM_SRF="/glade/p/cesmdata/cseg/inputdata/atm/cam/chem/trop_mam/atmsrf_mpasa60_c210511.nc"
      ATM_DT="225.0D0"
      ;;
    30)
      [ $NTASKS -eq 0 ] && NTASKS="$((36*16))"
      ATM_BLCK_PRE="/glade/u/home/gdicker/mpas_resources/meshes/x1.655362_mesh/x1.655362.graph.info.part."
      ATM_NCDATA="/glade/p/cesmdata/cseg/inputdata/atm/cam/inic/mpas/mpasa30_L32_notopo_coords_c211118.nc"
      ATM_SRF="/glade/p/cesmdata/cseg/inputdata/atm/cam/chem/trop_mam/atmsrf_mpasa30_c210601.nc"
      ATM_DT="120.0D0" # Closest factor of cam_dt (1800) to 112.5
      ;;
    *)
      echo -e "ERROR: value '$RES' is not a valid resolution"
      continue
      ;;
  esac
  LEN_DISP=$(printf "%d000" $RES)
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
    ./xmlchange CAM_CONFIG_OPTS="-analytic_ic -nlev 32"
    ./xmlchange DOUT_S=false
    ./xmlchange STOP_OPTION=$STOP_OPT
    ./xmlchange STOP_N=$STOP_N

cat << __EOF_NL_CAM >> user_nl_cam
${ATM_SRF:+drydep_srf_file = '$ATM_SRF'}
mpas_block_decomp_file_prefix = '$ATM_BLCK_PRE'
mpas_len_disp = $LEN_DISP
&camexp
 analytic_ic_type= 'us_standard_atmosphere'
 ${ATM_NCDATA:+ncdata = '$ATM_NCDATA'}
 mpas_dt = $ATM_DT
/

__EOF_NL_CAM

    if [ $VERBOSITY -ge 2 ] ; then
      vexec "cat user_nl_cam"
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
    vexec "qcmd -A $A_KEY -- ./case.build --skip-provenance-check"
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
