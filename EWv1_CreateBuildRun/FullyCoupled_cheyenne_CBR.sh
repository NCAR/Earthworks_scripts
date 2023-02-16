#!/usr/bin/env bash
THIS_FILE="FullyCoupled_cheyenne_CBR.sh"
# This script allows for easy creation of FullyCoupled cases on the Cheyenne
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
COMP="FullyCoupled"
COMP_LONG="2000_CAM60_CLM50%SP_MPASSI_MPASO_SROF_SGLC_SWAV"
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
  GRID=$(printf "mpasa%03d_oQU%03d" $RES $RES)
  echo -e "--- Start loop for $CASE ---\n"

  case $RES in
    120)
      [ $NTASKS -eq 0 ] && NTASKS="144"
      ATM_DMN_MESH="/glade/p/cesmdata/cseg/inputdata/atm/cam/coords/mpasa120_ESMF_desc.200911.nc"
      ATM_BLCK_PRE="/glade/u/home/gdicker/mpas_resources/meshes/x1.40962_mesh/x1.40962.graph.info.part."
      ATM_NCDATA="/glade/p/univ/ucsu0085/inputdata/cami_01-01-2000_00Z_mpasa120_L32_CFSR_c210426.nc"
      ATM_SRF=""
      ATM_BND=""
      OCN_BLCK_PRE="/glade/p/univ/ucsu0085/inputdata/mpas-o.graph.info.QU120.part."
      LND_DMN_MESH="/glade/p/cesmdata/cseg/inputdata/atm/cam/coords/mpasa120_ESMF_desc.200911.nc"
      LND_FSUR="/glade/p/cesmdata/cseg/inputdata/lnd/clm2/surfdata_map/surfdata_mpasa120_hist_78pfts_CMIP6_simyr2000_c211108.nc"

      ATM_NCPL=48
      ATM_DT="600.0D0"
      OCN_CONFIG_DT="00:30:00"
      SI_CONFIG_DT="1800.0D0"
      ;;
    60)
      [ $NTASKS -eq 0 ] && NTASKS="$((144*4))"
      ATM_DMN_MESH="/glade/p/cesmdata/cseg/inputdata/share/meshes/mpasa60_ESMFmesh-20210803.nc"
      ATM_BLCK_PRE="/glade/u/home/gdicker/mpas_resources/meshes/x1.163842_mesh/x1.163842.graph.info.part."
      ATM_NCDATA="/glade/p/univ/ucsu0085/inputdata/cami_01-01-2000_00Z_mpasa60_L32_CFSR_c210518.nc"
      ATM_SRF="/glade/p/cesmdata/cseg/inputdata/atm/cam/chem/trop_mam/atmsrf_mpasa30_c210601.nc"
      ATM_BND="/glade/p/cesmdata/cseg/inputdata/atm/cam/topo/mpas_60_nc3000_Co030_Fi001_MulG_PF_Nsw021.nc"
      LND_DMN_MESH="/glade/p/cesmdata/cseg/inputdata/share/meshes/mpasa60_ESMFmesh-20210803.nc"
      LND_FSUR="/glade/p/cesmdata/cseg/inputdata/lnd/clm2/surfdata_map/surfdata_mpasa60_hist_78pfts_CMIP6_simyr2000_c211110.nc"
      
      ATM_NCPL=144
      ATM_DT="300.0D0"
      OCN_CONFIG_DT="00:10:00"
      SI_CONFIG_DT="600.0D0"
      ;;
    30)
      [ $NTASKS -eq 0 ] && NTASKS="$((144*16))"
      ATM_DMN_MESH="/glade/p/cesmdata/cseg/inputdata/share/meshes/mpasa30_ESMFmesh-20210803.nc"
      ATM_BLCK_PRE="/glade/u/home/gdicker/mpas_resources/meshes/x1.655362_mesh/x1.655362.graph.info.part."
      ATM_NCDATA="/glade/p/cesmdata/cseg/inputdata/atm/cam/inic/mpas/mpasa30_L32_CFSR_c210611.nc"
      ATM_SRF="/glade/p/cesmdata/cseg/inputdata/atm/cam/chem/trop_mam/atmsrf_mpasa60_c210511.nc"
      ATM_BND="/glade/p/cesmdata/cseg/inputdata/atm/cam/topo/mpas_30_nc3000_Co015_Fi001_MulG_PF_Nsw011.nc"
      LND_DMN_MESH="/glade/p/cesmdata/cseg/inputdata/share/meshes/mpasa30_ESMFmesh-20210803.nc"
      LND_FSUR="/glade/p/cesmdata/cseg/inputdata/lnd/clm2/surfdata_map/surfdata_mpasa30_hist_78pfts_CMIP6_simyr2000_c211111.nc"
      
      ATM_NCPL=240
      ATM_DT="180.0D0"
      OCN_CONFIG_DT="00:06:00"
      SI_CONFIG_DT="360.0D0"
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
    ./xmlchange CAM_CONFIG_OPTS="-dyn mpas"
    ./xmlchange DOUT_S=false
    ./xmlchange DEBUG=false
    ./xmlchange REST_OPTION='ndays'
    ./xmlchange REST_N=1
    ./xmlchange STOP_OPTION=$STOP_OPT
    ./xmlchange STOP_N=$STOP_N
    # Run type options
    ./xmlchange RUN_TYPE=hybrid
    ./xmlchange RUN_REFCASE=$(printf "mpas_aos%03d" $RES)
    ./xmlchange RUN_REFDATE=0002-01-01
    ./xmlchange RUN_STARTDATE=0002-01-01
    # Define mesh files
    ./xmlchange OCN_DOMAIN_MESH="/glade/p/univ/ucsu0085/inputdata/oQU${RES}_ESMFmesh.nc"
    ./xmlchange ICE_DOMAIN_MESH="/glade/p/univ/ucsu0085/inputdata/oQU${RES}_ESMFmesh.nc"
    ./xmlchange MASK_MESH="/glade/p/univ/ucsu0085/inputdata/oQU${RES}_ESMFmesh.nc"
    ./xmlchange ATM_DOMAIN_MESH="${ATM_DMN_MESH}"
    ./xmlchange LND_DOMAIN_MESH="${LND_DMN_MESH}"
    ./xmlchange NCPL_BASE_PERIOD='day'
    ./xmlchange ATM_NCPL=$ATM_NCPL

    # Copy the rst file
    [ ! -d ${OUTPUTROOT}/${CASE}/run ] && mkdir -p ${OUTPUTROOT}/${CASE}/run
    RST_DIR="$(printf '/glade/p/univ/ucsu0085/rst_aos_%03dkm' ${RES})"
    vexec "cp ${RST_DIR}/* ${OUTPUTROOT}/${CASE}/run/" 

