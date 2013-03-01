!-------------------------------------------------------------------------------
!
!+  Dynamical step
!
!-------------------------------------------------------------------------------
module mod_dynstep
  !-----------------------------------------------------------------------------
  !
  !++ Description: 
  !       This module is for the dynamical step 
  !       
  ! 
  !++ Current Corresponding Author : H.Tomita
  ! 
  !++ History: 
  !      Version   Date       Comment 
  !      -----------------------------------------------------------------------
  !      0.00      04-02-17   Imported from igdc-4.34
  !                06-04-17   Add IN_LARGE_STEP2
  !                06-08-11   Add the option for tracer advection.
  !                07-01-26   Add flag [rayleigh_damp_only_w] 
  !                           in numfilter_rayleigh_damping.
  !                07-05-08   H.Tomita : Change the treatment of I_TKE.
  !                08-01-24   Y.Niwa: add revised MIURA2004 for tracer advection
  !                           old: 'MIURA2004OLD', revised: 'MIURA2004'
  !                08-01-30   Y.Niwa: add rho_pl = 0.D0
  !                08-04-12   T.Mitsui save memory(prgvar, frcvar, rhog0xxxx)
  !                08-05-24   T.Mitsui fix miss-conditioning for frcvar
  !                08-09-09   Y.Niwa move nudging routine here
  !                08-10-05   T.Mitsui all_phystep_post is already needless
  !                09-09-08   S.Iga  frhog and frhog_pl in ndg are deleted ( suggested by ES staff)
  !                10-05-06   M.Satoh: define QV_conv only if CP_TYPE='TDK' .or. 'KUO'
  !                10-07-16   A.T.Noda: bug fix for TDK
  !                10-08-16   A.T.Noda: Bug fix (Qconv not diveded by density)
  !                10-08-20   A.T.Noda: Bug fix (Qconv should be tendency, and not be multiplied by DT)
  !                10-11-29   A.T.Noda: Introduce the Smagorinsky model
  !                11-08-16   M.Satoh: bug fix for TDK: conv => tendency
  !                           qv_dyn_tend = v grad q
  !                                       = ( div(rho v q) - div(rho v)*q )/rho
  !                11-08-16   M.Satoh: move codes related to CP_TYPE below the tracer calculation
  !                11-11-28   Y.Yamada: Merge Terai-san timer into the original code.
  !                12-03-09   S.Iga: tuned (phase4-1)
  !                12-04-06   T.yamaura: optimized for K
  !                12-05-30   T.Yashiro: Change arguments from character to index/switch
  !                12-10-22   R.Yoshida  : add papi instructions
  !      -----------------------------------------------------------------------
  !
  !-----------------------------------------------------------------------------
  !
  !++ Used modules
  !
  !-----------------------------------------------------------------------------
  implicit none
  private
  !-----------------------------------------------------------------------------
  !
  !++ Public procedure
  !
  public :: dynstep
  public :: dynstep2

  !-----------------------------------------------------------------------------
  !
  !++ Public parameters & variables
  !
  !-----------------------------------------------------------------------------
  !
  !++ Private procedures
  !
  !-----------------------------------------------------------------------------
  !
  !++ Private parameters & variables
  !
  integer, private, parameter :: nmax_tendency   = 7

  integer, private, parameter :: I_RHOG     = 1 ! Density x G^{1/2} x gamma^2
  integer, private, parameter :: I_RHOGVX   = 2 ! Density x G^{1/2} x gamma^2 x Horizontal velocity (X-direction)
  integer, private, parameter :: I_RHOGVY   = 3 ! Density x G^{1/2} x gamma^2 x Horizontal velocity (Y-direction)
  integer, private, parameter :: I_RHOGVZ   = 4 ! Density x G^{1/2} x gamma^2 x Horizontal velocity (Z-direction)
  integer, private, parameter :: I_RHOGW    = 5 ! Density x G^{1/2} x gamma^2 x Vertical   velocity
  integer, private, parameter :: I_RHOGE    = 6 ! Density x G^{1/2} x gamma^2 x Internal Energy
  integer, private, parameter :: I_RHOGETOT = 7 ! Density x G^{1/2} x gamma^2 x Total Energy

  !-----------------------------------------------------------------------------
contains 
  !-----------------------------------------------------------------------------
  subroutine dynstep
    use mod_debug
    use mod_adm, only: &
       ADM_prc_me,  &
       ADM_prc_pl,  &
       ADM_gall,    &
       ADM_gall_pl, &
       ADM_lall,    &
       ADM_lall_pl, &
       ADM_kall,    &
       ADM_gall_1d, &
       ADM_gmax,    &
       ADM_gmin,    &
       ADM_kmax,    &
       ADM_kmin
    use mod_cnst, only: &
       CNST_RAIR, &
       CNST_RVAP, &
       CNST_CV
    use mod_time, only:  &
       TIME_INTEG_TYPE,  &
       TIME_SSTEP_MAX,   &
       TIME_DTL,         &
       TIME_DTS,         &
       TIME_SPLIT
    use mod_grd, only: &
       GRD_afac, &
       GRD_bfac
    use mod_vmtr, only: &
       VMTR_GSGAM2,     &
       VMTR_GSGAM2_pl,  &
       VMTR_GSGAM2H,    &
       VMTR_GSGAM2H_pl, &
       VMTR_PHI,        &
       VMTR_PHI_pl,     &
       VMTR_C2Wfact,    &
       VMTR_C2Wfact_pl
    use mod_comm, only: &
       COMM_data_transfer
    use mod_runconf, only: &
       TRC_VMAX,       &
       I_QV,           &
       I_TKE,          &
       NQW_STR,        &
       NQW_END,        &
       CVW,            &
       NDIFF_LOCATION, &
       TRC_ADV_TYPE,   &
       FLAG_NUDGING,   & ! Y.Niwa add 08/09/09
       CP_TYPE,        & ! 2010.5.11 M.Satoh [add]
       TB_TYPE           ! [add] 10/11/29 A.Noda
    use mod_bsstate, only: &
       pre_bs, pre_bs_pl, &
       rho_bs, rho_bs_pl
    use mod_bndcnd, only: &
       bndcnd_all
    use mod_prgvar, only: &
       prgvar_set,    &
       prgvar_get,    &
       prgvar_get_noq
    use mod_diagvar, only: &
       diagvar,       &
       diagvar_pl,    &
       I_RHOGQV_CONV, &
       I_QV_DYN_TEND    ! 2011.08.16 M.Satoh
    use mod_thrmdyn, only: &
       thrmdyn_th, &
       thrmdyn_eth
    use mod_numfilter, only: &
       NUMFILTER_DOrayleigh,       & ! [add] H.Yashiro 20120530
       NUMFILTER_DOverticaldiff,   & ! [add] H.Yashiro 20120530
       numfilter_rayleigh_damping, &
       numfilter_numerical_hdiff,  &
       numfilter_numerical_vdiff
    use mod_vi, only :         &
       vi_small_step
    use mod_src, only: &
       src_advection_convergence_v, &
       src_advection_convergence,   &
       src_update_tracer,           &
       I_SRC_default                  ! [add] H.Yashiro 20120530
    use mod_ndg, only: & ! Y.Niwa add 08/09/09
       ndg_nudging_uvtp, &
       ndg_update_var
    use mod_tb_smg, only: & ! [add] 10/11/29 A.Noda
       tb_smg_driver
    implicit none

    integer, parameter :: nmax_tendency   = 7
    integer, parameter :: nmax_prog = 6
    integer, parameter :: nmax_v_mean_c   = 5

    real(8) :: gtend        (ADM_gall,   ADM_kall,ADM_lall,   nmax_tendency) !--- tendensy
    real(8) :: gtend_pl     (ADM_gall_pl,ADM_kall,ADM_lall_pl,nmax_tendency)

    real(8) :: ftend        (ADM_gall,   ADM_kall,ADM_lall,   nmax_tendency) !--- forcing tendensy
    real(8) :: ftend_pl     (ADM_gall_pl,ADM_kall,ADM_lall_pl,nmax_tendency)

    real(8) :: prog0        (ADM_gall,   ADM_kall,ADM_lall,   nmax_prog)     !--- prog variables (save)
    real(8) :: prog0_pl     (ADM_gall_pl,ADM_kall,ADM_lall_pl,nmax_prog)

    real(8) :: prog         (ADM_gall,   ADM_kall,ADM_lall,   nmax_prog)     !--- prog variables
    real(8) :: prog_pl      (ADM_gall_pl,ADM_kall,ADM_lall_pl,nmax_prog)

    real(8) :: prog_split   (ADM_gall,   ADM_kall,ADM_lall,   nmax_prog)     !--- prog variables (split)
    real(8) :: prog_split_pl(ADM_gall_pl,ADM_kall,ADM_lall_pl,nmax_prog)



    real(8) :: gtendq    (ADM_gall,   ADM_kall,ADM_lall,   TRC_VMAX) !--- tendensy of q
    real(8) :: gtendq_pl (ADM_gall_pl,ADM_kall,ADM_lall_pl,TRC_VMAX)

    real(8) :: ftendq    (ADM_gall,   ADM_kall,ADM_lall,   TRC_VMAX) !--- forcing tendensy of q
    real(8) :: ftendq_pl (ADM_gall_pl,ADM_kall,ADM_lall_pl,TRC_VMAX)

    real(8) :: progq0    (ADM_gall,   ADM_kall,ADM_lall,   TRC_VMAX) !--- tracer variables (save)
    real(8) :: progq0_pl (ADM_gall_pl,ADM_kall,ADM_lall_pl,TRC_VMAX)

    real(8) :: progq     (ADM_gall,   ADM_kall,ADM_lall,   TRC_VMAX) !--- tracer variables
    real(8) :: progq_pl  (ADM_gall_pl,ADM_kall,ADM_lall_pl,TRC_VMAX)

    real(8) :: v_mean_c   (ADM_gall,   ADM_kall,ADM_lall   ,nmax_v_mean_c)
    real(8) :: v_mean_c_pl(ADM_gall_pl,ADM_kall,ADM_lall_pl,nmax_v_mean_c)

    !--- density ( physical )
    real(8) :: rho   (ADM_gall,   ADM_kall,ADM_lall   )
    real(8) :: rho_pl(ADM_gall_pl,ADM_kall,ADM_lall_pl)

    !--- horizontal velocity_x  ( physical )
    real(8) :: vx   (ADM_gall,   ADM_kall,ADM_lall   )
    real(8) :: vx_pl(ADM_gall_pl,ADM_kall,ADM_lall_pl)

    !--- horizontal velocity_y  ( physical )
    real(8) :: vy   (ADM_gall,   ADM_kall,ADM_lall   )
    real(8) :: vy_pl(ADM_gall_pl,ADM_kall,ADM_lall_pl)

    !--- horizontal velocity_z  ( physical )
    real(8) :: vz   (ADM_gall,   ADM_kall,ADM_lall   )
    real(8) :: vz_pl(ADM_gall_pl,ADM_kall,ADM_lall_pl)

    !--- vertical velocity ( physical )
    real(8) :: w   (ADM_gall,   ADM_kall,ADM_lall   )
    real(8) :: w_pl(ADM_gall_pl,ADM_kall,ADM_lall_pl)

    !--- [IN]ternal energy  ( physical )
    real(8) :: ein   (ADM_gall,   ADM_kall,ADM_lall   )
    real(8) :: ein_pl(ADM_gall_pl,ADM_kall,ADM_lall_pl)

    !--- mass concentration of water substance ( physical )
    real(8) :: q   (ADM_gall,   ADM_kall,ADM_lall,   TRC_VMAX)
    real(8) :: q_pl(ADM_gall_pl,ADM_kall,ADM_lall_pl,TRC_VMAX)

    !--- temperature ( physical )
    real(8) :: tem   (ADM_gall,   ADM_kall,ADM_lall   )
    real(8) :: tem_pl(ADM_gall_pl,ADM_kall,ADM_lall_pl)

    !--- pressure ( physical )
    real(8) :: pre   (ADM_gall,   ADM_kall,ADM_lall   )
    real(8) :: pre_pl(ADM_gall_pl,ADM_kall,ADM_lall_pl)

    !--- potential temperature ( physical )
    real(8) :: th   (ADM_gall,   ADM_kall,ADM_lall   )
    real(8) :: th_pl(ADM_gall_pl,ADM_kall,ADM_lall_pl)

    !--- enthalpy ( physical )
    real(8) :: eth   (ADM_gall,   ADM_kall,ADM_lall   )
    real(8) :: eth_pl(ADM_gall_pl,ADM_kall,ADM_lall_pl)

    !--- density deviation from the base state ( G^{1/2} X gamma2 )
    real(8) :: rhogd   (ADM_gall,   ADM_kall,ADM_lall   )
    real(8) :: rhogd_pl(ADM_gall_pl,ADM_kall,ADM_lall_pl)

    !--- pressure deviation from the base state ( G^{1/2} X gamma2 )
    real(8) :: pregd   (ADM_gall,   ADM_kall,ADM_lall   )
    real(8) :: pregd_pl(ADM_gall_pl,ADM_kall,ADM_lall_pl)

    !--- temporary variables
    real(8) :: qd      (ADM_gall,   ADM_kall,ADM_lall   )
    real(8) :: qd_pl   (ADM_gall_pl,ADM_kall,ADM_lall_pl)
    real(8) :: cv      (ADM_gall,   ADM_kall,ADM_lall   )
    real(8) :: cv_pl   (ADM_gall_pl,ADM_kall,ADM_lall_pl)

    real(8), parameter :: TKE_MIN = 0.D0
    real(8)            :: TKEg_corr

    integer :: small_step_ite
    real(8) :: small_step_dt

    logical :: ndgtend_out

    logical, save :: iflag = .true.
    integer, save :: num_of_iteration_lstep    ! number of large steps ( 2-4 )
    integer, save :: num_of_iteration_sstep(4) ! number of small steps in each of large steps

    integer :: ij, k ,l, nq, nl

    integer :: i, j, suf
    suf(i,j) = ADM_gall_1d * ((j)-1) + (i)
    !---------------------------------------------------------------------------

