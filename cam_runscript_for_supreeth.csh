#!/bin/csh

set echo verbose

date

set compile_model    = 1        # 0 = No, >0 = Yes
set run_model        = 1        # 0 = No, >0 = Yes
set user             = YOUR_NAME 
set scratch          = /glade/scratch/$user

foreach n (36)                  # MPI tasks

####################################################################
# Machine, compset, PE layout etc.
####################################################################
setenv GITREPO       ESCOMP_CAM 
setenv CCSMROOT      $scratch/$GITREPO
setenv ntasks        $n
setenv nthrds        1
setenv CASE          F2000climo.f09_f09_mg17.cheyenne.intel.test
setenv CASEROOT      $scratch/cam6/$CASE
setenv PTMP          $scratch/cam6_run/$CASE

####################################################################
# Compile model
####################################################################

if ($compile_model > 0) then

   rm -rf $CASEROOT

   cd $CCSMROOT/cime/scripts

   ./create_newcase --case $CASEROOT --mach cheyenne --project YOUR_PROJECT \
                    --res f09_f09_mg17 --compset F2000climo --compiler intel

####################################################################
# set up case
####################################################################

   cd $CASEROOT

   ./xmlchange --file env_run.xml      --id RUNDIR     --val $PTMP/run
   ./xmlchange --file env_build.xml    --id EXEROOT    --val $PTMP/bld

   ./xmlchange --file env_mach_pes.xml --id NTASKS_ATM --val $ntasks
   ./xmlchange --file env_mach_pes.xml --id NTHRDS_ATM --val $nthrds
   ./xmlchange --file env_mach_pes.xml --id ROOTPE_ATM --val '0'

   ./xmlchange --file env_mach_pes.xml --id NTASKS_LND --val $ntasks
   ./xmlchange --file env_mach_pes.xml --id NTHRDS_LND --val $nthrds
   ./xmlchange --file env_mach_pes.xml --id ROOTPE_LND --val '0'

   ./xmlchange --file env_mach_pes.xml --id NTASKS_ROF --val $ntasks
   ./xmlchange --file env_mach_pes.xml --id NTHRDS_ROF --val $nthrds
   ./xmlchange --file env_mach_pes.xml --id ROOTPE_ROF --val '0'

   ./xmlchange --file env_mach_pes.xml --id NTASKS_ICE --val $ntasks
   ./xmlchange --file env_mach_pes.xml --id NTHRDS_ICE --val $nthrds
   ./xmlchange --file env_mach_pes.xml --id ROOTPE_ICE --val '0'

   ./xmlchange --file env_mach_pes.xml --id NTASKS_OCN --val $ntasks
   ./xmlchange --file env_mach_pes.xml --id NTHRDS_OCN --val $nthrds
   ./xmlchange --file env_mach_pes.xml --id ROOTPE_OCN --val '0'

   ./xmlchange --file env_mach_pes.xml --id NTASKS_GLC --val $ntasks
   ./xmlchange --file env_mach_pes.xml --id NTHRDS_GLC --val $nthrds
   ./xmlchange --file env_mach_pes.xml --id ROOTPE_GLC --val '0'

   ./xmlchange --file env_mach_pes.xml --id NTASKS_WAV --val $ntasks
   ./xmlchange --file env_mach_pes.xml --id NTHRDS_WAV --val $nthrds
   ./xmlchange --file env_mach_pes.xml --id ROOTPE_WAV --val '0'

   ./xmlchange --file env_mach_pes.xml --id NTASKS_CPL --val $ntasks
   ./xmlchange --file env_mach_pes.xml --id NTHRDS_CPL --val $nthrds
   ./xmlchange --file env_mach_pes.xml --id ROOTPE_CPL --val '0'

   ./case.setup

####################################################################
# build CAM
####################################################################

   ./case.build

endif

#####################################################################
# Conduct simulation
#####################################################################

if ($run_model > 0) then

   cd $CASEROOT

   ./case.submit

endif

end # loop of different MPI tasks
