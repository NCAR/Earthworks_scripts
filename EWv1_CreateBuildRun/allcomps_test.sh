#!/usr/bin/env bash

# Intended to be run:
# bash allcomps_test.sh 2>&1 | tee log.attXX.txt

COMPS=("FHS94" "FKESSLER" "F2000climo" "QPC6" "FullyCoupled")
# Edit these paths to whatever works for you
# Assumes script is in "EarthWorks/tools/Earthworks_scripts/EWv1_CreateBuildRun"
SRCROOT="$(realpath ${PWD}/../../../)" # Points to EarthWorks
CSEROOT="$(realpath ${PWD}/../../../../cases)"
[ -d "${CSEROOT}" ] || mkdir -p "${CSEROOT}"
# Adjust case prefix to whatever makes sense for you
PRE="$(date +%Y%b%d_%H%M%S)_alpha16dUpdate"

#CMD="_cheyenne_CBR.sh --srcroot ${SRCROOT} --casesdir ${CSEROOT} --res=(120 60 30) --compiler=(gnu intel) -cp ${PRE} "
CMD="_cheyenne_CBR.sh --srcroot ${SRCROOT} --casesdir ${CSEROOT} --res=120 --compiler=(gnu intel) -cp ${PRE} "

## # Un-comment this section to do a dry run
## for C in ${COMPS[@]}; do
## 	CCMD="${C}${CMD}"
## 	LG_FILE="log.dryrun.${PRE}.${C}.txt"
## 	./${CCMD} -dr 2>&1 | tee $LG_FILE
## done
## exit $?

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
