#
# ------ FOR K computer -----
#
FFLAGS_FAST  = -Kfast,parallel,ocl,preex,array_private,noalias=s,mfunc=2 \
               -Qi -Qt -X03 -Ncompdisp -Koptmsg=2 -Cpp                   \
               -Kdynamic_iteration -Ksimd                                \
               -Kauto,threadsafe

#               -Qm -Nquickdbg -NRtrap

FFLAGS_DEBUG = -O0                                                   \
               -Qi -Qt -X03 -Ncompdisp -Koptmsg=2 -Cpp               \
               -Ec -Eg -Ha -He -Hf -Ho -Hs -Hu -Hx -v03s -v03d -v03o \
               -Ncheck_cache_arraysize -Ncheck_global                \
               -DDEBUG

FC     = mpifrtpx
FFLAGS = $(FFLAGS_FAST)
#FFLAGS = $(FFLAGS_DEBUG)

CC     = mpifccpx
CFLAGS_FAST  = -Kfast,parallel,ocl,preex,array_private,region_extension,restp=all -Ksimd
CFLAGS_DEBUG = -O0

CFLAGS = $(CFLAGS_FAST)
#CFLAGS = $(CFLAGS_DEBUG)

##### Special Options #####

# Performance monitor
# disable
PERF_MONIT = -Ntl_notrt -U_FIPP_ -U_FAPP_ -U_FINEPA_
# fipp
#PERF_MONIT = -Ntl_trt -D_FIPP_ -U_FAPP_ -U_FINEPA_
# fapp
#PERF_MONIT = -Ntl_trt -U_FIPP_ -D_FAPP_ -U_FINEPA_
# fine PA
#PERF_MONIT = -Ntl_trt -U_FIPP_ -U_FAPP_ -D_FINEPA_

FFLAGS += $(PERF_MONIT)
CFLAGS += $(PERF_MONIT)

ifeq ($(ENABLE_OPENMP),T)
	FFLAGS += -Kopenmp
endif

ifeq ($(ENABLE_NETCDF),T)
	FFLAGS      += -I/opt/aics/netcdf/k-serial-noszip/include
	CFLAGS      += -I/opt/aics/netcdf/k-serial-noszip/include
	NETCDF_LIBS ?= -L/opt/aics/netcdf/k-serial-noszip/lib-static -lnetcdff -lnetcdf -lhdf5_hl -lhdf5 -lz -lm
endif

LAPACK_LIBS ?= -SSL2BLAMP -SCALAPACK

###########################

MODDIROPT ?= -M $(BUILDDIR)
OBJDIR    ?= $(BUILDDIR)

LD     = $(FC)
LFLAGS = $(FFLAGS)

MAKE    = make
INSTALL = cp -u
AR      = ar
ARFLAGS = r
RANLIB  = ranlib
JOBSUB  = pjsub