#ifdef PAPI_OPS
    ! <-- [add] PAPI R.Yoshida 20121022
    !call PAPIF_flips( PAPI_real_time_i, PAPI_proc_time_i, PAPI_flpins, PAPI_mflins, PAPI_check )
    call PAPIF_flops( PAPI_real_time_o, PAPI_proc_time_o, PAPI_flpops, PAPI_mflops, PAPI_check )
#endif

    if ( iflag ) then
       iflag = .false.

       select case(trim(TIME_INTEG_TYPE))
       case('RK2')
          num_of_iteration_lstep = 2
          num_of_iteration_sstep(1) = TIME_SSTEP_MAX/2
          num_of_iteration_sstep(2) = TIME_SSTEP_MAX
       case('RK3')
          num_of_iteration_lstep = 3
          num_of_iteration_sstep(1) = TIME_SSTEP_MAX/3
          num_of_iteration_sstep(2) = TIME_SSTEP_MAX/2
          num_of_iteration_sstep(3) = TIME_SSTEP_MAX
        case('RK4')
          num_of_iteration_lstep = 4
          num_of_iteration_sstep(1) = TIME_SSTEP_MAX/4
          num_of_iteration_sstep(2) = TIME_SSTEP_MAX/3
          num_of_iteration_sstep(3) = TIME_SSTEP_MAX/2
          num_of_iteration_sstep(4) = TIME_SSTEP_MAX
       case default
          write(*,*) 'Msg : Sub[sub_dynstep]'
          write(*,*) ' --- Error : invalid TIME_INTEG_TYPE=', TIME_INTEG_TYPE
       endselect
    endif

    !--- get from prg0
    call prgvar_get( prog(:,:,:,I_RHOG),   prog_pl(:,:,:,I_RHOG),   & !--- [OUT]
                     prog(:,:,:,I_RHOGVX), prog_pl(:,:,:,I_RHOGVX), & !--- [OUT]
                     prog(:,:,:,I_RHOGVY), prog_pl(:,:,:,I_RHOGVY), & !--- [OUT]
                     prog(:,:,:,I_RHOGVZ), prog_pl(:,:,:,I_RHOGVZ), & !--- [OUT]
                     prog(:,:,:,I_RHOGW),  prog_pl(:,:,:,I_RHOGW),  & !--- [OUT]
                     prog(:,:,:,I_RHOGE),  prog_pl(:,:,:,I_RHOGE),  & !--- [OUT]
                     progq(:,:,:,:),       progq_pl(:,:,:,:),       & !--- [OUT]
                     0                                                          ) !--- [IN]

    prog0   (:,:,:,:) = prog   (:,:,:,:)
    prog0_pl(:,:,:,:) = prog_pl(:,:,:,:)

    if ( TRC_ADV_TYPE == 'DEFAULT' ) then
       progq0   (:,:,:,:) = progq   (:,:,:,:)
       progq0_pl(:,:,:,:) = progq_pl(:,:,:,:)
    endif

    !---------------------------------------------------------------------------
    !
    !> Start large time step integration
    !
    !---------------------------------------------------------------------------
    do nl = 1, num_of_iteration_lstep

       !---< Generate diagnostic values and set the boudary conditions
       rho(:,:,:) = prog(:,:,:,I_RHOG)   / VMTR_GSGAM2(:,:,:)
       vx (:,:,:) = prog(:,:,:,I_RHOGVX) / prog(:,:,:,I_RHOG)
       vy (:,:,:) = prog(:,:,:,I_RHOGVY) / prog(:,:,:,I_RHOG)
       vz (:,:,:) = prog(:,:,:,I_RHOGVZ) / prog(:,:,:,I_RHOG)
       ein(:,:,:) = prog(:,:,:,I_RHOGE)  / prog(:,:,:,I_RHOG)

       do nq = 1, TRC_VMAX
          q(:,:,:,nq) = progq(:,:,:,nq) / prog(:,:,:,I_RHOG)
       enddo

       cv(:,:,:)  = 0.D0
       qd(:,:,:)  = 1.D0
       do nq = NQW_STR, NQW_END
          cv(:,:,:) = cv(:,:,:) + q(:,:,:,nq) * CVW(nq)
          qd(:,:,:) = qd(:,:,:) - q(:,:,:,nq)
       enddo
       cv(:,:,:) = cv(:,:,:) + qd(:,:,:) * CNST_CV

       tem(:,:,:) = ein(:,:,:) / cv(:,:,:)
       pre(:,:,:) = rho(:,:,:) * tem(:,:,:) * ( qd(:,:,:)*CNST_RAIR + q(:,:,:,I_QV)*CNST_RVAP )

       do l = 1, ADM_lall
          do k = ADM_kmin+1, ADM_kmax
             do ij = 1, ADM_gall
                w(ij,k,l) = prog(ij,k,l,I_RHOGW) &
                          / ( 0.5D0 * ( GRD_afac(k) * rho(ij,k  ,l) &
                                      + GRD_bfac(k) * rho(ij,k-1,l) ) * VMTR_GSGAM2H(ij,k,l) )
             enddo
          enddo

          !--- boundary conditions
          call bndcnd_all( ADM_gall,            & !--- [IN]
                           rho   (:,:,l),       & !--- [INOUT]
                           vx    (:,:,l),       & !--- [INOUT]
                           vy    (:,:,l),       & !--- [INOUT]
                           vz    (:,:,l),       & !--- [INOUT]
                           w     (:,:,l),       & !--- [INOUT]
                           ein   (:,:,l),       & !--- [INOUT]
                           tem   (:,:,l),       & !--- [INOUT]
                           pre   (:,:,l),       & !--- [INOUT]
                           prog(:,:,l,I_RHOG),   & !--- [INOUT]
                           prog(:,:,l,I_RHOGVX), & !--- [INOUT]
                           prog(:,:,l,I_RHOGVY), & !--- [INOUT]
                           prog(:,:,l,I_RHOGVZ), & !--- [INOUT]
                           prog(:,:,l,I_RHOGW),  & !--- [INOUT]
                           prog(:,:,l,I_RHOGE),  & !--- [INOUT]
                           VMTR_GSGAM2 (:,:,l),   & !--- [IN]
                           VMTR_PHI    (:,:,l),   & !--- [IN]
                           VMTR_C2Wfact(:,:,:,l)  ) !--- [IN]

          call thrmdyn_th( ADM_gall, th(:,:,l), tem(:,:,l), pre(:,:,l) )

          call thrmdyn_eth( ADM_gall, eth(:,:,l), ein(:,:,l), pre(:,:,l), rho(:,:,l) )       
       enddo ! region LOOP

       !--- perturbations ( pred, rhod )
       pregd(:,:,:) = ( pre(:,:,:) - pre_bs(:,:,:) ) * VMTR_GSGAM2(:,:,:)
       rhogd(:,:,:) = ( rho(:,:,:) - rho_bs(:,:,:) ) * VMTR_GSGAM2(:,:,:)

       if ( ADM_prc_me == ADM_prc_pl ) then

       rho_pl(:,:,:) = prog_pl(:,:,:,I_RHOG)   / VMTR_GSGAM2_pl(:,:,:)
       vx_pl (:,:,:) = prog_pl(:,:,:,I_RHOGVX) / prog_pl(:,:,:,I_RHOG)
       vy_pl (:,:,:) = prog_pl(:,:,:,I_RHOGVY) / prog_pl(:,:,:,I_RHOG)
       vz_pl (:,:,:) = prog_pl(:,:,:,I_RHOGVZ) / prog_pl(:,:,:,I_RHOG)
       ein_pl(:,:,:) = prog_pl(:,:,:,I_RHOGE)  / prog_pl(:,:,:,I_RHOG)

       do nq = 1, TRC_VMAX
          q_pl(:,:,:,nq) = progq_pl(:,:,:,nq) / prog_pl(:,:,:,I_RHOG)
       enddo

       cv_pl(:,:,:)  = 0.D0
       qd_pl(:,:,:)  = 1.D0
       do nq = NQW_STR, NQW_END
          cv_pl(:,:,:) = cv_pl(:,:,:) + q_pl(:,:,:,nq) * CVW(nq)
          qd_pl(:,:,:) = qd_pl(:,:,:) - q_pl(:,:,:,nq)
       enddo
       cv_pl(:,:,:) = cv_pl(:,:,:) + qd_pl(:,:,:) * CNST_CV

       tem_pl(:,:,:) = ein_pl(:,:,:) / cv_pl(:,:,:)
       pre_pl(:,:,:) = rho_pl(:,:,:) * tem_pl(:,:,:) * ( qd_pl(:,:,:)*CNST_RAIR + q_pl(:,:,:,I_QV)*CNST_RVAP )

          do l = 1, ADM_lall_pl
          do k = ADM_kmin+1, ADM_kmax
             do ij = 1, ADM_gall_pl
                w_pl(ij,k,l) = prog_pl(ij,k,l,I_RHOGW) &
                          / ( 0.5D0 * ( GRD_afac(k) * rho_pl(ij,k  ,l) &
                                      + GRD_bfac(k) * rho_pl(ij,k-1,l) ) * VMTR_GSGAM2H_pl(ij,k,l) )
             enddo
          enddo

          !--- boundary conditions
          call bndcnd_all( ADM_gall_pl,            & !--- [IN]
                           rho_pl   (:,:,l),       & !--- [INOUT]
                           vx_pl    (:,:,l),       & !--- [INOUT]
                           vy_pl    (:,:,l),       & !--- [INOUT]
                           vz_pl    (:,:,l),       & !--- [INOUT]
                           w_pl     (:,:,l),       & !--- [INOUT]
                           ein_pl   (:,:,l),       & !--- [INOUT]
                           tem_pl   (:,:,l),       & !--- [INOUT]
                           pre_pl   (:,:,l),       & !--- [INOUT]
                           prog_pl(:,:,l,I_RHOG  ), & !--- [INOUT]
                           prog_pl(:,:,l,I_RHOGVX), & !--- [INOUT]
                           prog_pl(:,:,l,I_RHOGVY), & !--- [INOUT]
                           prog_pl(:,:,l,I_RHOGVZ), & !--- [INOUT]
                           prog_pl(:,:,l,I_RHOGW ), & !--- [INOUT]
                           prog_pl(:,:,l,I_RHOGE ), & !--- [INOUT]
                           VMTR_GSGAM2_pl (:,:,l),   & !--- [IN]
                           VMTR_PHI_pl    (:,:,l),   & !--- [IN]
                           VMTR_C2Wfact_pl(:,:,:,l)  ) !--- [IN]

             call thrmdyn_th( ADM_gall_pl, th_pl(:,:,l), tem_pl(:,:,l), pre_pl(:,:,l) )

             call thrmdyn_eth( ADM_gall_pl, eth_pl(:,:,l), ein_pl(:,:,l), pre_pl(:,:,l), rho_pl(:,:,l) )

          enddo

       pregd_pl(:,:,:) = ( pre_pl(:,:,:) - pre_bs_pl(:,:,:) ) * VMTR_GSGAM2_pl(:,:,:)
       rhogd_pl(:,:,:) = ( rho_pl(:,:,:) - rho_bs_pl(:,:,:) ) * VMTR_GSGAM2_pl(:,:,:)

       endif

       !------------------------------------------------------------------------
       !> LARGE step
       !------------------------------------------------------------------------

       !--- calculation of advection tendency including Coriolis force
       call src_advection_convergence_v( vx,      vx_pl,      & !--- [IN]
                                         vy,      vy_pl,      & !--- [IN]
                                         vz,      vz_pl,      & !--- [IN]
                                         w,       w_pl,       & !--- [IN]
                                         prog(:,:,:,I_RHOG  ), prog_pl(:,:,:,I_RHOG  ), & !--- [IN]
                                         prog(:,:,:,I_RHOGVX), prog_pl(:,:,:,I_RHOGVX), & !--- [IN]
                                         prog(:,:,:,I_RHOGVY), prog_pl(:,:,:,I_RHOGVY), & !--- [IN]
                                         prog(:,:,:,I_RHOGVZ), prog_pl(:,:,:,I_RHOGVZ), & !--- [IN]
                                         prog(:,:,:,I_RHOGW ), prog_pl(:,:,:,I_RHOGW ), & !--- [IN]
                                         gtend(:,:,:,I_RHOGVX), gtend_pl(:,:,:,I_RHOGVX), & !--- [OUT]
                                         gtend(:,:,:,I_RHOGVY), gtend_pl(:,:,:,I_RHOGVY), & !--- [OUT]
                                         gtend(:,:,:,I_RHOGVZ), gtend_pl(:,:,:,I_RHOGVZ), & !--- [OUT]
                                         gtend(:,:,:,I_RHOGW ), gtend_pl(:,:,:,I_RHOGW )  ) !--- [OUT]

       gtend   (:,:,:,I_RHOG)     = 0.D0
       gtend   (:,:,:,I_RHOGE)    = 0.D0
       gtend   (:,:,:,I_RHOGETOT) = 0.D0
       gtend_pl(:,:,:,I_RHOG)     = 0.D0
       gtend_pl(:,:,:,I_RHOGE)    = 0.D0
       gtend_pl(:,:,:,I_RHOGETOT) = 0.D0

       !---< numerical diffusion term
       if ( NDIFF_LOCATION == 'IN_LARGE_STEP' ) then

          if ( nl == 1 ) then ! only first step
             ftend    (:,:,:,:) = 0.D0
             ftend_pl (:,:,:,:) = 0.D0
             ftendq   (:,:,:,:) = 0.D0
             ftendq_pl(:,:,:,:) = 0.D0

             !------ numerical diffusion
             call numfilter_numerical_hdiff( rho,       rho_pl,       & !--- [IN]
                                             vx,        vx_pl,        & !--- [IN]
                                             vy,        vy_pl,        & !--- [IN]
                                             vz,        vz_pl,        & !--- [IN]
                                             w,         w_pl,         & !--- [IN]
                                             tem,       tem_pl,      & !--- [IN]
                                             q,         q_pl,         & !--- [IN]
                                             ftend (:,:,:,:), ftend_pl (:,:,:,:), & !--- [INOUT]
                                             ftendq(:,:,:,:), ftendq_pl(:,:,:,:)  ) !--- [INOUT]

             if ( NUMFILTER_DOverticaldiff ) then
                call numfilter_numerical_vdiff( rho,       rho_pl,       & !--- [IN]
                                                vx,        vx_pl,        & !--- [IN]
                                                vy,        vy_pl,        & !--- [IN]
                                                vz,        vz_pl,        & !--- [IN]
                                                w,         w_pl,         & !--- [IN]
                                                tem,       tem_pl,       & !--- [IN]
                                                q,         q_pl,         & !--- [IN]
                                                ftend (:,:,:,:), ftend_pl (:,:,:,:), & !--- [INOUT]
                                                ftendq(:,:,:,:), ftendq_pl(:,:,:,:)  ) !--- [INOUT]
             endif

             if ( NUMFILTER_DOrayleigh ) then
                !------ rayleigh damping
                call numfilter_rayleigh_damping( rho,     rho_pl,     & !--- [IN]
                                                 vx,      vx_pl,      & !--- [IN]
                                                 vy,      vy_pl,      & !--- [IN]
                                                 vz,      vz_pl,      & !--- [IN]
                                                 w,       w_pl,       & !--- [IN]
                                                 ftend (:,:,:,:), ftend_pl (:,:,:,:) ) !--- [INOUT]

             endif

          endif

       elseif( NDIFF_LOCATION == 'IN_LARGE_STEP2' ) then

             ftend    (:,:,:,:) = 0.D0
             ftend_pl (:,:,:,:) = 0.D0
             ftendq   (:,:,:,:) = 0.D0
             ftendq_pl(:,:,:,:) = 0.D0

             !------ numerical diffusion
             call numfilter_numerical_hdiff( rho,       rho_pl,       & !--- [IN]
                                             vx,        vx_pl,        & !--- [IN]
                                             vy,        vy_pl,        & !--- [IN]
                                             vz,        vz_pl,        & !--- [IN]
                                             w,         w_pl,         & !--- [IN]
                                             tem,       tem_pl,       & !--- [IN]
                                             q,         q_pl,         & !--- [IN]
                                             ftend (:,:,:,:), ftend_pl (:,:,:,:), & !--- [INOUT]
                                             ftendq(:,:,:,:), ftendq_pl(:,:,:,:)  ) !--- [INOUT]

             if ( NUMFILTER_DOverticaldiff ) then ! [add] H.Yashiro 20120530
                call numfilter_numerical_vdiff( rho,       rho_pl,       & !--- [IN]
                                                vx,        vx_pl,        & !--- [IN]
                                                vy,        vy_pl,        & !--- [IN]
                                                vz,        vz_pl,        & !--- [IN]
                                                w,         w_pl,         & !--- [IN]
                                                tem,       tem_pl,       & !--- [IN]
                                                q,         q_pl,         & !--- [IN]
                                                ftend (:,:,:,:), ftend_pl (:,:,:,:), & !--- [INOUT]
                                                ftendq(:,:,:,:), ftendq_pl(:,:,:,:)  ) !--- [INOUT]
             endif

             if ( NUMFILTER_DOrayleigh ) then ! [add] H.Yashiro 20120530
                !------ rayleigh damping
                call numfilter_rayleigh_damping( rho,     rho_pl,     & !--- [IN]
                                                 vx,      vx_pl,      & !--- [IN]
                                                 vy,      vy_pl,      & !--- [IN]
                                                 vz,      vz_pl,      & !--- [IN]
                                                 w,       w_pl,       & !--- [IN]
                                                 ftend (:,:,:,:), ftend_pl (:,:,:,:) ) !--- [INOUT]

             endif

       else !--- OUT_LARGE
             ftend    (:,:,:,:) = 0.D0
             ftend_pl (:,:,:,:) = 0.D0
             ftendq   (:,:,:,:) = 0.D0
             ftendq_pl(:,:,:,:) = 0.D0
       endif

       ! Smagorinksy-type SGS model [add] A.Noda 10/11/29
       if ( trim(TB_TYPE ) == 'SMG' ) then

          if ( ADM_prc_me /= ADM_prc_pl ) then ! for safety
             th_pl(:,:,:) = 0.D0
             vx_pl(:,:,:) = 0.D0
             vy_pl(:,:,:) = 0.D0
             vz_pl(:,:,:) = 0.D0
             w_pl (:,:,:) = 0.D0
          endif

          call tb_smg_driver( nl,              &
                              rho,   rho_pl,           & !--- [IN] : density
                                         prog(:,:,:,I_RHOG  ), prog_pl(:,:,:,I_RHOG  ), & !--- [IN]
                                         progq(:,:,:,:), progq_pl(:,:,:,:  ), & !--- [IN]
                              vx,    vx_pl,            & !--- [IN] : Vx
                              vy,    vy_pl,            & !--- [IN] : Vy
                              vz,    vz_pl,            & !--- [IN] : Vz
                              w,     w_pl,             & !--- [IN] : w
                              tem,   tem_pl,           & !--- [IN] : temperature
                              q,         q_pl,         & !--- [IN] : q
                              th,        th_pl,        & !--- [IN] : potential temperature 
                                             ftend (:,:,:,I_RHOG    ), ftend_pl (:,:,:,I_RHOG    ), & !--- [INOUT]
                                             ftend (:,:,:,I_RHOGVX  ), ftend_pl (:,:,:,I_RHOGVX  ), & !--- [INOUT]
                                             ftend (:,:,:,I_RHOGVY  ), ftend_pl (:,:,:,I_RHOGVY  ), & !--- [INOUT]
                                             ftend (:,:,:,I_RHOGVZ  ), ftend_pl (:,:,:,I_RHOGVZ  ), & !--- [INOUT]
                                             ftend (:,:,:,I_RHOGW   ), ftend_pl (:,:,:,I_RHOGW   ), & !--- [INOUT]
                                             ftend (:,:,:,I_RHOGE   ), ftend_pl (:,:,:,I_RHOGE   ), & !--- [INOUT]
                                             ftend (:,:,:,I_RHOGETOT), ftend_pl (:,:,:,I_RHOGETOT), & !--- [INOUT]
                                             ftendq(:,:,:,:),          ftendq_pl(:,:,:,:)           ) !--- [INOUT]
       endif

       !--- Nudging routines [add] Y.Niwa 08/09/09
       if ( FLAG_NUDGING ) then

          if ( nl == 1 ) then
             call ndg_update_var
          endif

          if ( nl == num_of_iteration_lstep ) then
             ndgtend_out = .true.
          else
             ndgtend_out = .false.
          endif

          call ndg_nudging_uvtp( rho,       rho_pl,       & !--- [IN]
                                 vx,        vx_pl,        & !--- [IN]
                                 vy,        vy_pl,        & !--- [IN]
                                 vz,        vz_pl,        & !--- [IN]
                                 w,         w_pl,         & !--- [IN]
                                 tem,       tem_pl,       & !--- [IN]
                                 pre,       pre_pl,       & !--- [IN]
                                             ftend (:,:,:,I_RHOGVX  ), ftend_pl (:,:,:,I_RHOGVX  ), & !--- [INOUT]
                                             ftend (:,:,:,I_RHOGVY  ), ftend_pl (:,:,:,I_RHOGVY  ), & !--- [INOUT]
                                             ftend (:,:,:,I_RHOGVZ  ), ftend_pl (:,:,:,I_RHOGVZ  ), & !--- [INOUT]
                                             ftend (:,:,:,I_RHOGW   ), ftend_pl (:,:,:,I_RHOGW   ), & !--- [INOUT]
                                             ftend (:,:,:,I_RHOGE   ), ftend_pl (:,:,:,I_RHOGE   ), & !--- [INOUT]
                                             ftend (:,:,:,I_RHOGETOT), ftend_pl (:,:,:,I_RHOGETOT), & !--- [INOUT]
                                 ndgtend_out         ) !--- [IN] ( tendency out )
       endif

       !--- sum the large step tendency ( advection + coriolis + num.diff.,SGS,nudge )
       gtend   (:,:,:,:) = gtend   (:,:,:,:) + ftend   (:,:,:,:)
       gtend_pl(:,:,:,:) = gtend_pl(:,:,:,:) + ftend_pl(:,:,:,:)

       !------------------------------------------------------------------------
       !> SMALL step
       !------------------------------------------------------------------------
       if ( nl /= 1 ) then ! update split values
          prog_split   (:,:,:,:) = prog0   (:,:,:,:) - prog   (:,:,:,:)
          prog_split_pl(:,:,:,:) = prog0_pl(:,:,:,:) - prog_pl(:,:,:,:)
       else
          prog_split   (:,:,:,:) = 0.D0
          prog_split_pl(:,:,:,:) = 0.D0
       endif

       !------ Core routine for small step
       !------    1. By this subroutine, prog variables 
       !------       ( rho,.., rhoge ) are calculated through
       !------       the 'num_of_iteration_sstep(nl)'-th times small step.
       !------    2. grho, grhogvx, ..., and  grhoge has the large step
       !------       tendencies initially, however,
       !------       they are re-used in this subroutine.
       !------
       if ( TIME_SPLIT ) then
          small_step_ite = num_of_iteration_sstep(nl)
          small_step_dt  = TIME_DTS
       else
          small_step_ite = 1
          small_step_dt  = TIME_DTL / (num_of_iteration_lstep+1-nl)
       endif

       call vi_small_step( &
                           prog(:,:,:,I_RHOG  ),prog_pl(:,:,:,I_RHOG  ), &
                           prog(:,:,:,I_RHOGVX),prog_pl(:,:,:,I_RHOGVX), &
                           prog(:,:,:,I_RHOGVY),prog_pl(:,:,:,I_RHOGVY), &
                           prog(:,:,:,I_RHOGVZ),prog_pl(:,:,:,I_RHOGVZ), &
                           prog(:,:,:,I_RHOGW ),prog_pl(:,:,:,I_RHOGW ), &
                           prog(:,:,:,I_RHOGE ),prog_pl(:,:,:,I_RHOGE ), &
!                           rhog,         rhog_pl,         & !--- [INOUT] prog value
!                           rhogvx,       rhogvx_pl,       & !--- [INOUT]
!                           rhogvy,       rhogvy_pl,       & !--- [INOUT]
!                           rhogvz,       rhogvz_pl,       & !--- [INOUT]
!                           rhogw,        rhogw_pl,        & !--- [INOUT]
!                           rhoge,        rhoge_pl,        & !--- [INOUT]
                           vx,           vx_pl,           & !--- [IN] diagnostic value
                           vy,           vy_pl,           & !--- [IN]
                           vz,           vz_pl,           & !--- [IN]
                           eth,          eth_pl,          & !--- [IN]
                           rhogd,        rhogd_pl,        & !--- [IN]
                           pregd,        pregd_pl,        & !--- [IN]
                           gtend(:,:,:,I_RHOG  ), gtend_pl(:,:,:,I_RHOG  ), &
                           gtend(:,:,:,I_RHOGVX  ), gtend_pl(:,:,:,I_RHOGVX  ), &
                           gtend(:,:,:,I_RHOGVY  ), gtend_pl(:,:,:,I_RHOGVY  ), &
                           gtend(:,:,:,I_RHOGVZ  ), gtend_pl(:,:,:,I_RHOGVZ  ), &
                           gtend(:,:,:,I_RHOGW  ), gtend_pl(:,:,:,I_RHOGW  ), &
                           gtend(:,:,:,I_RHOGE  ), gtend_pl(:,:,:,I_RHOGE  ), &
                           gtend(:,:,:,I_RHOGETOT  ), gtend_pl(:,:,:,I_RHOGETOT  ), &
!                           grhog,        grhog_pl,        & !--- [IN] large step tendency
!                           grhogvx,      grhogvx_pl,      & !--- [IN]
!                           grhogvy,      grhogvy_pl,      & !--- [IN]
!                           grhogvz,      grhogvz_pl,      & !--- [IN]
!                           grhogw,       grhogw_pl,       & !--- [IN]
!                           grhoge,       grhoge_pl,       & !--- [IN]
!                           grhogetot,    grhogetot_pl,    & !--- [IN]
                           prog_split(:,:,:,I_RHOG  ),prog_split_pl(:,:,:,I_RHOG  ), &
                           prog_split(:,:,:,I_RHOGVX),prog_split_pl(:,:,:,I_RHOGVX), &
                           prog_split(:,:,:,I_RHOGVY),prog_split_pl(:,:,:,I_RHOGVY), &
                           prog_split(:,:,:,I_RHOGVZ),prog_split_pl(:,:,:,I_RHOGVZ), &
                           prog_split(:,:,:,I_RHOGW ),prog_split_pl(:,:,:,I_RHOGW ), &
                           prog_split(:,:,:,I_RHOGE ),prog_split_pl(:,:,:,I_RHOGE ), &
!                           rhog_split,   rhog_split_pl,   & !--- [INOUT] split value
!                           rhogvx_split, rhogvx_split_pl, & !--- [INOUT]
!                           rhogvy_split, rhogvy_split_pl, & !--- [INOUT]
!                           rhogvz_split, rhogvz_split_pl, & !--- [INOUT]
!                           rhogw_split,  rhogw_split_pl,  & !--- [INOUT]
!                           rhoge_split,  rhoge_split_pl,  & !--- [INOUT]
                           v_mean_c,     v_mean_c_pl,     & !--- [OUT] mean value
                           small_step_ite,                & !--- [IN]
                           small_step_dt                  ) !--- [IN]

       !------------------------------------------------------------------------
       !>  Tracer advection
       !------------------------------------------------------------------------
       if ( TRC_ADV_TYPE == 'MIURA2004' ) then

          if ( nl == num_of_iteration_lstep ) then

             call src_update_tracer( TRC_VMAX,                                              & !--- [IN]
                                     progq(:,:,:,:), progq_pl(:,:,:,:), & !--- [INOUT]
                                     prog0(:,:,:,I_RHOG  ), prog0_pl(:,:,:,I_RHOG  ), & !--- [IN]
                                     v_mean_c(:,:,:,I_rhog),   v_mean_c_pl(:,:,:,I_rhog),   & !--- [IN]
                                     v_mean_c(:,:,:,I_rhogvx), v_mean_c_pl(:,:,:,I_rhogvx), & !--- [IN]
                                     v_mean_c(:,:,:,I_rhogvy), v_mean_c_pl(:,:,:,I_rhogvy), & !--- [IN]
                                     v_mean_c(:,:,:,I_rhogvz), v_mean_c_pl(:,:,:,I_rhogvz), & !--- [IN]
                                     v_mean_c(:,:,:,I_rhogw),  v_mean_c_pl(:,:,:,I_rhogw),  & !--- [IN]
                                     ftend (:,:,:,I_RHOG    ), ftend_pl (:,:,:,I_RHOG    ), & !--- [IN]
                                     TIME_DTL                                               ) !--- [IN]

             progq(:,:,:,:) = progq(:,:,:,:) + TIME_DTL * ftendq(:,:,:,:) ! update rhogq by viscosity

             progq(:,ADM_kmin-1,:,:) = 0.D0
             progq(:,ADM_kmax+1,:,:) = 0.D0

             if ( ADM_prc_pl == ADM_prc_me ) then
                progq_pl(:,:,:,:) = progq_pl(:,:,:,:) + TIME_DTL * ftendq_pl(:,:,:,:)

                progq_pl(:,ADM_kmin-1,:,:) = 0.D0
                progq_pl(:,ADM_kmax+1,:,:) = 0.D0
             endif

             !<---- I don't recommend adding the hyperviscosity term
             !<---- because of numerical instability in this case. ( H.Tomita )

          endif ! Last large step only

       elseif( TRC_ADV_TYPE == 'DEFAULT' ) then

          do nq = 1, TRC_VMAX

             call src_advection_convergence( v_mean_c(:,:,:,I_rhogvx), v_mean_c_pl(:,:,:,I_rhogvx), & !--- [IN]
                                             v_mean_c(:,:,:,I_rhogvy), v_mean_c_pl(:,:,:,I_rhogvy), & !--- [IN]
                                             v_mean_c(:,:,:,I_rhogvz), v_mean_c_pl(:,:,:,I_rhogvz), & !--- [IN]
                                             v_mean_c(:,:,:,I_rhogw),  v_mean_c_pl(:,:,:,I_rhogw),  & !--- [IN]
                                             q(:,:,:,nq),      q_pl(:,:,:,nq),                      & !--- [IN]
                                             gtendq(:,:,:,nq), gtendq_pl(:,:,:,nq),                 & !--- [OUT]
                                             I_SRC_default                                          ) !--- [IN]  [mod] H.Yashiro 20120530

            progq(:,:,:,:) = progq0(:,:,:,:)                      &
                                   + ( num_of_iteration_sstep(nl) * TIME_DTS ) * ( gtendq(:,:,:,:) + ftendq(:,:,:,:) )

             progq(:,ADM_kmin-1,:,:) = 0.D0
             progq(:,ADM_kmax+1,:,:) = 0.D0

             if ( ADM_prc_pl == ADM_prc_me ) then
                      progq_pl(:,:,:,:) = progq0_pl(:,:,:,:)                         &
                                          + ( num_of_iteration_sstep(nl) * TIME_DTS )       &
                                          * ( gtendq_pl(:,:,:,:) + ftendq_pl(:,:,:,:) )

                progq_pl(:,ADM_kmin-1,:,:) = 0.D0
                progq_pl(:,ADM_kmax+1,:,:) = 0.D0
             endif

          enddo ! tracer LOOP

       endif

       !--- TKE fixer ( TKE >= 0.D0 )
       ! 2011/08/16 M.Satoh [comment] need this fixer for every small time steps
       if ( I_TKE >= 0 ) then
          if ( TRC_ADV_TYPE == 'DEFAULT' .OR. nl == num_of_iteration_lstep ) then
             do l  = 1, ADM_lall
                do k  = 1, ADM_kall
                do ij = 1, ADM_gall
                   TKEg_corr = TKE_MIN * VMTR_GSGAM2(ij,k,l) - progq(ij,k,l,I_TKE)

                   if ( TKEg_corr >= 0.D0 ) then
                      prog(ij,k,l,I_RHOGE)       = prog(ij,k,l,I_RHOGE)       - TKEg_corr
                      progq(ij,k,l,I_TKE) = progq(ij,k,l,I_TKE) + TKEg_corr
                   endif
                enddo
                enddo
             enddo

             if ( ADM_prc_pl == ADM_prc_me ) then
                do l  = 1, ADM_lall_pl
                   do k  = 1, ADM_kall
                   do ij = 1, ADM_gall_pl
                      TKEg_corr = TKE_MIN * VMTR_GSGAM2_pl(ij,k,l) - progq_pl(ij,k,l,I_TKE)

                      if ( TKEg_corr >= 0.D0 ) then
                         prog_pl(ij,k,l,I_RHOGE)       = prog_pl(ij,k,l,I_RHOGE)       - TKEg_corr
                         progq_pl(ij,k,l,I_TKE) = progq_pl(ij,k,l,I_TKE) + TKEg_corr
                      endif
                   enddo
                   enddo
                enddo
             endif

          endif
       endif

       !------ Update
       if ( nl /= num_of_iteration_lstep ) then
          ! communication
          call COMM_data_transfer( prog, prog_pl )

          prog(suf(ADM_gall_1d,1),:,:,:) = prog(suf(ADM_gmax+1,ADM_gmin),:,:,:)
          prog(suf(1,ADM_gall_1d),:,:,:) = prog(suf(ADM_gmin,ADM_gmax+1),:,:,:)
       endif

    enddo !--- large step 

    ! 2011/08/16 M.Satoh move from above =>
    ! 2010/05/06 M.Satoh (comment on TDK)
    ! 2011/08/16 M.Satoh bug fix for TDK: conv => tendency
    ! 2011/08/16 M.Satoh
    !    use rhogq-rhogq_old to calculate qconv & qtendency
    ! Kuo param.    : total convergence of water vapor [integ over time]
    ! Tiedtke scheme: tendency of water vapor [per time]
    if ( CP_TYPE == 'KUO' ) then
       diagvar(:,:,:,I_RHOGQV_CONV) = progq(:,:,:,I_QV) - progq0(:,:,:,I_QV)
       if ( ADM_prc_pl == ADM_prc_me ) then
          diagvar_pl(:,:,:,I_RHOGQV_CONV) = progq_pl(:,:,:,I_QV) - progq0_pl(:,:,:,I_QV)
       endif
    endif

    if ( CP_TYPE == 'TDK' ) then
       ! 2011.08.16 M.Satoh,bug fix: conv => tendency
       ! qv_dyn_tend = v grad q
       !             = ( div(rho v q) - div(rho v)*q )/rho
       diagvar(:,:,:,I_QV_DYN_TEND) = ( ( progq(:,:,:,I_QV)-progq0(:,:,:,I_QV) ) &
                                      - ( prog(:,:,:,I_RHOG)-prog0(:,:,:,I_RHOG) )             &
                                        * progq(:,:,:,I_QV) / prog(:,:,:,I_RHOG)           & ! = q(:,:,:,I_QV)
                                      ) / TIME_DTL / prog(:,:,:,I_RHOG)
       if ( ADM_prc_pl == ADM_prc_me ) then
          diagvar_pl(:,:,:,I_QV_DYN_TEND) = ( ( progq_pl(:,:,:,I_QV)-progq0_pl(:,:,:,I_QV) ) &
                                            - ( prog_pl(:,:,:,I_RHOG)-prog0_pl(:,:,:,I_RHOG) )             &
                                              * progq_pl(:,:,:,I_QV) / prog_pl(:,:,:,I_RHOG)           & ! = q_pl(:,:,:,I_QV)
                                            ) / TIME_DTL / prog_pl(:,:,:,I_RHOG)
       endif
    endif
    ! <= 2011/08/16 M.Satoh move from above

    call prgvar_set( prog(:,:,:,I_RHOG),   prog_pl(:,:,:,I_RHOG),   & !--- [IN]
                     prog(:,:,:,I_RHOGVX), prog_pl(:,:,:,I_RHOGVX), & !--- [IN]
                     prog(:,:,:,I_RHOGVY), prog_pl(:,:,:,I_RHOGVY), & !--- [IN]
                     prog(:,:,:,I_RHOGVZ), prog_pl(:,:,:,I_RHOGVZ), & !--- [IN]
                     prog(:,:,:,I_RHOGW),  prog_pl(:,:,:,I_RHOGW),  & !--- [IN]
                     prog(:,:,:,I_RHOGE),  prog_pl(:,:,:,I_RHOGE),  & !--- [IN]
                     progq(:,:,:,:),       progq_pl(:,:,:,:),       & !--- [IN]
                     0                                                          ) !--- [IN]

