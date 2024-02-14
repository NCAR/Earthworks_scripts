#!/usr/bin/env bash
THIS_FILE="F2000climo_derecho_CBR.sh"
# This script allows for easy creation of F2000climo cases on the Derecho
# Supercomputer using an already downloaded copy of the EarthWorks repo. Users
# should edit the desired sections to create/compiler/run their desired tests.
# Consult the `usage` function below or run this  with --help for more info.


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
RESS="30"
# For pecount, provide an array of valid CESM pecounts in the NTASKSS variable
NTASKSS="512"

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
COMP="F2000climo"
MACH="derecho"
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
      # [ $NTASKS -eq 0 ] && NTASKS="36"
      ATM_BLCK_PRE="/pscratch/sd/s/ssuresh/inputdata/atm/cam/inic/mpas/mpasa120.graph.info.part."
      ATM_NCDATA="/pscratch/sd/s/ssuresh/inputdata/atm/cam/inic/mpas/cami_01-01-2000_00Z_mpasa120_L32_CFSR_c210426.nc"
      ATM_SRF=""
      ATM_BND=""
      ATM_DT="450.0D0"
      LND_DOMAIN="domain.lnd.mpasa120_gx1v7.201215.nc"
      LND_FSUR="/pscratch/sd/s/ssuresh/inputdata/lnd/clm2/surfdata_map/ctsm5.1.dev052/surfdata_mpasa120_hist_78pfts_CMIP6_simyr2000_c211108.nc"
      ;;
    60)
      #[ $NTASKS -eq 0 ] && NTASKS="$((36*5))"
      ATM_BLCK_PRE="/pscratch/sd/s/ssuresh/inputdata/atm/cam/inic/mpas/mpasa60.graph.info.part."
      ATM_NCDATA="/pscratch/sd/s/ssuresh/inputdata/atm/cam/inic/mpas/cami_01-01-2000_00Z_mpasa60_L32_CFSR_c210518.nc"
      ATM_SRF="/pscratch/sd/s/ssuresh/inputdata/atm/cam/chem/trop_mam/atmsrf_mpasa60_c210511.nc"
      ATM_BND="/pscratch/sd/s/ssuresh/inputdata/atm/cam/topo/mpas_60_nc3000_Co030_Fi001_MulG_PF_Nsw021.nc"
      ATM_DT="225.0D0"
      LND_DOMAIN="domain.lnd.mpasa60_gx1v7.210716.nc"
      LND_FSUR="/pscratch/sd/s/ssuresh/inputdata/lnd/clm2/surfdata_map/ctsm5.1.dev052/surfdata_mpasa60_hist_78pfts_CMIP6_simyr2000_c211110.nc"
      ;;
    30)
      #[ $NTASKS -eq 0 ] && NTASKS="$((36*16))"
      ATM_BLCK_PRE="/pscratch/sd/s/ssuresh/inputdata/atm/cam/inic/mpas/mpasa30.graph.info.part."
      ATM_NCDATA="/pscratch/sd/s/ssuresh/inputdata/atm/cam/inic/mpas/cami_01-01-2000_00Z_mpasa30_L32_CFSR_230302.nc"
      ATM_SRF="/pscratch/sd/s/ssuresh/inputdata/atm/cam/chem/trop_mam/atmsrf_mpasa30_c210601.nc"
      ATM_BND="/pscratch/sd/s/ssuresh/inputdata/atm/cam/topo/mpas_30_nc3000_Co015_Fi001_MulG_PF_Nsw011.nc"
      ATM_DT="120.0D0" # Closest factor of cam_dt (1800) to 112.5
      LND_DOMAIN="domain.lnd.mpasa30_gx1v7.210601.nc"
      LND_FSUR="/pscratch/sd/s/ssuresh/inputdata/lnd/clm2/surfdata_map/ctsm5.1.dev052/surfdata_mpasa30_hist_78pfts_CMIP6_simyr2000_c211111.nc"
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
    ./xmlchange DOUT_S=false
    ./xmlchange STOP_OPTION=$STOP_OPT
    ./xmlchange STOP_N=$STOP_N
    # ./xmlchange LND_DOMAIN_FILE=${LND_DOMAIN}

cat << __EOF_NL_CAM >> user_nl_cam
${ATM_SRF:+drydep_srf_file = '$ATM_SRF'}
${ATM_BND:+bnd_topo = '$ATM_BND'}
${ATM_NCDATA:+ncdata = '$ATM_NCDATA'}
mpas_block_decomp_file_prefix = '$ATM_BLCK_PRE'
mpas_len_disp = $LEN_DISP
&camexp
 mpas_dt = $ATM_DT
 scale_dry_air_mass = -1.0
 cldfrc_sh1 = 0.04
 dust_emis_fact = 0.70D0
 zmconv_ke = 5.0E-6
/
__EOF_NL_CAM

cat << __EOF_NL_CLM >> user_nl_clm
&camexp
  fsurdat = '$LND_FSUR'
/
__EOF_NL_CLM

    if [ $VERBOSITY -ge 2 ] ; then
      vexec "cat user_nl_cam"
      vexec "cat user_nl_clm"
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
    vexec ./case.build --skip-provenance-check
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
