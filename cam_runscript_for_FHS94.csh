#!/bin/csh

set echo verbose

date

set compile_model    = 1        # 0 = No, >0 = Yes
set run_model        = 1        # 0 = No, >0 = Yes
set user             = ssuresh 
set scratch          = /glade/scratch/$user
set work             = /glade/work/$user/earthworks/cpu_che
set account_key      = UCSU0085

foreach n (32,64)                  # MPI tasks

####################################################################
# Machine, compset, PE layout etc.
####################################################################
setenv GITREPO       my_cesm_sandbox
setenv CCSMROOT      $scratch/$GITREPO
setenv ntasks        $n
setenv nthrds        1
setenv CASE          FHS94.mpas120.cheyenne.intel.$n.test
setenv CASEROOT      $scratch/earthworks/$CASE
setenv PTMP          $scratch/earthworks_run/$CASE

####################################################################
# Compile model
####################################################################

if ($compile_model > 0) then

   rm -rf $CASEROOT

   cd $CCSMROOT/cime/scripts

   ./create_newcase --case $CASEROOT --mach cheyenne --project $account_key \
                    --res mpasa120_mpasa120 --compset FHS94 --compiler intel \
                    --run-unsupported --pecount $n

####################################################################
# set up case
####################################################################

   cd $CASEROOT

   ./xmlchange CAM_CONFIG_OPTS="-phys held_suarez -analytic_ic -nlev 32"
   ./xmlchange DOUT_S=false
   ./xmlchange MAX_MPITASKS_PER_NODE=32
   ./xmlchange MAX_TASKS_PER_NODE=32
   ./xmlchange STOP_OPTION=ndays
   ./xmlchange STOP_N=10

   ./xmlchange --file env_run.xml      --id RUNDIR     --val $PTMP/run
   ./xmlchange --file env_build.xml    --id EXEROOT    --val $PTMP/bld

   ./case.setup

####################################################################
# build CAM
####################################################################

   qcmd -A $account_key -- ./case.build --skip-provenance-check
   #./case.build --skip-provenance-check

endif

#####################################################################
# Conduct simulation
#####################################################################

if ($run_model > 0) then

   cd $CASEROOT

   ./case.submit

endif

end # loop of different MPI tasks