#ifdef PAPI_OPS
    ! <-- [add] PAPI R.Yoshida 20121022
    !call PAPIF_flips( PAPI_real_time_i, PAPI_proc_time_i, PAPI_flpins, PAPI_mflins, PAPI_check )
    call PAPIF_flops( PAPI_real_time_o, PAPI_proc_time_o, PAPI_flpops, PAPI_mflops, PAPI_check )
#endif

    return
  end subroutine dynstep

  !-----------------------------------------------------------------------------
  subroutine dynstep2
    use mod_adm, only: &
       ADM_prc_me,  &
       ADM_prc_pl,  &
       ADM_gall,    &
       ADM_gall_pl, &
       ADM_lall,    &
       ADM_lall_pl, &
       ADM_kall,    &
       ADM_kmax,    &
       ADM_kmin
    use mod_cnst, only: &
       CNST_RAIR, &
       CNST_RVAP, &
       CNST_CV
    use mod_time, only: &
       TIME_DTL
    use mod_grd, only: &
       GRD_afac, &
       GRD_bfac
    use mod_oprt, only : &
       OPRT_horizontalize_vec
    use mod_vmtr, only: &
       VMTR_GSGAM2,     &
       VMTR_GSGAM2_pl,  &
       VMTR_GSGAM2H,    &
       VMTR_GSGAM2H_pl, &
       VMTR_PHI,        &
       VMTR_PHI_pl,     &
       VMTR_C2Wfact,    &
       VMTR_C2Wfact_pl
    use mod_runconf, only: &
       TRC_VMAX,       &
       I_QV,           &
       NQW_STR,        &
       NQW_END,        &
       CVW,            &
       NDIFF_LOCATION
    use mod_bsstate, only: &
       tem_bs, tem_bs_pl
    use mod_bndcnd, only: &
       bndcnd_all
    use mod_prgvar, only: &
       prgvar_set,&
       prgvar_get
    use mod_numfilter, only: &
       NUMFILTER_DOrayleigh,       & ! [add] H.Yashiro 20120530
       NUMFILTER_DOverticaldiff,   & ! [add] H.Yashiro 20120530
       numfilter_rayleigh_damping, &
       numfilter_numerical_hdiff,  &
       numfilter_numerical_vdiff
    implicit none