cat << __EOF_NL_CAM >> user_nl_cam
ncdata = '$ATM_NCDATA'
${ATM_SRF:+drydep_srf_file = '$ATM_SRF'}
${ATM_BND:+bnd_topo = '$ATM_BND'}
mpas_block_decomp_file_prefix = '$ATM_BLCK_PRE'
mpas_len_disp = $LEN_DISP
mpas_dt = $ATM_DT
fincl1 = 'PRECT','vorticity'
__EOF_NL_CAM

cat << __EOF_NL_OCN >> user_nl_mpaso
&decomposition
 config_block_decomp_file_prefix = '/glade/p/univ/ucsu0085/inputdata/mpas-o.graph.info.QU${RES}.part.'
 config_proc_decomp_file_prefix = 'graph.info.part.'
/
&time_integration
 config_dt = '$OCN_CONFIG_DT'
 config_time_integrator = 'split_explicit'
/
__EOF_NL_OCN

cat << __EOF_NL_SI >> user_nl_mpassi
&decomposition
 config_block_decomp_file_prefix = '/glade/p/univ/ucsu0085/inputdata/mpas-o.graph.info.QU${RES}.part.'
 config_proc_decomp_file_prefix = 'graph.info.part.'
/
&seaice_model
 config_dt = $SI_CONFIG_DT
/
__EOF_NL_SI

cat << __EOF_NL_CLM >> user_nl_clm
fsurdat = '$LND_FSUR'
__EOF_NL_CLM

    if [ $VERBOSITY -ge 2 ] ; then
      vexec "cat user_nl_cam"
      vexec "cat user_nl_mpaso"
      vexec "cat user_nl_mpassi"
      vexec "cat user_nl_clm"
      echo ""
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
