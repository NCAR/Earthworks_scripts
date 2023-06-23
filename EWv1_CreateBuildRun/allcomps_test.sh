#!/usr/bin/env bash

COMPS=("FHS94" "FKESSLER" "F2000climo" "QPC6" "FullyCoupled")
# Edit these paths to whatever works for you
SRCROOT="/glade/work/gdicker/EarthWorks/2023Jun22_Beta14Update/EarthWorks"
CSEROOT="/glade/work/gdicker/EarthWorks/2023Jun22_Beta14Update/cases"
# Adjust case prefix to whatever makes sense for you
PRE="$(date +%Y%b%d_%H%M%S)"

#CMD="_cheyenne_CBR.sh --srcroot ${SRCROOT} --casesdir ${CSEROOT} --res=(120 60 30) --compiler=(gnu intel) -cp ${PRE} "
CMD="_cheyenne_CBR.sh --srcroot ${SRCROOT} --casesdir ${CSEROOT} --res=120 --compiler=gnu -cp ${PRE} "

#GDD# # Un-comment this to do a dry run
#GDD# for C in ${COMPS[@]}; do
#GDD# 	CCMD="${C}${CMD}"
#GDD# 	LG_FILE="log.dryrun.${PRE}.${C}.txt"
#GDD# 	./${CCMD} -dr 2>&1 | tee $LG_FILE
#GDD# done
#GDD# exit $?

# Run the setup steps for each
for C in ${COMPS[@]}; do
	CCMD="${C}${CMD}"
	LG_FILE="log.setup.${PRE}.${C}.txt"
	./${CCMD} -nb -nr 2>&1 | tee $LG_FILE
done

# Run the build and then submit steps for each
for C in ${COMPS[@]}; do
	CCMD="${C}${CMD}"
	LG_FILE="log.buildrun.${PRE}.${C}.txt"
	./${CCMD} -nc 2>&1 | tee $LG_FILE
done