!    --- forcing tendensy of rhog  ( G^{1/2} X gamma2 )
!    real(8) :: frhog   (ADM_gall,   ADM_kall,ADM_lall   )
!    real(8) :: frhog_pl(ADM_gall_pl,ADM_kall,ADM_lall_pl)
!    
!    --- forcing tendensy of rhogvx  ( G^{1/2} X gamma2 )
!    real(8) :: frhogvx   (ADM_gall,   ADM_kall,ADM_lall   )
!    real(8) :: frhogvx_pl(ADM_gall_pl,ADM_kall,ADM_lall_pl)
!    
!    --- forcing tendensy of rhogvy  ( G^{1/2} X gamma2 )
!    real(8) :: frhogvy   (ADM_gall,   ADM_kall,ADM_lall   )
!    real(8) :: frhogvy_pl(ADM_gall_pl,ADM_kall,ADM_lall_pl)
!    
!    --- forcing tendensy of rhogvz  ( G^{1/2} X gamma2 )
!    real(8) :: frhogvz   (ADM_gall,   ADM_kall,ADM_lall   )
!    real(8) :: frhogvz_pl(ADM_gall_pl,ADM_kall,ADM_lall_pl)
!    
!    --- forcing tendensy of rhogw  ( G^{1/2} X gamma2 )
!    real(8) :: frhogw(ADM_gall,   ADM_kall,ADM_lall   )
!    real(8) :: frhogw_pl(ADM_gall_pl,ADM_kall,ADM_lall_pl)
!    
!    --- forcing tendensy of rhoge  ( G^{1/2} X gamma2 )
!    real(8) :: frhoge(ADM_gall,   ADM_kall,ADM_lall   )
!    real(8) :: frhoge_pl(ADM_gall_pl,ADM_kall,ADM_lall_pl)
!    
!    --- tendensy of rhogetot  ( G^{1/2} X gamma2 )
!    real(8) :: frhogetot(ADM_gall,   ADM_kall,ADM_lall   )
!    real(8) :: frhogetot_pl(ADM_gall_pl,ADM_kall,ADM_lall_pl)
!    
!    --- forcing tendensy of rhogq  ( G^{1/2} X gamma2 )
!    real(8) :: frhogq(ADM_gall,ADM_kall,ADM_lall,TRC_VMAX)
!    real(8) :: frhogq_pl(ADM_gall_pl,ADM_kall,ADM_lall_pl,TRC_VMAX)
!
!    --- rho X ( G^{1/2} X gamma2 )
!    real(8) :: rhog(ADM_gall,   ADM_kall,ADM_lall   )
!    real(8) :: rhog_pl(ADM_gall_pl,ADM_kall,ADM_lall_pl)
!    
!    --- rho X ( G^{1/2} X gamma2 ) X vx
!    real(8) :: rhogvx(ADM_gall,   ADM_kall,ADM_lall   )
!    real(8) :: rhogvx_pl(ADM_gall_pl,ADM_kall,ADM_lall_pl)
!    
!    --- rho X ( G^{1/2} X gamma2 ) X vy
!    real(8) :: rhogvy(ADM_gall,   ADM_kall,ADM_lall   )
!    real(8) :: rhogvy_pl(ADM_gall_pl,ADM_kall,ADM_lall_pl)
!    
!    --- rho X ( G^{1/2} X gamma2 ) X vz
!    real(8) :: rhogvz(ADM_gall,   ADM_kall,ADM_lall   )
!    real(8) :: rhogvz_pl(ADM_gall_pl,ADM_kall,ADM_lall_pl)
!    
!    --- rho X ( G^{1/2} X gamma2 ) X w
!    real(8) :: rhogw(ADM_gall,   ADM_kall,ADM_lall   )
!    real(8) :: rhogw_pl(ADM_gall_pl,ADM_kall,ADM_lall_pl)
!    
!    --- rho X ( G^{1/2} X gamma2 ) X ein
!    real(8) :: rhoge(ADM_gall,   ADM_kall,ADM_lall   )
!    real(8) :: rhoge_pl(ADM_gall_pl,ADM_kall,ADM_lall_pl)
!    
!    --- rho X ( G^{1/2} X gamma2 ) X q
!    real(8) :: rhogq(ADM_gall,ADM_kall,ADM_lall,TRC_VMAX)
!    real(8) :: rhogq_pl(ADM_gall_pl,ADM_kall,ADM_lall_pl,TRC_VMAX)
!    
!    --- density ( physical )
!    real(8) :: rho(ADM_gall,   ADM_kall,ADM_lall   )
!    real(8) :: rho_pl(ADM_gall_pl,ADM_kall,ADM_lall_pl)
!    
!    --- horizontal velocity_x  ( physical )
!    real(8) :: vx(ADM_gall,   ADM_kall,ADM_lall   )
!    real(8) :: vx_pl(ADM_gall_pl,ADM_kall,ADM_lall_pl)
!    
!    --- horizontal velocity_y  ( physical )
!    real(8) :: vy(ADM_gall,   ADM_kall,ADM_lall   )
!    real(8) :: vy_pl(ADM_gall_pl,ADM_kall,ADM_lall_pl)
!    
!    --- horizontal velocity_z  ( physical )
!    real(8) :: vz(ADM_gall,   ADM_kall,ADM_lall   )
!    real(8) :: vz_pl(ADM_gall_pl,ADM_kall,ADM_lall_pl)
!    
!    --- vertical velocity ( physical )
!    real(8) :: w(ADM_gall,   ADM_kall,ADM_lall   )
!    real(8) :: w_pl(ADM_gall_pl,ADM_kall,ADM_lall_pl)
!    
!    --- [IN]ternal energy  ( physical )
!    real(8) :: ein(ADM_gall,   ADM_kall,ADM_lall   )
!    real(8) :: ein_pl(ADM_gall_pl,ADM_kall,ADM_lall_pl)
!    
!    --- mass concentration of water substance ( physical )
!    real(8) :: q(ADM_gall,ADM_kall,ADM_lall,TRC_VMAX)
!    real(8) :: q_pl(ADM_gall_pl,ADM_kall,ADM_lall_pl,TRC_VMAX)
!
!    --- pressure ( physical )
!    real(8) :: pre(ADM_gall,   ADM_kall,ADM_lall   )
!    real(8) :: pre_pl(ADM_gall_pl,ADM_kall,ADM_lall_pl)
!    
!    --- temperature ( physical )
!    real(8) :: tem(ADM_gall,   ADM_kall,ADM_lall   )
!    real(8) :: tem_pl(ADM_gall_pl,ADM_kall,ADM_lall_pl)
!    
!    --- temperature deviation from the base state ( physical )
!    real(8) :: temd(ADM_gall,   ADM_kall,ADM_lall   )
!    real(8) :: temd_pl(ADM_gall_pl,ADM_kall,ADM_lall_pl)
!
!    --- temporary variables
!    real(8) :: qd      (ADM_gall,   ADM_kall,ADM_lall   )
!    real(8) :: qd_pl   (ADM_gall_pl,ADM_kall,ADM_lall_pl)
!    real(8) :: rrhog   (ADM_gall,   ADM_kall,ADM_lall   )
!    real(8) :: rrhog_pl(ADM_gall_pl,ADM_kall,ADM_lall_pl)
!    real(8) :: cv      (ADM_gall,   ADM_kall,ADM_lall   )
!    real(8) :: cv_pl   (ADM_gall_pl,ADM_kall,ADM_lall_pl)
!
!    integer :: ij, k ,l, nq
    !---------------------------------------------------------------------------

