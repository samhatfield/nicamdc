################################################################################
#
# Makefile for main program
#
################################################################################

TOPDIR = ..

include $(TOPDIR)/sysdep/Makedef.$(NICAM_SYS)
include $(TOPDIR)/src/Mkinclude

VPATH = share:nhm/share:nhm/dynamics$(OCL):nhm/forcing:nhm

ifeq ($(prec), noreal16)
VPATH += :share/extra
mod_misc := mod_misc_noreal16
else
mod_misc := mod_misc
endif

PRJ1 = prg_driver-dc



all: makedir makemain maketool

makedir:
	mkdir -p $(BINDIR)
	mkdir -p $(LIBDIR)

makemain: $(PRJ1)
	$(INSTALL) $(PRJ1) $(BINDIR)/$(BINNAME)
	@echo; echo "##### $(BINNAME) is Installed Successfully #####"; echo

maketool:
	@$(MAKE) -C tool || exit 1



MODS =	\
	mod_adm.o	\
	$(mod_misc).o	\
	mod_debug.o	\
	mod_cnst.o	\
	mod_fio.o	\
	mod_calendar.o	\
	fio.o	\
	fiof.o	\
	mod_comm.o	\
	mod_grd.o	\
	mod_gmtr.o	\
	mod_oprt$(OCL).o	\
	mod_vmtr.o	\
	mod_time.o	\
	mod_latlon.o	\
	mod_gtl.o	\
	mod_vintrpl.o	\
	mod_oprt3d$(OCL).o	\
	mod_history.o	\
	mod_chemvar.o	\
	mod_runconf.o	\
	mod_cnvvar.o	\
	mod_thrmdyn.o	\
	mod_bndcnd.o	\
	mod_sfcvar.o	\
	mod_prgvar.o	\
	mod_history_vars.o	\
	mod_bsstate.o	\
	mod_diagvar.o	\
	mod_embudget.o	\
	mod_dycoretest.o \
	mod_numfilter.o	\
	mod_src.o	\
	mod_advlim_thuburn.o	\
	mod_forcing_init.o	\
	mod_af_driver.o	\
	mod_af_heldsuarez.o	\
	mod_dynstep.o	\
	mod_vi.o	\
	mod_ndg.o	\
	mod_tb_smg.o	\
	mod_forcing.o

$(PRJ1): $(PRJ1).o $(LIBDIR)/$(LIBNAME)
	$(LD) $(LFLAGS) -o $@ $^

$(PRJ1).o : $(PRJ1).f90 $(LIBNAME)

$(LIBDIR)/$(LIBNAME): $(LIBNAME)
	install $< $@
	@echo; echo "##### $(LIBNAME) is Installed Successfully #####"; echo

$(LIBNAME): $(MODS)
	$(AR) $@ $?
	$(RANLIB) $@

$(mod_misc).o	: $(mod_misc).f90
mod_adm.o	: mod_adm.f90 $(mod_misc).o
mod_debug.o	: mod_debug.f90 mod_adm.o $(mod_misc).o mod_comm.o
mod_cnst.o	: mod_cnst.f90 mod_adm.o
mod_calendar.o	: mod_calendar.f90 mod_adm.o
fio.o	: fio.c fio.h fio_def.h
fiof.o	: fiof.c fiof.h fio.h fio_def.h
mod_fio.o	: mod_fio.f90 mod_adm.o mod_calendar.o mod_cnst.o fio.o fiof.o
mod_comm.o	: mod_comm.f90 mod_adm.o mod_cnst.o
mod_grd.o	: mod_grd.f90 mod_adm.o mod_cnst.o mod_comm.o $(mod_misc).o mod_fio.o
mod_gmtr.o	: mod_gmtr.f90 mod_adm.o mod_comm.o $(mod_misc).o mod_grd.o mod_cnst.o
mod_oprt$(OCL).o	: mod_oprt$(OCL).f90 mod_adm.o mod_gmtr.o mod_grd.o mod_comm.o mod_cnst.o
mod_vmtr.o	: mod_vmtr.f90 mod_adm.o mod_grd.o mod_comm.o mod_gmtr.o mod_oprt$(OCL).o mod_cnst.o
mod_time.o	: mod_time.f90 mod_adm.o mod_calendar.o
mod_latlon.o	: mod_latlon.f90 mod_adm.o mod_cnst.o $(mod_misc).o mod_grd.o mod_oprt$(OCL).o mod_comm.o mod_gmtr.o
mod_gtl.o	: mod_gtl.f90 mod_adm.o mod_comm.o mod_gmtr.o mod_vmtr.o mod_cnst.o $(mod_misc).o mod_grd.o
mod_vintrpl.o	: mod_vintrpl.f90 mod_adm.o mod_grd.o mod_cnst.o
mod_oprt3d$(OCL).o	: mod_oprt3d$(OCL).f90 mod_adm.o mod_grd.o mod_gmtr.o mod_vmtr.o

