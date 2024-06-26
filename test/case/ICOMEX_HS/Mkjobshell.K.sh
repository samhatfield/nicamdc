#! /bin/bash -x

GLEV=${1}
RLEV=${2}
NMPI=${3}
ZL=${4}
VGRID=${5}
TOPDIR=${6}
BINNAME=${7}

# System specific
MPIEXEC="mpiexec"

GL=`printf %02d ${GLEV}`
RL=`printf %02d ${RLEV}`
if   [ ${NMPI} -ge 10000 ]; then
	NP=`printf %05d ${NMPI}`
elif [ ${NMPI} -ge 1000 ]; then
	NP=`printf %04d ${NMPI}`
elif [ ${NMPI} -ge 100 ]; then
	NP=`printf %03d ${NMPI}`
else
	NP=`printf %02d ${NMPI}`
fi

dir2d=gl${GL}rl${RL}pe${NP}
dir3d=gl${GL}rl${RL}z${ZL}pe${NP}
res2d=GL${GL}RL${RL}
res3d=GL${GL}RL${RL}z${ZL}

MNGINFO=rl${RL}-prc${NP}.info

# for K computer
if [ ${NMPI} -gt 36864 ]; then
   rscgrp="huge"
elif [ ${NMPI} -gt 384 ]; then
   rscgrp="large"
else
   rscgrp="small"
fi

cat << EOF1 > run.sh
#! /bin/bash -x
################################################################################
#
# for K computer
#
################################################################################
#PJM --rsc-list "rscgrp=${rscgrp}"
#PJM --rsc-list "node=${NMPI}"
#PJM --rsc-list "elapse=16:00:00"
#PJM --stg-transfiles all
#PJM --mpi "use-rankdir"
#PJM --stgin  "rank=* ${TOPDIR}/bin/${BINNAME}           %r:./"
#PJM --stgin  "rank=* ./nhm_driver.cnf                   %r:./"
#PJM --stgin  "rank=* ${TOPDIR}/data/mnginfo/${MNGINFO}  %r:./"
#PJM --stgin  "rank=* ${TOPDIR}/data/grid/vgrid/${VGRID} %r:./"
#PJM --stgin  "rank=* ${TOPDIR}/data/grid/boundary/${dir2d}/boundary_${res2d}.pe%06r %r:./"
#PJM --stgin  "rank=* ${TOPDIR}/data/initial/HS_spinup_300day/${dir3d}/restart_all_${res3d}.pe%06r %r:./init_all_${res3d}.pe%06r"
#PJM --stgout "rank=* %r:./*           ./"
#PJM -j
#PJM -s
#
. /work/system/Env_base
#
export PARALLEL=8
export OMP_NUM_THREADS=8
export XOS_MMM_L_ARENA_FREE=2

# run
${MPIEXEC} ./${BINNAME} || exit

################################################################################
EOF1


cat << EOFICO2LL1 > ico2ll.sh
#! /bin/bash -x
################################################################################
#
# for K computer
#
################################################################################
#PJM --rsc-list "rscgrp=${rscgrp}"
#PJM --rsc-list "node=${NMPI}"
#PJM --rsc-list "elapse=00:30:00"
#PJM --stg-transfiles all
#PJM --mpi "use-rankdir"
#PJM --stgin  "rank=* ${TOPDIR}/bin/fio_ico2ll_mpi      %r:./"
#PJM --stgin  "rank=* ${TOPDIR}/data/mnginfo/${MNGINFO} %r:./"
#PJM --stgin  "rank=* ${TOPDIR}/data/zaxis/*            %r:./"
#PJM --stgin  "rank=* ./history.pe%06r                  %r:./"
#PJM --stgin  "rank=* ${TOPDIR}/data/grid/llmap/gl${GL}rl${RL}/llmap.* %r:./"
#PJM --stgout "rank=* %r:./*           ./"
#PJM --stgout "rank=0 ../*             ./"
#PJM -j
#PJM -s
#
. /work/system/Env_base
#
export PARALLEL=8
export OMP_NUM_THREADS=8

# run
${MPIEXEC} ./fio_ico2ll_mpi \
history \
glevel=${GLEV} \
rlevel=${RLEV} \
mnginfo="./${MNGINFO}" \
layerfile_dir="./." \
llmap_base="./llmap" \
outfile_dir="../" \
-lon_swap \
-comm_smallchunk

################################################################################
EOFICO2LL1