!    if ( NDIFF_LOCATION == 'OUT_LARGE_STEP' ) then
!
!       !--- get from prg0
!       call prgvar_get( rhog,   rhog_pl,   & !--- [OUT]
!                        rhogvx, rhogvx_pl, & !--- [OUT]
!                        rhogvy, rhogvy_pl, & !--- [OUT]
!                        rhogvz, rhogvz_pl, & !--- [OUT]
!                        rhogw,  rhogw_pl,  & !--- [OUT]
!                        rhoge,  rhoge_pl,  & !--- [OUT]
!                        rhogq,  rhogq_pl,  & !--- [OUT]
!                        0                  ) !--- [IN]
!
!       !---< Generate diagnostic values and set the boudary conditions
!       do l = 1, ADM_lall
!          do k = 1, ADM_kall
!             do ij = 1, ADM_gall
!                rrhog(ij,k,l) = 1.D0 / rhog(ij,k,l)
!             enddo
!             do ij = 1, ADM_gall
!               rho(ij,k,l) = rhog(ij,k,l) / VMTR_GSGAM2(ij,k,l)
!             enddo
!             do ij = 1, ADM_gall
!                ein(ij,k,l) = rhoge(ij,k,l) * rrhog(ij,k,l)
!             enddo
!             do ij = 1, ADM_gall
!                vx(ij,k,l) = rhogvx(ij,k,l) * rrhog(ij,k,l)
!             enddo
!             do ij = 1, ADM_gall
!                vy(ij,k,l) = rhogvy(ij,k,l) * rrhog(ij,k,l)
!             enddo
!             do ij = 1, ADM_gall
!                vz(ij,k,l) = rhogvz(ij,k,l) * rrhog(ij,k,l)
!             enddo
!          enddo
!          do nq = 1, TRC_VMAX
!             do k = 1, ADM_kall
!                do ij = 1, ADM_gall
!                   q(ij,k,l,nq) = rhogq(ij,k,l,nq) * rrhog(ij,k,l)
!                enddo
!             enddo
!          enddo
!          do k = 1, ADM_kall
!             do ij = 1, ADM_gall
!                qd(ij,k,l) = 1.D0
!             enddo
!          enddo
!          do nq = NQW_STR, NQW_END
!             do k  = 1, ADM_kall
!             do ij = 1, ADM_gall
!                qd(ij,k,l) = qd(ij,k,l) - q(ij,k,l,nq)
!             enddo
!             enddo
!          enddo
!          do k  = 1, ADM_kall
!             do ij = 1, ADM_gall
!                cv(ij,k,l) = qd(ij,k,l) * CNST_CV
!             enddo
!          enddo
!          do nq = NQW_STR, NQW_END
!             do k  = 1, ADM_kall
!             do ij = 1, ADM_gall
!                cv(ij,k,l) = cv(ij,k,l) + q(ij,k,l,nq) * CVW(nq)
!             enddo
!             enddo
!          enddo
!          do k = 1, ADM_kall
!             do ij = 1, ADM_gall
!                tem(ij,k,l) = ein(ij,k,l) / cv(ij,k,l)
!             enddo
!             do ij = 1, ADM_gall
!                pre(ij,k,l) = rho(ij,k,l) * tem(ij,k,l) * ( qd(ij,k,l)*CNST_RAIR + q(ij,k,l,I_QV)*CNST_RVAP )
!             enddo
!          enddo
!          do k = ADM_kmin+1, ADM_kmax
!             do ij = 1, ADM_gall
!                w(ij,k,l) = rhogw(ij,k,l) &
!                          / ( 0.5D0 * ( GRD_afac(k) * rho(ij,k  ,l) &
!                                      + GRD_bfac(k) * rho(ij,k-1,l) ) * VMTR_GSGAM2H(ij,k,l) )
!             enddo
!          enddo
!
!          !--- boundary conditions
!          call bndcnd_all( ADM_gall,            & !--- [IN]
!                           vx    (:,:,l),       & !--- [INOUT]
!                           vy    (:,:,l),       & !--- [INOUT]
!                           vz    (:,:,l),       & !--- [INOUT]
!                           w     (:,:,l),       & !--- [INOUT]
!                           tem   (:,:,l),       & !--- [INOUT]
!                           rho   (:,:,l),       & !--- [INOUT]
!                           pre   (:,:,l),       & !--- [INOUT]
!                           ein   (:,:,l),       & !--- [INOUT]
!                           rhog  (:,:,l),       & !--- [INOUT]
!                           rhogvx(:,:,l),       & !--- [INOUT]
!                           rhogvy(:,:,l),       & !--- [INOUT]
!                           rhogvz(:,:,l),       & !--- [INOUT]
!                           rhogw (:,:,l),       & !--- [INOUT]
!                           rhoge (:,:,l),       & !--- [INOUT]
!                           VMTR_PHI    (:,:,l), & !--- [IN]
!                           VMTR_GSGAM2 (:,:,l), & !--- [IN]
!                           VMTR_GSGAM2H(:,:,l), & !--- [IN]
!                           VMTR_GZXH   (:,:,l), & !--- [IN]
!                           VMTR_GZYH   (:,:,l), & !--- [IN]
!                           VMTR_GZZH   (:,:,l)  ) !--- [IN]
!
!             !--- perturbations ( pred, rhod, temd )
!          do k = 1, ADM_kall
!             do ij = 1, ADM_gall
!                temd(ij,k,l) = tem(ij,k,l) - tem_bs(ij,k,l)
!             enddo
!          enddo
!
!       enddo ! region LOOP
!
!       if ( ADM_prc_me == ADM_prc_pl ) then
!
!          do l = 1, ADM_lall_pl
!             do k = 1, ADM_kall
!                do ij = 1, ADM_gall_pl
!                   rrhog_pl(ij,k,l) = 1.D0 / rhog_pl(ij,k,l)
!                enddo
!                do ij = 1, ADM_gall_pl
!                  rho_pl(ij,k,l)  = rhog_pl(ij,k,l) / VMTR_GSGAM2_pl(ij,k,l)
!                enddo
!                do ij = 1, ADM_gall_pl
!                   ein_pl(ij,k,l) = rhoge_pl(ij,k,l)  * rrhog_pl(ij,k,l)
!                enddo
!                do ij = 1, ADM_gall_pl
!                   vx_pl(ij,k,l)  = rhogvx_pl(ij,k,l) * rrhog_pl(ij,k,l)
!                enddo
!                do ij = 1, ADM_gall_pl
!                   vy_pl(ij,k,l)  = rhogvy_pl(ij,k,l) * rrhog_pl(ij,k,l)
!                enddo
!                do ij = 1, ADM_gall_pl
!                   vz_pl(ij,k,l)  = rhogvz_pl(ij,k,l) * rrhog_pl(ij,k,l)
!                enddo
!             enddo
!             do nq = 1, TRC_VMAX
!                do k = 1, ADM_kall
!                   do ij = 1, ADM_gall_pl
!                      q_pl(ij,k,l,nq) = rhogq_pl(ij,k,l,nq) * rrhog_pl(ij,k,l)
!                   enddo
!                enddo
!             enddo
!             do k = 1, ADM_kall
!                do ij = 1, ADM_gall_pl
!                   qd_pl(ij,k,l) = 1.D0
!                enddo
!             enddo
!             do nq = NQW_STR, NQW_END
!                do k = 1, ADM_kall
!                   do ij = 1, ADM_gall_pl
!                      qd_pl(ij,k,l) = qd_pl(ij,k,l) - q_pl(ij,k,l,nq)
!                   enddo
!                enddo
!             enddo
!             do k = 1, ADM_kall
!                do ij = 1, ADM_gall_pl
!                   cv_pl(ij,k,l) = qd_pl(ij,k,l) * CNST_CV
!                enddo
!             enddo
!             do nq = NQW_STR, NQW_END
!                do k = 1, ADM_kall
!                   do ij = 1, ADM_gall_pl
!                      cv_pl(ij,k,l) = cv_pl(ij,k,l) + q_pl(ij,k,l,nq) * CVW(nq)
!                   enddo
!                enddo
!             enddo
!             do k = 1, ADM_kall
!                do ij = 1, ADM_gall_pl
!                   tem_pl(ij,k,l) = ein_pl(ij,k,l) / cv_pl(ij,k,l)
!                enddo
!                do ij = 1, ADM_gall_pl
!                   pre_pl(ij,k,l) = rho_pl(ij,k,l) * tem_pl(ij,k,l) &
!                        * ( qd_pl(ij,k,l)*CNST_RAIR+q_pl(ij,k,l,I_QV)*CNST_RVAP )
!                enddo
!             enddo
!             do k = ADM_kmin+1, ADM_kmax
!                do ij = 1, ADM_gall_pl
!                   w_pl(ij,k,l) = rhogw_pl(ij,k,l) &
!                                / ( 0.5D0 * ( GRD_afac(k) * rho_pl(ij,k  ,l) &
!                                            + GRD_bfac(k) * rho_pl(ij,k-1,l) ) * VMTR_GSGAM2H_pl(ij,k,l) )
!                enddo
!             enddo
!
!             call bndcnd_all( ADM_gall_pl,            & !--- [IN]
!                              vx_pl    (:,:,l),       & !--- [INOUT]
!                              vy_pl    (:,:,l),       & !--- [INOUT]
!                              vz_pl    (:,:,l),       & !--- [INOUT]
!                              w_pl     (:,:,l),       & !--- [INOUT]
!                              tem_pl   (:,:,l),       & !--- [INOUT]
!                              rho_pl   (:,:,l),       & !--- [INOUT]
!                              pre_pl   (:,:,l),       & !--- [INOUT]
!                              ein_pl   (:,:,l),       & !--- [INOUT]
!                              rhog_pl  (:,:,l),       & !--- [INOUT]
!                              rhogvx_pl(:,:,l),       & !--- [INOUT]
!                              rhogvy_pl(:,:,l),       & !--- [INOUT]
!                              rhogvz_pl(:,:,l),       & !--- [INOUT]
!                              rhogw_pl (:,:,l),       & !--- [INOUT]
!                              rhoge_pl (:,:,l),       & !--- [INOUT]
!                              VMTR_PHI_pl   (:,:,l),       & !--- [IN]
!                              VMTR_GSGAM2_pl (:,:,l), & !--- [IN]
!                              VMTR_GSGAM2H_pl(:,:,l), & !--- [IN]
!                              VMTR_GZXH_pl   (:,:,l), & !--- [IN]
!                              VMTR_GZYH_pl   (:,:,l), & !--- [IN]
!                              VMTR_GZZH_pl   (:,:,l)  ) !--- [IN]
!
!             do k = 1, ADM_kall
!                do ij = 1, ADM_gall_pl
!                   temd_pl(ij,k,l) = tem_pl(ij,k,l) - tem_bs_pl(ij,k,l)
!                enddo
!             enddo
!
!          enddo
!       endif
!
!             do l = 1, ADM_lall
!                do k = 1, ADM_kall
!                   do ij = 1, ADM_gall
!                      frhog  (ij,k,l) = 0.D0
!                   enddo
!                   do ij = 1, ADM_gall
!                      frhogvx(ij,k,l) = 0.D0
!                   enddo
!                   do ij = 1, ADM_gall
!                      frhogvy(ij,k,l) = 0.D0
!                   enddo
!                   do ij = 1, ADM_gall
!                      frhogvz(ij,k,l) = 0.D0
!                   enddo
!                   do ij = 1, ADM_gall
!                      frhogw (ij,k,l) = 0.D0
!                   enddo
!                   do ij = 1, ADM_gall
!                      frhoge (ij,k,l) = 0.D0
!                   enddo
!                   do ij = 1, ADM_gall
!                      frhogetot(ij,k,l) = 0.D0
!                   enddo
!                enddo
!             enddo
!             do nq = 1,TRC_VMAX
!             do l = 1, ADM_lall
!                do k = 1, ADM_kall
!                   do ij = 1, ADM_gall
!                      frhogq(ij,k,l,nq) = 0.D0
!                   enddo
!                enddo
!             enddo
!             enddo
!
!             do l = 1, ADM_lall_pl
!                do k = 1, ADM_kall
!                   do ij = 1, ADM_gall_pl
!                      frhog_pl  (ij,k,l) = 0.D0
!                   enddo
!                   do ij = 1, ADM_gall_pl
!                      frhogvx_pl(ij,k,l) = 0.D0
!                   enddo
!                   do ij = 1, ADM_gall_pl
!                      frhogvy_pl(ij,k,l) = 0.D0
!                   enddo
!                   do ij = 1, ADM_gall_pl
!                      frhogvz_pl(ij,k,l) = 0.D0
!                   enddo
!                   do ij = 1, ADM_gall_pl
!                      frhogw_pl (ij,k,l) = 0.D0
!                   enddo
!                   do ij = 1, ADM_gall_pl
!                      frhoge_pl (ij,k,l) = 0.D0
!                   enddo
!                   do ij = 1, ADM_gall_pl
!                      frhogetot_pl(ij,k,l) = 0.D0
!                   enddo
!                enddo
!             enddo
!             do nq = 1, TRC_VMAX
!             do l  = 1, ADM_lall_pl
!                do k = 1, ADM_kall
!                   do ij = 1, ADM_gall_pl
!                      frhogq_pl(ij,k,l,nq) = 0.D0
!                   enddo
!                enddo
!             enddo
!             enddo
!
!             if ( NUMFILTER_DOrayleigh ) then ! [add] H.Yashiro 20120530
!
!             !------ rayleigh damping
!             call numfilter_rayleigh_damping( &
!                  rho, rho_pl,                & !--- [IN]
!                  vx, vx_pl,                  & !--- [IN]
!                  vy, vy_pl,                  & !--- [IN]
!                  vz, vz_pl,                  & !--- [IN]
!                  w, w_pl,                    & !--- [IN]
!                  frhogvx, frhogvx_pl,        & !--- [INOUT]
!                  frhogvy, frhogvy_pl,        & !--- [INOUT]
!                  frhogvz, frhogvz_pl,        & !--- [INOUT]
!                  frhogw, frhogw_pl           ) !--- [INOUT]
!
!             endif
!
!             !------ numerical diffusion
!             call numfilter_numerical_hdiff(  &
!                  rho, rho_pl,                & !--- [IN]
!                  vx, vx_pl,                  & !--- [IN]
!                  vy, vy_pl,                  & !--- [IN]
!                  vz, vz_pl,                  & !--- [IN]
!                  w , w_pl,                   & !--- [IN]
!                  tem,  tem_pl,               & !--- [IN]
!                  q , q_pl,                   & !--- [IN]
!                  frhog, frhog_pl,            & !--- [INOUT]
!                  frhogvx, frhogvx_pl,        & !--- [INOUT]
!                  frhogvy, frhogvy_pl,        & !--- [INOUT]
!                  frhogvz, frhogvz_pl,        & !--- [INOUT]
!                  frhogw , frhogw_pl,         & !--- [INOUT]
!                  frhoge , frhoge_pl,         & !--- [INOUT]
!                  frhogetot , frhogetot_pl,         & !--- [INOUT]
!                  frhogq , frhogq_pl )          !--- [INOUT]
!
!             if ( NUMFILTER_DOverticaldiff ) then ! [add] H.Yashiro 20120530
!
!             call numfilter_numerical_vdiff(  &
!                  rho,   rho_pl,              &  !--- [IN]
!                  vx, vx_pl,                  &  !--- [IN]
!                  vy, vy_pl,                  &  !--- [IN]
!                  vz, vz_pl,                  &  !--- [IN]
!                  w , w_pl,                   &  !--- [IN]
!                  tem, tem_pl,                &  !--- [IN]
!                  q,q_pl,                     &  !--- [IN]
!                  frhog, frhog_pl,            &  !--- [INOUT]
!                  frhogvx, frhogvx_pl,        &  !--- [INOUT]
!                  frhogvy, frhogvy_pl,        &  !--- [INOUT]
!                  frhogvz, frhogvz_pl,        &  !--- [INOUT]
!                  frhogw , frhogw_pl,         &  !--- [INOUT]
!                  frhoge , frhoge_pl,         &  !--- [INOUT]
!                  frhogetot , frhogetot_pl,         & !--- [INOUT]
!                  frhogq , frhogq_pl          )  !--- [INOUT]
!
!             endif
!
!       call OPRT_horizontalize_vec( frhogvx, frhogvx_pl, & !--- [INOUT]
!                                    frhogvy, frhogvy_pl, & !--- [INOUT]
!                                    frhogvz, frhogvz_pl  ) !--- [INOUT]
!
!       rhog   = rhog   + TIME_DTL * frhog
!       rhogvx = rhogvx + TIME_DTL * frhogvx
!       rhogvy = rhogvy + TIME_DTL * frhogvy
!       rhogvz = rhogvz + TIME_DTL * frhogvz
!       rhogw  = rhogw  + TIME_DTL * frhogw
!       rhoge  = rhoge  + TIME_DTL * frhoge
!       rhogq  = rhogq  + TIME_DTL * frhogq
!
!       if ( ADM_prc_me == ADM_prc_pl ) then
!          rhog_pl   = rhog_pl   + TIME_DTL * frhog_pl
!          rhogvx_pl = rhogvx_pl + TIME_DTL * frhogvx_pl
!          rhogvy_pl = rhogvy_pl + TIME_DTL * frhogvy_pl
!          rhogvz_pl = rhogvz_pl + TIME_DTL * frhogvz_pl
!          rhogw_pl  = rhogw_pl  + TIME_DTL * frhogw_pl
!          rhoge_pl  = rhoge_pl  + TIME_DTL * frhoge_pl
!          rhogq_pl  = rhogq_pl  + TIME_DTL * frhogq_pl
!       endif
!
!       call prgvar_set( rhog,   rhog_pl,   & !--- [IN]
!                        rhogvx, rhogvx_pl, & !--- [IN]
!                        rhogvy, rhogvy_pl, & !--- [IN]
!                        rhogvz, rhogvz_pl, & !--- [IN]
!                        rhogw,  rhogw_pl,  & !--- [IN]
!                        rhoge,  rhoge_pl,  & !--- [IN]
!                        rhogq,  rhogq_pl,  & !--- [IN]
!                        0                  )
!
!    endif

    return
  end subroutine dynstep2

end module mod_dynstep