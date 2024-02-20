#!/usr/bin/env bash

# Intended to be run:
# bash allcomps_test.sh 2>&1 | tee log.attXX.txt

RESS=("120" "60" "30" "15")
# RESS=("120")
COMPS=("FHS94" "FKESSLER" "F2000climo" "QPC6" "FullyCoupled")
# COMPS=("FullyCoupled")
COMPI=("nvhpc" "intel-oneapi" "gnu")

# Edit these paths to whatever works for you
# Assumes script is in "EarthWorks/tools/Earthworks_scripts/EWv1_CreateBuildRun"
SRCROOT="$(realpath ${PWD}/../../../)" # Points to EarthWorks
if [ ! -d "${SRCROOT}" ] ; then
	echo -e "ERROR: SRCROOT not a directory: \"${SRCROOT}\""
	exit 1
fi
CSEROOT="$(realpath ${PWD}/../../../../cases)"
[ -d "${CSEROOT}" ] || mkdir -p "${CSEROOT}"
# Adjust case prefix to whatever makes sense for you
PRE="$(date +%Y%b%d_%H%M%S)_EWMTesting"
INDATA="/glade/campaign/univ/ucsu0085/inputdata"

CMD="_derecho_CBR.sh -id ${INDATA} --srcroot ${SRCROOT} --casesdir ${CSEROOT} --res=(${RESS[@]}) --compiler=(${COMPI[@]}) -cp ${PRE} "
## This line requests GPUs
# CMD="_derecho_CBR.sh -id ${INDATA} --srcroot ${SRCROOT} --casesdir ${CSEROOT} --res=(${RESS[@]}) --compiler=(${COMPI[@]}) --gpus -cp ${PRE} "
## Note the difference in RESS between above and below lines. Arrays don't work for single values correctly
CMD="_derecho_CBR.sh -id ${INDATA} --srcroot ${SRCROOT} --casesdir ${CSEROOT} --res=${RESS} --compiler=(${COMPI[@]}) -cp ${PRE} "

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
	echo "./${CCMD}" | tee $LG_FILE
	./${CCMD} -nb -nr 2>&1 | tee -a $LG_FILE
done

# Run the build and then submit steps for each
for C in ${COMPS[@]}; do
	CCMD="${C}${CMD}"
	LG_FILE="log.buildrun.${PRE}.${C}.txt"
	./${CCMD} -nc 2>&1 | tee -a $LG_FILE
done