mod_chemvar.o	: mod_chemvar.f90 mod_adm.o
mod_runconf.o	: mod_runconf.f90 mod_adm.o mod_cnst.o mod_chemvar.o
mod_thrmdyn.o	: mod_thrmdyn.f90 mod_adm.o mod_cnst.o mod_runconf.o
mod_bndcnd.o	: mod_bndcnd.f90 mod_adm.o mod_cnst.o mod_grd.o mod_runconf.o
mod_cnvvar.o	: mod_cnvvar.f90 mod_adm.o mod_grd.o mod_thrmdyn.o mod_runconf.o mod_bndcnd.o mod_vmtr.o
mod_sfcvar.o	: mod_sfcvar.f90 mod_adm.o mod_runconf.o mod_comm.o
mod_prgvar.o	: mod_prgvar.f90 mod_adm.o mod_runconf.o mod_comm.o mod_dycoretest.o
mod_history.o	: mod_history.f90 mod_adm.o mod_time.o mod_runconf.o mod_grd.o mod_cnst.o mod_calendar.o mod_fio.o mod_comm.o mod_gtl.o mod_vintrpl.o $(mod_misc).o mod_cnvvar.o mod_thrmdyn.o mod_vmtr.o mod_sfcvar.o mod_prgvar.o
mod_bsstate.o	: mod_bsstate.f90 mod_adm.o mod_cnst.o mod_grd.o $(mod_misc).o mod_runconf.o mod_vintrpl.o mod_bndcnd.o mod_thrmdyn.o
mod_diagvar.o	: mod_diagvar.f90 mod_adm.o mod_comm.o $(mod_misc).o mod_gtl.o mod_runconf.o mod_fio.o mod_time.o mod_grd.o
mod_history_vars.o	: mod_history_vars.f90 mod_history.o mod_adm.o mod_runconf.o mod_gmtr.o mod_gtl.o mod_vmtr.o mod_prgvar.o mod_sfcvar.o mod_bsstate.o mod_cnvvar.o mod_thrmdyn.o mod_cnst.o mod_bndcnd.o mod_diagvar.o mod_grd.o
mod_embudget.o	: mod_embudget.f90 mod_adm.o $(mod_misc).o mod_time.o mod_sfcvar.o mod_cnst.o mod_grd.o mod_vmtr.o mod_gtl.o mod_runconf.o mod_cnvvar.o mod_bsstate.o mod_thrmdyn.o mod_prgvar.o
mod_dycoretest.o	: mod_dycoretest.f90 mod_adm.o mod_runconf.o $(mod_misc).o mod_vmtr.o mod_fio.o mod_time.o mod_cnvvar.o mod_vintrpl.o mod_comm.o mod_cnst.o mod_thrmdyn.o
mod_advlim_thuburn.o	: mod_advlim_thuburn.f90 mod_adm.o mod_cnst.o mod_comm.o
mod_src.o	: mod_src.f90 mod_adm.o mod_vmtr.o mod_grd.o mod_oprt$(OCL).o mod_cnst.o mod_runconf.o mod_gtl.o mod_advlim_thuburn.o
mod_numfilter.o	: mod_numfilter.f90 mod_adm.o mod_time.o mod_grd.o mod_cnst.o mod_gtl.o mod_gmtr.o mod_oprt$(OCL).o mod_oprt3d$(OCL).o mod_comm.o mod_src.o mod_vmtr.o mod_runconf.o mod_bsstate.o
mod_af_heldsuarez.o	: mod_af_heldsuarez.f90 mod_adm.o mod_cnst.o
mod_af_driver.o	: mod_af_driver.f90 mod_adm.o mod_af_heldsuarez.o mod_runconf.o mod_cnst.o
mod_forcing_init.o	: mod_forcing_init.f90 mod_adm.o mod_runconf.o mod_af_driver.o
mod_vi.o	: mod_vi.f90 mod_adm.o mod_comm.o mod_time.o mod_cnst.o mod_grd.o mod_oprt$(OCL).o mod_vmtr.o mod_runconf.o mod_bndcnd.o mod_numfilter.o mod_src.o mod_cnvvar.o mod_bsstate.o
mod_ndg.o	: mod_ndg.f90 mod_adm.o $(mod_misc).o mod_time.o mod_calendar.o mod_grd.o mod_cnst.o mod_vmtr.o mod_history.o mod_gmtr.o mod_oprt$(OCL).o mod_runconf.o mod_gtl.o mod_comm.o
mod_tb_smg.o	: mod_tb_smg.f90 mod_adm.o mod_vmtr.o mod_history.o mod_gmtr.o mod_grd.o mod_cnst.o mod_runconf.o mod_oprt$(OCL).o mod_comm.o mod_bsstate.o mod_time.o
mod_dynstep.o	: mod_dynstep.f90 mod_adm.o mod_cnst.o mod_time.o mod_grd.o mod_vmtr.o mod_runconf.o mod_bsstate.o mod_bndcnd.o mod_prgvar.o mod_diagvar.o mod_thrmdyn.o mod_numfilter.o mod_vi.o mod_src.o mod_ndg.o mod_tb_smg.o mod_oprt$(OCL).o mod_debug.o
mod_forcing.o	: mod_forcing.f90 mod_adm.o mod_grd.o mod_gmtr.o mod_vmtr.o mod_time.o mod_runconf.o mod_cnst.o mod_cnvvar.o mod_prgvar.o mod_sfcvar.o mod_thrmdyn.o mod_gtl.o mod_diagvar.o mod_bsstate.o mod_bndcnd.o $(mod_misc).o mod_af_driver.o mod_history.o


.SUFFIXES: .o .f90 .c
.f90.o:
	$(FC) $(FFLAGS) -o $@ -c $<
.c.o:
	$(CC) $(CFLAGS) -o $@ -c $<

%.o: %.mod

.PHONY: clean

clean:
	rm -f $(PRJ1) $(LIBNAME)
	$(CLEAN)
	$(MAKE) -C tool clean