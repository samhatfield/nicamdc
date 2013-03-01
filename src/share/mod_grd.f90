!-------------------------------------------------------------------------------
!>
!! Grid system module
!!
!! @par Description
!!         This module is for the management of the icosahedral grid system
!!
!! @author  H.Tomita
!!
!! @par History
!! @li      2004-02-17 (H.Tomita)  Imported from igdc-4.33
!! @li      2009-01-23 (H.Tomita)  extend the vertical grid method, introducing "hflat".
!! @li      2009-03-10 (H.Tomita)  1. add sub[GRD_gen_plgrid]
!!                                    ( This subroutine generates
!!                                      the pole grids from the regular region grids. )
!!                                 2. support direct access of grid file without pole data.
!!                                    sub[GRD_input_hgrid,GRD_output_hgrid].
!!                                 3. add 'da_access_hgrid' in the namelist.
!! @li      2009-03-10 (H.Tomita)  add error handling in GRD_input_hgrid.
!! @li      2009-05-27 (M.Hara)    1. bug fix of error handling in GRD_input_hgrid.
!!                                 2. remove "optional" declaration from
!!                                    da_access in GRD_input_hgrid and GRD_output_hgrid.
!! @li      2011-07-22 (T.Ohno)    add parameters
!!                                 1.GRD_grid_type 'ON_SPHERE' / 'ON_PLANE'
!!                                 2.hgrid_comm_flg
!!                                   the grid data should be communicated or not. ( default:.true. )
!!                                 3.triangle_size
!!                                   scale factor when GRD_grid_type is 'ON_PLANE'
!! @li      2011-09-03 (H.Yashiro) New I/O
!! @li      2012-05-25 (H.Yashiro) Avoid irregal ISEND/IRECV comm.
!! @li      2012-10-20 (R.Yoshida) Topography for Jablonowski test
!!
!<
module mod_grd
  !-----------------------------------------------------------------------------
  !
  !++ Used modules
  !
  use mpi
  use mod_adm, only: &
     ADM_NSYS,    & ! [add] T.Ohno 110722
     ADM_MAXFNAME
  !-----------------------------------------------------------------------------
  implicit none
  private
  !-----------------------------------------------------------------------------
  !
  !++ Public procedure
  !
  public :: GRD_setup
  public :: GRD_output_hgrid
  public :: GRD_input_hgrid
  public :: GRD_scaling
  public :: GRD_output_vgrid
  public :: GRD_input_vgrid
  public :: GRD_gen_plgrid

  !-----------------------------------------------------------------------------
  !
  !++ Public parameters & variables
  !

  !====== Horizontal direction ======
  !
  !------ Scaling factor for length, e.g., earth's radius.
  real(8), public,  save :: GRD_rscale
  !
  !------ Indentifiers for the directions in the Cartesian coordinate.
  integer, public, parameter :: GRD_XDIR=1
  integer, public, parameter :: GRD_YDIR=2
  integer, public, parameter :: GRD_ZDIR=3
  !
  !------ Grid points ( CELL CENTER )
  real(8), public, allocatable, save :: GRD_x   (:,:,:,:)
  real(8), public, allocatable, save :: GRD_x_pl(:,:,:,:)
  !<-----
  !<-----         GRD_x(1:ADM_gall,          &  --- horizontal
  !<-----               1:ADM_KNONE,         &  --- vertical
  !<-----               1:ADM_lall,          &  --- local region
  !<-----               GRD_XDIR:GRD_ZDIR)      --- three components
  !<-----
  !<-----         GRD_x_pl(1:ADM_gall_pl,    &  --- horizontal
  !<-----                  1:ADM_KNONE,      &  --- vertical
  !<-----                  1:ADM_lall_pl,    &  --- pole regions
  !<-----                  GRD_XDIR:GRD_ZDIR)   --- three components
  !<-----           ___
  !<-----         /     \
  !<-----        <   p   >
  !<-----         \ ___ /
  !<-----

  !------ Grid points ( CELL CORNER )
  real(8), public, allocatable, save :: GRD_xt   (:,:,:,:,:)
  real(8), public, allocatable, save :: GRD_xt_pl(:,:,:,:)
  !<-----
  !<-----         GRD_xt(1:ADM_gall,         &  --- horizontal
  !<-----                1:ADM_KNONE,        &  --- vertical
  !<-----                1:ADM_lall,         &  --- local region
  !<-----                ADM_TI:ADM_TJ,      &  --- upper or lower triangle.
  !<-----                GRD_XDIR:GRD_ZDIR)     --- three components
  !<-----
  !<-----         GRD_xt_pl(1:ADM_gall_pl,   &  --- horizontal
  !<-----                  1:ADM_KNONE,      &  --- vertical
  !<-----                  1:ADM_lall_pl,    &  --- pole regions
  !<-----                  GRD_XDIR:GRD_ZDIR)   --- three components
  !<-----          p___p
  !<-----         /     \
  !<-----        p       p
  !<-----         \ ___ /
  !<-----          p   p

  real(8), public, allocatable, save :: GRD_e   (:,:,:) ! unscaled GRD_x (=unit vector)
  real(8), public, allocatable, save :: GRD_e_pl(:,:,:)

  !====== Vertical direction ======
  !
  !------ Top height
  real(8), public, save              :: GRD_htop
  !<----- unit : [m]
  !
  !------ xi coordinate
  real(8), public, allocatable, save :: GRD_gz(:)
  !
  !------ xi coordinate at the half point
  real(8), public, allocatable, save :: GRD_gzh(:)
  !
  !------ d(xi)
  real(8), public, allocatable, save :: GRD_dgz(:)
  !
  !------ d(xi) at the half point
  real(8), public, allocatable, save :: GRD_dgzh(:)
  !
  !------ 1/dgz, 1/dgzh   ( add by kgoto )
  real(8), public, allocatable, save ::  GRD_rdgz (:)
  real(8), public, allocatable, save ::  GRD_rdgzh(:)

  !------ Topography & vegitation
  integer, public,         parameter :: GRD_ZSFC    = 1
  integer, public,         parameter :: GRD_ZSD     = 2
  integer, public,         parameter :: GRD_VEGINDX = 3
  real(8), public, allocatable, save :: GRD_zs   (:,:,:,:)
  real(8), public, allocatable, save :: GRD_zs_pl(:,:,:,:)
  !<-----
  !<-----         GRD_zs(1:ADM_gall,       &
  !<-----                ADM_KNONE,        & <- one layer data
  !<-----                1:ADM_lall,       &
  !<-----                GRD_ZSFC:GRD_VEGINDX))
  !<-----
  !<-----         GRD_zs_pl(1:ADM_gall_pl, &
  !<-----                   ADM_KNONE,     & <- one layer data
  !<-----                   1:ADM_lall_pl, &
  !<-----                   GRD_ZSFC:GRD_VEGINDX))
  !<-----
  !
  !------ z coordinate ( actual height )
  integer, public,         parameter :: GRD_Z  = 1
  integer, public,         parameter :: GRD_ZH = 2
  real(8), public, allocatable, save :: GRD_vz   (:,:,:,:)
  real(8), public, allocatable, save :: GRD_vz_pl(:,:,:,:)
  !<-----
  !<-----         GRD_vz(1:ADM_gall,     &
  !<-----                1:ADM_kall,     &
  !<-----                1:ADM_lall,     &
  !<-----                GRD_Z:GRD_ZH))
  !<-----         GRD_vz_pl(1:ADM_gall_pl, &
  !<-----                   1:ADM_kall,    &
  !<-----                   1:ADM_lall_pl, &
  !<-----                   GRD_Z:GRD_ZH))
  !<-----
  !
  !------ Vertical interpolation factors
  real(8), public, allocatable, save :: GRD_afac(:)
  real(8), public, allocatable, save :: GRD_bfac(:)
  real(8), public, allocatable, save :: GRD_cfac(:)
  real(8), public, allocatable, save :: GRD_dfac(:)
  !
  ! [add] T.Ohno 110722
  character(ADM_NSYS),  public, save :: GRD_grid_type = 'ON_SPHERE'
  !                                                     'ON_PLANE'

  !-----------------------------------------------------------------------------
  !
  !++ Private procedure
  !
  !-----------------------------------------------------------------------------
  !
  !++ Private parameters & variables
  !
  character(len=ADM_MAXFNAME), private, save :: hgrid_fname     = ''       ! Horizontal grid file

  character(len=ADM_MAXFNAME), private, save :: topo_fname      = ''       ! Topographical data file
  character(len=ADM_MAXFNAME), private, save :: toposd_fname    = ''       ! Standard deviation of topog. data file
  character(len=ADM_MAXFNAME), private, save :: vegeindex_fname = ''       ! Vegetation index data file

  character(len=ADM_MAXFNAME), private, save :: vgrid_fname     = ''       ! Vertical grid file
  character(len=ADM_MAXFNAME), private, save :: vgrid_scheme    = 'LINEAR' ! Vertical coordinate scheme
  real(8),                     private, save :: h_efold         = 10000.D0 ! [m]
  real(8),                     private, save :: hflat           =  -999.D0 ! [m]

  logical,                     private, save :: hgrid_comm_flg  = .true.   ! [add] T.Ohno 110722
  real(8),                     private, save :: triangle_size   = 0.D0     ! [add] T.Ohno 110722 length of sides of triangle

  logical,                     private, save :: da_access_hgrid    = .false.
  logical,                     private, save :: topo_direct_access = .false.  ! [add] H.Yashiro 20110819
  character(len=ADM_MAXFNAME), private, save :: hgrid_io_mode      = 'LEGACY' ! [add] H.Yashiro 20110819
  character(len=ADM_MAXFNAME), private, save :: topo_io_mode       = 'LEGACY' ! [add] H.Yashiro 20110819

  logical,                     private, save :: output_vgrid       = .false.

  !-----------------------------------------------------------------------------
contains

  !-----------------------------------------------------------------------------
  !>
  !> Setup routine for grid module.
  !>    1. set the horizontal grid
  !>    2. set the vertical grid
  !>    3. set the topograph
  !>
  subroutine GRD_setup
    use mod_adm, only :  &
         ADM_LOG_FID,    &
         ADM_CTL_FID,    &
         ADM_PRC_PL,     &
         ADM_lall_pl,    &
         ADM_gall_pl,    &
         ADM_TI,         &
         ADM_TJ,         &
         ADM_GSLF_PL,    &
         ADM_KNONE,      &
         ADM_VNONE,      &
         ADM_VMISS,      &
         ADM_prc_me,     &
         ADM_lall,       &
         ADM_kall,       &
         ADM_gmin,       &
         ADM_gmax,       &
         ADM_gall,       &
         ADM_gall_1d,    &
         ADM_kmin,       &
         ADM_kmax,       &
         ADM_prc_run_master,&
         ADM_proc_stop
    use mod_cnst, only : &
         CNST_ERADIUS
    use mod_comm, only :  &
         COMM_data_transfer, &
         COMM_var ! [add] H.Yashiro 20110819
    implicit none

    namelist / GRDPARAM / &
        vgrid_fname,     & !--- vertical grid file-name
        hgrid_fname,     & !--- horizontal grid basename
        topo_fname,      & !--- topography basename
        toposd_fname,    & !--- standard deviation of topography basename
        vegeindex_fname, & !--- vegetation index basename
        vgrid_scheme,    & !--- verical grid scheme
        h_efold,         & !--- efolding height for hybrid vertical grid.
        hflat,           &
        output_vgrid,    & !--- output verical grid file?
        hgrid_comm_flg,  & !--- communicate GRD_x           ! [add] T.Ohno 110722
        triangle_size,   & !--- length of sides of triangle ! [add] T.Ohno 110722
        GRD_grid_type,   & !--- grid type                   ! [add] T.Ohno 110722
        da_access_hgrid, &
        hgrid_io_mode,   & !--- io type(hgrid) [add] H.Yashiro 20110819
        topo_io_mode       !--- io type(topo)  [add] H.Yashiro 20110819

    integer :: n,k,l
    integer :: ierr

    integer :: kflat, K0
    real(8) :: htop

    real(8) :: fac_scale ! [add] T.Ohno 110722

    integer :: nstart,nend
    integer :: i,j,suf
    suf(i,j) = ADM_gall_1d * ((j)-1) + (i)
    !---------------------------------------------------------------------------

    !--- read parameters
    write(ADM_LOG_FID,*)
    write(ADM_LOG_FID,*) '+++ Module[grd]/Category[common share]'
    rewind(ADM_CTL_FID)
    read(ADM_CTL_FID,nml=GRDPARAM,iostat=ierr)
    if ( ierr < 0 ) then
       write(ADM_LOG_FID,*) '*** GRDPARAM is not specified. use default.'
    elseif( ierr > 0 ) then
       write(*,          *) 'xxx Not appropriate names in namelist GRDPARAM. STOP.'
       write(ADM_LOG_FID,*) 'xxx Not appropriate names in namelist GRDPARAM. STOP.'
       call ADM_proc_stop
    endif
    write(ADM_LOG_FID,GRDPARAM)

    K0 = ADM_KNONE

    !
    !--- < setting the horizontal grid > ---
    !
    !------ allocation and intitialization of horizontal grid points
    !------ ( cell CENTER )
    allocate( GRD_x   (ADM_gall,   K0,ADM_lall,   GRD_XDIR:GRD_ZDIR) )
    allocate( GRD_x_pl(ADM_gall_pl,K0,ADM_lall_pl,GRD_XDIR:GRD_ZDIR) )
    GRD_x   (:,:,:,:) = ADM_VMISS
    GRD_x_pl(:,:,:,:) = ADM_VMISS
    !
    !------ allocation and intitialization of horizontal grid points
    !------  ( cell CORNER )
    allocate( GRD_xt   (ADM_gall,   K0,ADM_lall,   ADM_TI:ADM_TJ,GRD_XDIR:GRD_ZDIR) )
    allocate( GRD_xt_pl(ADM_gall_pl,K0,ADM_lall_pl,              GRD_XDIR:GRD_ZDIR) )
    GRD_xt   (:,:,:,:,:) = ADM_VMISS
    GRD_xt_pl(:,:,:,:)   = ADM_VMISS
    !
    !--- reading the horzontal grid (unit sphere) and
    !--- scaled by earth radius
    call GRD_input_hgrid(hgrid_fname,Bgrid_dump=.true.,da_access=da_access_hgrid)

    !--- data transfer for GRD_x
    !--- note : do not communicate GRD_xt
    if( hgrid_comm_flg ) call COMM_data_transfer(GRD_x,GRD_x_pl) ! [mod] T.Ohno 110722

    ! save unscaled grid points as the unit vector
    allocate( GRD_e   (ADM_gall,   ADM_lall,   GRD_XDIR:GRD_ZDIR) )
    allocate( GRD_e_pl(ADM_gall_pl,ADM_lall_pl,GRD_XDIR:GRD_ZDIR) )
    GRD_e   (:,:,:) = GRD_x   (:,K0,:,:)
    GRD_e_pl(:,:,:) = GRD_x_pl(:,K0,:,:)

    ! [mod] T.Ohno 110722 ==>
    if ( trim(GRD_grid_type) == 'ON_PLANE' ) then
       fac_scale = triangle_size
    else
       fac_scale = CNST_ERADIUS
    endif

    call GRD_scaling(fac_scale)
    ! [mod] T.Ohno 110722 <==


    !------ allocation, initialization, and
    !------ reading of surface height, standard deviation, vegetation index
    allocate(GRD_zs   (ADM_gall,   K0,ADM_lall,   GRD_ZSFC:GRD_VEGINDX))
    allocate(GRD_zs_pl(ADM_gall_pl,K0,ADM_lall_pl,GRD_ZSFC:GRD_VEGINDX))
    GRD_zs   (:,:,:,:) = 0.D0
    GRD_zs_pl(:,:,:,:) = 0.D0

    ! -> [add] R.Yoshida 20121020
    if ( trim(topo_fname) == 'Jablonowski' ) then
       call GRD_jbw_init_topo
    else
       call GRD_input_topograph(topo_fname,GRD_ZSFC)
    endif
    ! <- [add] R.Yoshida 20121020

    call GRD_input_topograph(toposd_fname,   GRD_ZSD)
    call GRD_input_topograph(vegeindex_fname,GRD_VEGINDX)

    !--- data transfer for GRD_zs
    if (topo_direct_access) then ! [add] H.Yashiro 20110819
       call COMM_var( GRD_zs, GRD_zs_pl, K0, 3, comm_type=2, NSval_fix=.true. )
    else
       call COMM_data_transfer(GRD_zs,GRD_zs_pl)
    endif

    !
    !--- < setting the vertical coordinate > ---
    !
    if( ADM_kall /= ADM_KNONE ) then

       !------ allocation of vertical grid.
       allocate( GRD_gz   (ADM_kall) )
       allocate( GRD_gzh  (ADM_kall) )
       allocate( GRD_dgz  (ADM_kall) )
       allocate( GRD_dgzh (ADM_kall) )
       allocate( GRD_rdgz (ADM_kall) )
       allocate( GRD_rdgzh(ADM_kall) )

       !------ input the vertical grid.
       call GRD_input_vgrid(vgrid_fname)

       !------ calculation of grid intervals ( cell center )
       do k = ADM_kmin-1, ADM_kmax
          GRD_dgz(k) = GRD_gzh(k+1) - GRD_gzh(k)
       enddo
       GRD_dgz(ADM_kmax+1) = GRD_dgz(ADM_kmax)

       !------ calculation of grid intervals ( cell wall )
       do k = ADM_kmin, ADM_kmax+1
          GRD_dgzh(k) = GRD_gz(k) - GRD_gz(k-1)
       enddo
       GRD_dgzh(ADM_kmin-1) = GRD_dgzh(ADM_kmin)

       !------ calculation of 1/dgz and 1/dgzh
       do k = 1, ADM_kall
          GRD_rdgz (k) = 1.D0 / grd_dgz (k)
          GRD_rdgzh(k) = 1.D0 / grd_dgzh(k)
       enddo

       !------ hight top
       GRD_htop = GRD_gzh(ADM_kmax+1) - GRD_gzh(ADM_kmin)

       !--- < vertical interpolation factor > ---
       allocate( GRD_afac(ADM_kall) )
       allocate( GRD_bfac(ADM_kall) )
       allocate( GRD_cfac(ADM_kall) )
       allocate( GRD_dfac(ADM_kall) )

       !------ From the cell center value to the cell wall value
       !------     A(k-1/2) = ( afac(k) A(k) + bfac(k) * A(k-1) ) / 2
       do k = ADM_kmin, ADM_kmax+1
          GRD_afac(k) = 2.D0 * ( GRD_gzh(k) - GRD_gz(k-1) ) &
                             / ( GRD_gz (k) - GRD_gz(k-1) )
       enddo
       GRD_afac(ADM_kmin-1) = 2.D0

       GRD_bfac(:) = 2.D0 - GRD_afac(:)

       !------ From the cell wall value to the cell center value
       !------     A(k) = ( cfac(k) A(k+1/2) + dfac(k) * A(k-1/2) ) / 2
       do k = ADM_kmin, ADM_kmax
          GRD_cfac(k) = 2.D0 * ( GRD_gz (k  ) - GRD_gzh(k) ) &
                             / ( GRD_gzh(k+1) - GRD_gzh(k) )
       enddo
       GRD_cfac(ADM_kmin-1) = 2.D0
       GRD_cfac(ADM_kmax+1) = 0.D0

       GRD_dfac(:) = 2.D0 - GRD_cfac(:)

       !------ allocation, initilization, and setting the z-coordinate
       allocate( GRD_vz   ( ADM_gall,   ADM_kall,ADM_lall,   GRD_Z:GRD_ZH) )
       allocate( GRD_vz_pl( ADM_gall_pl,ADM_kall,ADM_lall_pl,GRD_Z:GRD_ZH) )
       GRD_vz   (:,:,:,:) = ADM_VMISS
       GRD_vz_pl(:,:,:,:) = ADM_VMISS

       select case(trim(vgrid_scheme))
       case('LINEAR')
          !--- linear transfromation : (Gal-Chen & Sommerville(1975)
          !---     gz = H(z-zs)/(H-zs) -> z = (H-zs)/H * gz + zs
          kflat = -1
          if ( hflat > 0.D0 ) then !--- default : -999.0
             do k = ADM_kmin+1, ADM_kmax+1
                if ( hflat < GRD_gzh(k) ) then
                   kflat = k
                   exit
                endif
             enddo
          endif

          if ( kflat == -1 ) then
             kflat = ADM_kmax + 1
             htop  = GRD_htop
          else
             htop = GRD_gzh(kflat) - GRD_gzh(ADM_kmin)
          endif

          K0 = ADM_KNONE
          nstart = suf(ADM_gmin,ADM_gmin)
          nend   = suf(ADM_gmax,ADM_gmax)

          do l = 1, ADM_lall
             do k = ADM_kmin-1, kflat
                do n = nstart,nend
                   GRD_vz(n,k,l,GRD_Z ) = GRD_zs(n,K0,l,GRD_ZSFC) &
                                        + ( htop - GRD_zs(n,K0,l,GRD_ZSFC) ) / htop * GRD_gz(k)
                   GRD_vz(n,k,l,GRD_ZH) = GRD_zs(n,K0,l,GRD_ZSFC) &
                                        + ( htop - GRD_zs(n,K0,l,GRD_ZSFC) ) / htop * GRD_gzh(k)
                enddo
             enddo

             if ( kflat < ADM_kmax+1 ) then
                do k = kflat+1, ADM_kmax+1
                   do n = nstart, nend
                      GRD_vz(n,k,l,GRD_Z ) = GRD_gz (k)
                      GRD_vz(n,k,l,GRD_ZH) = GRD_gzh(k)
                   enddo
                enddo
             endif
          enddo

          if ( ADM_prc_me == ADM_prc_pl ) then
             n = ADM_GSLF_PL

             do l = 1, ADM_lall_pl
                do k = ADM_kmin-1, kflat
                   GRD_vz_pl(n,k,l,GRD_Z)  = GRD_zs_pl(n,K0,l,GRD_ZSFC) &
                                           + ( htop - GRD_zs_pl(n,K0,l,GRD_ZSFC) ) / htop * GRD_gz(k)
                   GRD_vz_pl(n,k,l,GRD_ZH) = GRD_zs_pl(n,K0,l,GRD_ZSFC) &
                                           + ( htop - GRD_zs_pl(n,K0,l,GRD_ZSFC) ) / htop * GRD_gzh(k)
                enddo

                if ( kflat < ADM_kmax+1 ) then
                   do k = kflat+1, ADM_kmax+1
                      GRD_vz_pl(n,k,l,GRD_Z ) = GRD_gz (k)
                      GRD_vz_pl(n,k,l,GRD_ZH) = GRD_gzh(k)
                   enddo
                endif
             enddo
          endif

       case('HYBRID')
          !--------- Hybrid transformation : like as Simmons & Buridge(1981)
          K0 = ADM_KNONE
          nstart = suf(ADM_gmin,ADM_gmin)
          nend   = suf(ADM_gmax,ADM_gmax)

          do l = 1, ADM_lall
             do k = ADM_kmin-1, ADM_kmax+1
                do n = nstart,nend
                   GRD_vz(n,k,l,GRD_Z)  = GRD_gz(k)                              &
                                        + GRD_zs(n,K0,l,ADM_VNONE)               &
                                        * sinh( (GRD_htop-GRD_gz(k)) / h_efold ) &
                                        / sinh(  GRD_htop            / h_efold )
                   GRD_vz(n,k,l,GRD_ZH) = GRD_gzh(k)                              &
                                        + GRD_zs(n,K0,l,ADM_VNONE)                &
                                        * sinh( (GRD_htop-GRD_gzh(k)) / h_efold ) &
                                        / sinh(  GRD_htop             / h_efold )
                enddo
             enddo
          enddo

          if ( ADM_prc_me == ADM_prc_pl ) then
             n = ADM_GSLF_PL

             do l = 1, ADM_lall_pl
                do k = ADM_kmin-1, ADM_kmax+1
                   GRD_vz_pl(n,k,l,GRD_Z)  = GRD_gz(k)                              &
                                           + GRD_zs_pl(n,K0,l,ADM_VNONE)            &
                                           * sinh( (GRD_htop-GRD_gz(k)) / h_efold ) &
                                           / sinh(  GRD_htop            / h_efold )
                   GRD_vz_pl(n,k,l,GRD_ZH) = GRD_gzh(k)                              &
                                           + GRD_zs_pl(n,K0,l,ADM_VNONE)             &
                                           * sinh( (GRD_htop-GRD_gzh(k)) / h_efold ) &
                                           / sinh(  GRD_htop             / h_efold )
                enddo
             enddo
          endif

       endselect

       call COMM_data_transfer(GRD_vz,GRD_vz_pl)

       GRD_vz(suf(1,ADM_gall_1d),:,:,:) = GRD_vz(suf(ADM_gmin,ADM_gmin),:,:,:)
       GRD_vz(suf(ADM_gall_1d,1),:,:,:) = GRD_vz(suf(ADM_gmin,ADM_gmin),:,:,:)
    endif

    !--- output information about grid.
    if ( ADM_kall /= ADM_KNONE ) then
       write(ADM_LOG_FID,*)
       write(ADM_LOG_FID,'(5x,A)')             '|======      Vertical Coordinate [m]      ======|'
       write(ADM_LOG_FID,'(5x,A)')             '|                                               |'
       write(ADM_LOG_FID,'(5x,A)')             '|          -GRID CENTER-       -GRID INTERFACE- |'
       write(ADM_LOG_FID,'(5x,A)')             '|  k        gz     d(gz)      gzh    d(gzh)   k |'
       write(ADM_LOG_FID,'(5x,A)')             '|                                               |'
       k = ADM_kmax + 1
       write(ADM_LOG_FID,'(5x,A,I3,2F10.1,A)') '|',k,GRD_gz(k),GRD_dgz(k), '                        | dummy'
       write(ADM_LOG_FID,'(5x,A,2F10.1,I4,A)') '|                      ',GRD_gzh(k),GRD_dgzh(k),k,' | TOA'
       k = ADM_kmax
       write(ADM_LOG_FID,'(5x,A,I3,2F10.1,A)') '|',k,GRD_gz(k),GRD_dgz(k), '                        | kmax'
       write(ADM_LOG_FID,'(5x,A,2F10.1,I4,A)') '|                      ',GRD_gzh(k),GRD_dgzh(k),k,' |'
       do k = ADM_kmax-1, ADM_kmin+1, -1
       write(ADM_LOG_FID,'(5x,A,I3,2F10.1,A)') '|',k,GRD_gz(k),GRD_dgz(k), '                        |'
       write(ADM_LOG_FID,'(5x,A,2F10.1,I4,A)') '|                      ',GRD_gzh(k),GRD_dgzh(k),k,' |'
       enddo
       k = ADM_kmin
       write(ADM_LOG_FID,'(5x,A,I3,2F10.1,A)') '|',k,GRD_gz(k),GRD_dgz(k), '                        | kmin'
       write(ADM_LOG_FID,'(5x,A,2F10.1,I4,A)') '|                      ',GRD_gzh(k),GRD_dgzh(k),k,' | ground'
       k = ADM_kmin-1
       write(ADM_LOG_FID,'(5x,A,I3,2F10.1,A)') '|',k,GRD_gz(k),GRD_dgz(k), '                        | dummy'
       write(ADM_LOG_FID,'(5x,A)')             '|===============================================|'

       write(ADM_LOG_FID,*)
       write(ADM_LOG_FID,*) '--- Vertical layer scheme = ', trim(vgrid_scheme)
       if ( vgrid_scheme == 'HYBRID' ) then
          write(ADM_LOG_FID,*) '--- e-folding height = ', h_efold
       endif

       if ( output_vgrid ) then
          if ( ADM_prc_me == ADM_prc_run_master ) then
             call GRD_output_vgrid('./vgrid_used.dat')
          endif
       endif
    else
       write(ADM_LOG_FID,*)
       write(ADM_LOG_FID,*) '--- vartical layer = 1'
    endif

    return
  end subroutine GRD_setup

  !-----------------------------------------------------------------------------
  !>
  !> Description of the subroutine GRD_scaling
  !>
  subroutine GRD_scaling( fact )
    implicit none

    real(8), intent(in) :: fact !--- IN : scaling factor
    !---------------------------------------------------------------------------

    ! [mod] T.Ohno 110722 ==>
    if ( trim(GRD_grid_type) == 'ON_PLANE' ) then
       GRD_x    (:,:,:,:)   = GRD_x    (:,:,:,:)   * fact
       GRD_x_pl (:,:,:,:)   = GRD_x_pl (:,:,:,:)   * fact
       GRD_xt   (:,:,:,:,:) = GRD_xt   (:,:,:,:,:) * fact
       GRD_xt_pl(:,:,:,:)   = GRD_xt_pl(:,:,:,:)   * fact
    else
       !--- setting the sphere radius
       GRD_rscale = fact

       !--- scaling by using GRD_rscale
       GRD_x    (:,:,:,:)   = GRD_x    (:,:,:,:)   * GRD_rscale
       GRD_x_pl (:,:,:,:)   = GRD_x_pl (:,:,:,:)   * GRD_rscale
       GRD_xt   (:,:,:,:,:) = GRD_xt   (:,:,:,:,:) * GRD_rscale
       GRD_xt_pl(:,:,:,:)   = GRD_xt_pl(:,:,:,:)   * GRD_rscale
    endif
    ! [mod] T.Ohno 110722 <==

    return
  end subroutine GRD_scaling

  !-----------------------------------------------------------------------------
  !>
  !> Description of the subroutine GRD_output_hgrid
  !>
  subroutine GRD_output_hgrid( &
       basename,   &
       bgrid_dump, &
       txt_mode,   &
       da_access   )
    use mod_misc, only: &
       MISC_make_idstr,&
       MISC_get_available_fid
    use mod_adm, only: &
       ADM_LOG_FID,   &
       ADM_proc_stop, &
       ADM_prc_tab,   &
       ADM_prc_me,    &
       ADM_PRC_PL,    &
       ADM_TI,        &
       ADM_TJ,        &
       ADM_gall,      &
       ADM_gall_pl,   &
       ADM_lall,      &
       ADM_lall_pl,   &
       ADM_KNONE,     & 
       ADM_gall_1d
    use mod_fio, only: & ! [add] H.Yashiro 20110819
       FIO_output, &
       FIO_HMID,   &
       FIO_REAL8
    implicit none

    character(len=ADM_MAXFNAME), intent(in) :: basename   ! output basename
    logical,                     intent(in) :: bgrid_dump ! flag of B-grid dump
    logical,                     intent(in) :: txt_mode   ! flag of ascii mode
    logical,                     intent(in) :: da_access  ! true or false for direct access

    character(len=ADM_MAXFNAME) :: fname

    ! -> [add] H.Yashiro 20110819
    character(len=FIO_HMID)   :: desc = 'HORIZONTAL GRID FILE'
    ! <- [add] H.Yashiro 20110819

    integer :: rgnid
    integer :: fid
    integer :: i, j, l, n, K0
    !---------------------------------------------------------------------------

    K0 = ADM_KNONE

    ! -> [add] H.Yashiro 20110819
    if ( hgrid_io_mode == 'ADVANCED' ) then

       call FIO_output( GRD_x(:,:,:,GRD_XDIR),                           &
                        basename, desc, "",                              &
                       "grd_x_x", "GRD_x (X_DIR)", "",                   &
                       "NIL", FIO_REAL8, "ZSSFC1", K0, K0, 1, 0.D0, 0.D0 )
       call FIO_output( GRD_x(:,:,:,GRD_YDIR),                           &
                        basename, desc, '',                              &
                       'grd_x_y', 'GRD_x (Y_DIR)', '',                   &
                       'NIL', FIO_REAL8, 'ZSSFC1', K0, K0, 1, 0.D0, 0.D0 )
       call FIO_output( GRD_x(:,:,:,GRD_ZDIR),                           &
                        basename, desc, '',                              &
                       'grd_x_z', 'GRD_x (Z_DIR)', '',                   &
                       'NIL', FIO_REAL8, 'ZSSFC1', K0, K0, 1, 0.D0, 0.D0 )

       if ( bgrid_dump ) then
          call FIO_output( GRD_xt(:,:,:,ADM_TI,GRD_XDIR),                   &
                           basename, desc, '',                              &
                          'grd_xt_ix', 'GRD_xt (TI,X_DIR)', '',             &
                          'NIL', FIO_REAL8, 'ZSSFC1', K0, K0, 1, 0.D0, 0.D0 )
          call FIO_output( GRD_xt(:,:,:,ADM_TJ,GRD_XDIR),                   &
                           basename, desc, '',                              &
                          'grd_xt_jx', 'GRD_xt (TJ,X_DIR)', '',             &
                          'NIL', FIO_REAL8, 'ZSSFC1', K0, K0, 1, 0.D0, 0.D0 )
          call FIO_output( GRD_xt(:,:,:,ADM_TI,GRD_YDIR),                   &
                           basename, desc, '',                              &
                          'grd_xt_iy', 'GRD_xt (TI,Y_DIR)', '',             &
                          'NIL', FIO_REAL8, 'ZSSFC1', K0, K0, 1, 0.D0, 0.D0 )
          call FIO_output( GRD_xt(:,:,:,ADM_TJ,GRD_YDIR),                   &
                           basename, desc, '',                              &
                          'grd_xt_jy', 'GRD_xt (TJ,Y_DIR)', '',             &
                          'NIL', FIO_REAL8, 'ZSSFC1', K0, K0, 1, 0.D0, 0.D0 )
          call FIO_output( GRD_xt(:,:,:,ADM_TI,GRD_ZDIR),                   &
                           basename, desc, '',                              &
                          'grd_xt_iz', 'GRD_xt (TI,Z_DIR)', '',             &
                          'NIL', FIO_REAL8, 'ZSSFC1', K0, K0, 1, 0.D0, 0.D0 )
          call FIO_output( GRD_xt(:,:,:,ADM_TJ,GRD_ZDIR),                   &
                           basename, desc, '',                              &
                          'grd_xt_jz', 'GRD_xt (TJ,Z_DIR)', '',             &
                          'NIL', FIO_REAL8, 'ZSSFC1', K0, K0, 1, 0.D0, 0.D0 )
       endif

    elseif( hgrid_io_mode == 'LEGACY' ) then

       do l = 1, ADM_lall
          rgnid = ADM_prc_tab(l,ADM_prc_me)
          call MISC_make_idstr(fname,trim(basename),'rgn',rgnid)

          fid = MISC_get_available_fid()

          if ( txt_mode ) then
             open(fid,file=trim(fname),form='formatted')
                write(fid,'(2I12)') ADM_gall_1d
                do i = 1, ADM_gall_1d
                do j = 1, ADM_gall_1d
                   n = ADM_gall_1d*(j-1) + i
                   write(fid,'(2I8,3E24.15)') i, j, GRD_x(n,K0,l,GRD_XDIR), &
                                                    GRD_x(n,K0,l,GRD_YDIR), &
                                                    GRD_x(n,K0,l,GRD_ZDIR)
                enddo
                enddo
                if ( bgrid_dump ) then
                   do i = 1, ADM_gall_1d
                   do j = 1, ADM_gall_1d
                      n = ADM_gall_1d*(j-1) + i
                      write(fid,'(3I8,3E24.15)') i, j, ADM_TI, GRD_xt(n,K0,l,ADM_TI,GRD_XDIR), &
                                                               GRD_xt(n,K0,l,ADM_TI,GRD_YDIR), &
                                                               GRD_xt(n,K0,l,ADM_TI,GRD_ZDIR)
                   enddo
                   enddo
                   do i = 1, ADM_gall_1d
                   do j = 1, ADM_gall_1d
                      n = ADM_gall_1d*(j-1) + i
                      write(fid,'(3I8,3E24.15)') i, j, ADM_TJ, GRD_xt(n,K0,l,ADM_TJ,GRD_XDIR), &
                                                               GRD_xt(n,K0,l,ADM_TJ,GRD_YDIR), &
                                                               GRD_xt(n,K0,l,ADM_TJ,GRD_ZDIR)
                   enddo
                   enddo
                endif
             close(fid)
          else
             if ( da_access ) then
                open( unit = fid, &
                     file=trim(fname),   &
                     form='unformatted', &
                     access='direct',    &
                     recl=ADM_gall*8     )

                   write(fid,rec=1) GRD_x(:,K0,l,GRD_XDIR)
                   write(fid,rec=2) GRD_x(:,K0,l,GRD_YDIR)
                   write(fid,rec=3) GRD_x(:,K0,l,GRD_ZDIR)
                   if ( bgrid_dump ) then
                      write(fid,rec=4) GRD_xt(:,K0,l,ADM_TI,GRD_XDIR)
                      write(fid,rec=5) GRD_xt(:,K0,l,ADM_TI,GRD_YDIR)
                      write(fid,rec=6) GRD_xt(:,K0,l,ADM_TI,GRD_ZDIR)
                      write(fid,rec=7) GRD_xt(:,K0,l,ADM_TJ,GRD_XDIR)
                      write(fid,rec=8) GRD_xt(:,K0,l,ADM_TJ,GRD_YDIR)
                      write(fid,rec=9) GRD_xt(:,K0,l,ADM_TJ,GRD_ZDIR)
                   endif
                close(fid)
             else !--- legacy type
                open(fid,file=trim(fname),form='unformatted')
                   write(fid) ADM_gall_1d

                   write(fid) GRD_x(:,K0,l,GRD_XDIR)
                   write(fid) GRD_x(:,K0,l,GRD_YDIR)
                   write(fid) GRD_x(:,K0,l,GRD_ZDIR)
                   if ( bgrid_dump ) then
                      write(fid) GRD_xt(:,K0,l,ADM_TI:ADM_TJ,GRD_XDIR)
                      write(fid) GRD_xt(:,K0,l,ADM_TI:ADM_TJ,GRD_YDIR)
                      write(fid) GRD_xt(:,K0,l,ADM_TI:ADM_TJ,GRD_ZDIR)
                   endif
                close(fid)
             endif
          endif
       enddo

       if ( ADM_prc_me == ADM_PRC_PL ) then
          if ( txt_mode ) then
             fname=trim(basename)//'.pl'
             fid = MISC_get_available_fid()
             open(fid,file=fname,form='formatted')
                do l = 1, ADM_lall_pl
                do n = 1, ADM_gall_pl
                   write(fid,'(I8,3E24.15)') n, GRD_x_pl(n,K0,l,GRD_XDIR), &
                                                GRD_x_pl(n,K0,l,GRD_YDIR), &
                                                GRD_x_pl(n,K0,l,GRD_ZDIR)
                enddo
                enddo
                if ( bgrid_dump ) then
                   do l = 1, ADM_lall_pl
                   do n = 1, ADM_gall_pl
                      write(fid,'(I8,3E24.15)') n, GRD_xt_pl(n,K0,l,GRD_XDIR), &
                                                   GRD_xt_pl(n,K0,l,GRD_YDIR), &
                                                   GRD_xt_pl(n,K0,l,GRD_ZDIR)
                   enddo
                   enddo
                endif
             close(fid)
          else
             if( da_access ) then
                !--- nonthing to do
             else
                fname=trim(basename)//'.pl'
                fid = MISC_get_available_fid()
                open(fid,file=fname,form='unformatted')
                   write(fid) GRD_x_pl(:,:,:,:)
                   if( bgrid_dump ) then
                      write(fid) GRD_xt_pl(:,:,:,:)
                   endif
                close(fid)
             endif
          endif
       endif
    else
       write(ADM_LOG_FID,*) 'Invalid io_mode!'
       call ADM_proc_stop
    endif
    ! <- [add] H.Yashiro 20110819

    return
  end subroutine GRD_output_hgrid

  !-----------------------------------------------------------------------------
  !>
  !> Description of the subroutine GRD_input_hgrid
  !>
  subroutine GRD_input_hgrid( &
       basename,   &
       bgrid_dump, &
       da_access   )
    use mod_misc, only: &
       MISC_make_idstr,       &
       MISC_get_available_fid
    use mod_adm, only: &
       ADM_LOG_FID,   &
       ADM_proc_stop, &
       ADM_prc_tab,   &
       ADM_prc_me,    &
       ADM_PRC_PL,    &
       ADM_TI,        &
       ADM_TJ,        &
       ADM_gall,      &
       ADM_lall,      &
       ADM_KNONE,     &
       ADM_gall_1d
    use mod_fio, only : & ! [add] H.Yashiro 20110819
       FIO_input
    implicit none

    character(len=ADM_MAXFNAME), intent(in) :: basename   ! input basename
    logical,                     intent(in) :: bgrid_dump ! flag of B-grid input
    logical, optional,           intent(in) :: da_access  ! true or false for direct access

    logical :: read_success = .true.

    character(len=ADM_MAXFNAME) :: fname

    integer :: fid, ierr
    integer :: K0, l, rgnid
    !---------------------------------------------------------------------------

    K0 = ADM_KNONE

    ! -> [add] H.Yashiro 20110819
    if ( hgrid_io_mode == 'ADVANCED' ) then

       call FIO_input(GRD_x(:,:,:,GRD_XDIR),basename,'grd_x_x','ZSSFC1',K0,K0,1)
       call FIO_input(GRD_x(:,:,:,GRD_YDIR),basename,'grd_x_y','ZSSFC1',K0,K0,1)
       call FIO_input(GRD_x(:,:,:,GRD_ZDIR),basename,'grd_x_z','ZSSFC1',K0,K0,1)
       if (bgrid_dump) then
          call FIO_input(GRD_xt(:,:,:,ADM_TI,GRD_XDIR),basename, &
                         'grd_xt_ix','ZSSFC1',K0,K0,1            )
          call FIO_input(GRD_xt(:,:,:,ADM_TJ,GRD_XDIR),basename, &
                         'grd_xt_jx','ZSSFC1',K0,K0,1            )
          call FIO_input(GRD_xt(:,:,:,ADM_TI,GRD_YDIR),basename, &
                         'grd_xt_iy','ZSSFC1',K0,K0,1            )
          call FIO_input(GRD_xt(:,:,:,ADM_TJ,GRD_YDIR),basename, &
                         'grd_xt_jy','ZSSFC1',K0,K0,1            )
          call FIO_input(GRD_xt(:,:,:,ADM_TI,GRD_ZDIR),basename, &
                         'grd_xt_iz','ZSSFC1',K0,K0,1            )
          call FIO_input(GRD_xt(:,:,:,ADM_TJ,GRD_ZDIR),basename, &
                         'grd_xt_jz','ZSSFC1',K0,K0,1            )
       endif

       call GRD_gen_plgrid

    elseif( hgrid_io_mode == 'LEGACY' ) then

       do l = 1, ADM_lall
          rgnid = ADM_prc_tab(l,ADM_prc_me)

          call MISC_make_idstr(fname,trim(basename),'rgn',rgnid)

          fid = MISC_get_available_fid()
          if ( da_access ) then
             open( unit   = fid,           &
                   file   = trim(fname),   &
                   form   = 'unformatted', &
                   access = 'direct',      &
                   recl   = ADM_gall*8,    &
                   status = 'old',         &
                   iostat = ierr           )

                if ( ierr /= 0 ) then
                   write(ADM_LOG_FID,*) 'xxx No grid file.', trim(fname)
                   read_success = .false.
                   exit
                endif

                read(fid,rec=1) GRD_x(:,K0,l,GRD_XDIR)
                read(fid,rec=2) GRD_x(:,K0,l,GRD_YDIR)
                read(fid,rec=3) GRD_x(:,K0,l,GRD_ZDIR)
                if ( bgrid_dump ) then
                   read(fid,rec=4) GRD_xt(:,K0,l,ADM_TI,GRD_XDIR)
                   read(fid,rec=5) GRD_xt(:,K0,l,ADM_TI,GRD_YDIR)
                   read(fid,rec=6) GRD_xt(:,K0,l,ADM_TI,GRD_ZDIR)
                   read(fid,rec=7) GRD_xt(:,K0,l,ADM_TJ,GRD_XDIR)
                   read(fid,rec=8) GRD_xt(:,K0,l,ADM_TJ,GRD_YDIR)
                   read(fid,rec=9) GRD_xt(:,K0,l,ADM_TJ,GRD_ZDIR)
                endif
             close(fid)
          else
             open( unit   = fid,           &
                   file   = trim(fname),   &
                   form   = 'unformatted', &
                   status = 'old',         &
                   iostat = ierr           )

                if ( ierr /= 0 ) then
                   write(ADM_LOG_FID,*) 'xxx No grid file.', trim(fname)
                   read_success = .false.
                   exit
                endif

                read(fid) ADM_gall_1d
                read(fid) GRD_x(:,K0,l,GRD_XDIR)
                read(fid) GRD_x(:,K0,l,GRD_YDIR)
                read(fid) GRD_x(:,K0,l,GRD_ZDIR)
                if ( bgrid_dump ) then
                   read(fid) GRD_xt(:,K0,l,ADM_TI:ADM_TJ,GRD_XDIR)
                   read(fid) GRD_xt(:,K0,l,ADM_TI:ADM_TJ,GRD_YDIR)
                   read(fid) GRD_xt(:,K0,l,ADM_TI:ADM_TJ,GRD_ZDIR)
                endif
             close(fid)
          endif

       enddo

       if ( .NOT. read_success ) then
          write(ADM_LOG_FID,*) 'xxx Error occured in reading grid file.', trim(fname)
       endif

       if ( da_access ) then
          call GRD_gen_plgrid
       else
          if ( ADM_prc_me == ADM_PRC_PL ) then
             fname=trim(basename)//'.pl'

          fid = MISC_get_available_fid()
          open( unit   = fid,           &
                file   = trim(fname),   &
                form   = 'unformatted', &
                status = 'old',         &
                iostat = ierr           )

             if ( ierr /= 0 ) then
                write(ADM_LOG_FID,*) 'xxx No pole-grid file.', trim(fname)
                read_success = .false.
             endif

             read(fid) GRD_x_pl(:,:,:,:)

             if ( bgrid_dump ) then
                read(fid) GRD_xt_pl(:,:,:,:)
             endif

          close(fid)

       endif
    endif

    if ( .NOT. read_success ) then
       write(ADM_LOG_FID,*) 'xxx Error occured in reading pole-grid file.', trim(fname)
    endif

    else
       write(ADM_LOG_FID,*) 'Invalid io_mode!'
       call ADM_proc_stop
    endif
    ! <- [add] H.Yashiro 20110819

    return
  end subroutine GRD_input_hgrid

  !-----------------------------------------------------------------------------
  !>
  !> Description of the subroutine GRD_input_vgrid
  !>
  subroutine GRD_input_vgrid( fname )
    use mod_misc, only: &
       MISC_get_available_fid
    use mod_adm, only: &
       ADM_LOG_FID,  &
       ADM_vlayer,   &
       ADM_proc_stop
    implicit none

    character(len=ADM_MAXFNAME), intent(in) :: fname ! vertical grid file name

    integer :: num_of_layer
    integer :: fid, ierr
    !---------------------------------------------------------------------------

    fid = MISC_get_available_fid()
    open( unit   = fid,           &
          file   = trim(fname),   &
          status = 'old',         &
          form   = 'unformatted', &
          iostat = ierr           )

       if ( ierr /= 0 ) then
          write(ADM_LOG_FID,*) 'xxx No vertical grid file.'
          call ADM_proc_stop
       endif

       read(fid) num_of_layer

       if ( num_of_layer /= ADM_vlayer ) then
          write(ADM_LOG_FID,*) 'xxx inconsistency in number of vertical layers.'
          call ADM_proc_stop
       endif

       read(fid) GRD_gz
       read(fid) GRD_gzh

    close(fid)

    return
  end subroutine GRD_input_vgrid

  !-----------------------------------------------------------------------------
  !>
  !> Description of the subroutine GRD_output_vgrid
  !>
  subroutine GRD_output_vgrid( fname )
    use mod_misc, only: &
       MISC_get_available_fid
    use mod_adm, only: &
       ADM_vlayer
    implicit none

    character(len=*), intent(in) :: fname

    integer :: fid
    !---------------------------------------------------------------------------

    fid = MISC_get_available_fid()
    open(fid,file=trim(fname),form='unformatted')
       write(fid) ADM_vlayer
       write(fid) GRD_gz
       write(fid) GRD_gzh
    close(fid)

    return
  end subroutine GRD_output_vgrid

  !-----------------------------------------------------------------------------
  !>
  !> Description of the subroutine GRD_input_topograph
  !>
  subroutine GRD_input_topograph( &
       basename, &
       i_var     )
    use mod_misc,  only: &
       MISC_make_idstr,&
       MISC_get_available_fid
    use mod_adm, only: &
       ADM_LOG_FID, &
       ADM_prc_tab, &
       ADM_prc_me,  &
       ADM_PRC_PL,  &
       ADM_lall,    &
       ADM_gall,    &
       ADM_KNONE
    use mod_fio, only: &
       FIO_input
    implicit none

    character(len=*), intent(in) :: basename
    integer,          intent(in) :: i_var

    character(len=16) :: varname(3)
    data varname / 'topo', 'topo_stddev', 'vegeindex' /

    character(len=128) :: fname
    integer            :: ierr
    integer            :: l, rgnid, fid
    !---------------------------------------------------------------------------

    if ( topo_io_mode == 'ADVANCED' ) then
       topo_direct_access = .true.

       call FIO_input(GRD_zs(:,:,:,i_var),basename,varname(i_var),'ZSSFC1',1,1,1)

    elseif( topo_io_mode == 'LEGACY' ) then

       if ( topo_direct_access ) then !--- direct access ( defalut )
          do l = 1, ADM_lall
             rgnid = ADM_prc_tab(l,ADM_prc_me)
             call MISC_make_idstr(fname,trim(basename),'rgn',rgnid)
             fid = MISC_get_available_fid()

             open( fid,                    &
                   file   = trim(fname),   &
                   form   = 'unformatted', &
                   access = 'direct',      &
                   recl   = ADM_gall*8,    &
                   status = 'old'          )

                read(fid,rec=1) GRD_zs(:,ADM_KNONE,l,i_var)

             close(fid)
          enddo
       else !--- sequential access
          do l = 1, ADM_lall
             rgnid = ADM_prc_tab(l,ADM_prc_me)
             call MISC_make_idstr(fname,trim(basename),'rgn',rgnid)
             fid = MISC_get_available_fid()

             open(fid,file=trim(fname),status='old',form='unformatted',iostat=ierr)
                if ( ierr /= 0 ) then
                   write(ADM_LOG_FID,*) 'Msg : Sub[GRD_input_topograph]/Mod[grid]'
                   write(ADM_LOG_FID,*) '   *** No topographical file. Number :', i_var
                   return
                endif

                read(fid) GRD_zs(:,ADM_KNONE,l,i_var)
             close(fid)
          enddo

          if ( ADM_prc_me == ADM_prc_pl ) then
             fname = trim(basename)//'.pl'
             fid = MISC_get_available_fid()

             open(fid,file=trim(fname),status='old',form='unformatted')
                read(fid) GRD_zs_pl(:,:,:,i_var)
             close(fid)
          endif
       endif !--- direct/sequencial

    endif !--- io_mode

    return
  end subroutine GRD_input_topograph

  !-----------------------------------------------------------------------------
  !>
  !> Description of the subroutine GRD_gen_plgrid
  !>
  subroutine GRD_gen_plgrid
    use mod_adm, only: &
      ADM_rgn_nmax,       &
      ADM_rgn_vnum,       &
      ADM_rgn_vtab,       &
      ADM_rgn2prc,        &
      ADM_RID,            &
      ADM_VLINK_NMAX,     &
      ADM_COMM_RUN_WORLD, &
      ADM_prc_tab,        &
      ADM_prc_me,         &
      ADM_prc_npl,        &
      ADM_prc_spl,        &
      ADM_TI,             &
      ADM_TJ,             &
      ADM_N,              &
      ADM_S,              &
      ADM_NPL,            &
      ADM_SPL,            &
      ADM_lall,           &
      ADM_gall_1d,        &
      ADM_gmax,           &
      ADM_gmin,           &
      ADM_KNONE,          &
      ADM_GSLF_PL
    use mod_comm, only: &
      COMM_var
    implicit none

    integer :: prctab   (ADM_VLINK_NMAX)
    integer :: rgntab   (ADM_VLINK_NMAX)
    integer :: sreq     (ADM_VLINK_NMAX)
    integer :: rreq     (ADM_VLINK_NMAX)
    logical :: send_flag(ADM_VLINK_NMAX)

!    real(8) :: v_pl(GRD_XDIR:GRD_ZDIR,ADM_VLINK_NMAX)
    real(8) :: vsend_pl(GRD_XDIR:GRD_ZDIR,ADM_VLINK_NMAX) ! [mod] H.Yashiro 20120525
    real(8) :: vrecv_pl(GRD_XDIR:GRD_ZDIR,ADM_VLINK_NMAX) ! [mod] H.Yashiro 20120525

    integer :: istat(MPI_STATUS_SIZE)
    integer :: n, l, ierr

    integer :: suf, i, j
    suf(i,j) = ADM_gall_1d * ((j)-1) + (i)
    !---------------------------------------------------------------------------

    !--- control volume points at the north pole
    do l = ADM_rgn_nmax, 1, -1
       if ( ADM_rgn_vnum(ADM_N,l) == ADM_VLINK_NMAX ) then
          do n = 1, ADM_VLINK_NMAX
             rgntab(n) = ADM_rgn_vtab(ADM_RID,ADM_N,l,n)
             prctab(n) = ADM_rgn2prc(rgntab(n))
          enddo
          exit
       endif
    enddo

    send_flag(:) = .false.

    do n = 1, ADM_VLINK_NMAX
       do l = 1, ADM_lall
          if ( ADM_prc_tab(l,ADM_prc_me) == rgntab(n) ) then
             vsend_pl(:,n) = GRD_xt(suf(ADM_gmin,ADM_gmax),ADM_KNONE,l,ADM_TJ,:) ! [mod] H.Yashiro 20120525

             call MPI_ISEND( vsend_pl(:,n),        & ! [mod] H.Yashiro 20120525
                             3,                    &
                             MPI_DOUBLE_PRECISION, &
                             ADM_prc_npl-1,        &
                             rgntab(n),            &
                             ADM_COMM_RUN_WORLD,   &
                             sreq(n),              &
                             ierr                  )

             send_flag(n) = .true.
          endif
       enddo
    enddo

    if ( ADM_prc_me == ADM_prc_npl ) then
       do n = 1, ADM_VLINK_NMAX
          call MPI_IRECV( vrecv_pl(:,n),        & ! [mod] H.Yashiro 20120525
                          3,                    &
                          MPI_DOUBLE_PRECISION, &
                          prctab(n)-1,          &
                          rgntab(n),            &
                          ADM_COMM_RUN_WORLD,   &
                          rreq(n),              &
                          ierr                  )
       enddo
    endif

    do n = 1, ADM_VLINK_NMAX
       if ( send_flag(n) ) then
          call MPI_WAIT(sreq(n),istat,ierr)
       endif
    enddo

    if ( ADM_prc_me == ADM_prc_npl ) then
       do n = 1, ADM_VLINK_NMAX
          call MPI_WAIT(rreq(n),istat,ierr)
          GRD_xt_pl(n+1,ADM_KNONE,ADM_NPL,:) = vrecv_pl(:,n) ! [mod] H.Yashiro 20120525
       enddo
    endif

    !--- control volume points at the sourth pole
    do l = 1, ADM_rgn_nmax
       if ( ADM_rgn_vnum(ADM_S,l) == ADM_VLINK_NMAX ) then
          do n = 1, ADM_VLINK_NMAX
             rgntab(n) = ADM_rgn_vtab(ADM_RID,ADM_S,l,n)
             prctab(n) = ADM_rgn2prc(rgntab(n))
          enddo
          exit
       endif
    enddo

    send_flag(:) = .false.

    do n = 1, ADM_VLINK_NMAX
       do l =1, ADM_lall
          if (ADM_prc_tab(l,ADM_prc_me) == rgntab(n) ) then
             vsend_pl(:,n) = GRD_xt(suf(ADM_gmax,ADM_gmin),ADM_KNONE,l,ADM_TI,:) ! [mod] H.Yashiro 20120525
             call MPI_ISEND( vsend_pl(:,n),        & ! [mod] H.Yashiro 20120525
                             3,                    &
                             MPI_DOUBLE_PRECISION, &
                             ADM_prc_spl-1,        &
                             rgntab(n),            &
                             ADM_COMM_RUN_WORLD,   &
                             sreq(n),              &
                             ierr                  )

             send_flag(n) = .true.
          endif
       enddo
    enddo

    if ( ADM_prc_me == ADM_prc_spl ) then
       do n = 1, ADM_VLINK_NMAX
          call MPI_IRECV( vrecv_pl(:,n),        & ! [mod] H.Yashiro 20120525
                          3,                    &
                          MPI_DOUBLE_PRECISION, &
                          prctab(n)-1,          &
                          rgntab(n),            &
                          ADM_COMM_RUN_WORLD,   &
                          rreq(n),              &
                          ierr                  )
       enddo
    endif

    do n = 1, ADM_VLINK_NMAX
       if ( send_flag(n) ) then
          call MPI_WAIT(sreq(n),istat,ierr)
       endif
    enddo

    if ( ADM_prc_me == ADM_prc_spl ) then
       do n = 1, ADM_VLINK_NMAX
          call MPI_WAIT(rreq(n),istat,ierr)
          GRD_xt_pl(n+1,ADM_KNONE,ADM_SPL,:) = vrecv_pl(:,n) ! [mod] H.Yashiro 20120525
       enddo
    endif

    !--- grid point communication
    call COMM_var(GRD_x,GRD_x_pl,ADM_KNONE,3,comm_type=2,NSval_fix=.false.)
    GRD_xt_pl(ADM_GSLF_PL,:,:,:) = GRD_x_pl(ADM_GSLF_PL,:,:,:)

    return
  end subroutine GRD_gen_plgrid

  !-----------------------------------------------------------------------------
  ! [ADD] R.Yoshida 20121020
  ! imported from ENDGame UK Met.office.
  !-----------------------------------------------------------------------------
  subroutine GRD_jbw_init_topo()
    use mod_misc, only : &
       MISC_get_latlon
    use mod_adm, only :  &
       ADM_lall,         &
       ADM_gall,         &
       ADM_GALL_PL,      &
       ADM_LALL_PL,      &
       ADM_KNONE,        &
       ADM_prc_me,       &
       ADM_prc_pl,       &
       ADM_LOG_FID
    implicit none

    real(8), parameter :: rearth  = 6.371229d+6   ! [m] mean radis of the earth
    real(8), parameter :: rotatn  = 7.29212d-5    ! [s^-1] rotation of the earth
    real(8), parameter :: gravity = 9.80616d0     ! gravity accelaration [ms^-2]
    real(8), parameter :: u00 = 35.0d0
    real(8), parameter :: eps = 1.0d-14
    logical, parameter :: deep_atm = .false.      ! deep atmosphere setting

    real(8) :: cs32ev, pi, piby2, f1, f2, min_surf
    real(8) :: lat, p_lat, proj
    real(8) :: rsurf  (ADM_gall,ADM_lall)        ! surface height in ICO-grid
    real(8) :: rsurf_p(ADM_GALL_PL,ADM_LALL_PL)   ! surface height in ICO-grid for pole region

    integer :: n, l
    !---------------------------------------------------------------------------

    pi    = 2.D0 * asin(1.D0)
    piby2 = pi / 2.0d0
    cs32ev = ( COS((1.0d0 - 0.252d0)*piby2) )**1.5d0
    !
    ! for globe
    do l=1, ADM_lall
    DO n=1, ADM_gall
       if ( deep_atm ) then
          rsurf(n,l) = rearth
       else
          rsurf(n,l) = 0.0d0
       endif
       !
       proj=sqrt (GRD_x(n,ADM_KNONE,l,GRD_XDIR)*GRD_x(n,ADM_KNONE,l,GRD_XDIR) &
                  + GRD_x(n,ADM_KNONE,l,GRD_YDIR)*GRD_x(n,ADM_KNONE,l,GRD_YDIR))
       if (proj<eps) then
          lat=sign (0.5d0*pi,GRD_x(n,ADM_KNONE,l,GRD_ZDIR)) !# pole points
       else
          lat=atan (GRD_x(n,ADM_KNONE,l,GRD_ZDIR)/proj)
       end if
       !
       f1 = 10.0d0/63.0d0 - 2.0d0*( sin(lat)**6.0d0)*( cos(lat)**2.0d0 + 1.0d0/3.0d0 )
       f2 = 1.6d0*( cos(lat)**3.0d0)*(sin(lat)**2.0d0 + 2.0d0/3.0d0 ) - 0.25d0*pi
       rsurf(n,l) = rsurf(n,l) + u00*cs32ev*( f1*u00*cs32ev + f2*rearth*rotatn )/gravity
    ENDDO
    enddo
    !
    if ( deep_atm ) then
       write (ADM_LOG_FID, '(A)') "|-- Deep atmosphere setting [jbw_init topo]"
       min_surf = 0.0d0
    else
       min_surf = minval(rsurf)
    endif
    do l=1, ADM_lall
    do n=1, ADM_gall
       GRD_zs(n,ADM_KNONE,l,GRD_ZSFC) = rsurf(n,l) - min_surf
    enddo
    enddo

    ! for pole region
    if ( ADM_prc_me==ADM_prc_pl ) then !---------------------------------
       do l=1, ADM_LALL_PL
       do n=1, ADM_GALL_PL
          if ( deep_atm ) then
             rsurf_p(n,l) = rearth
          else
             rsurf_p(n,l) = 0.0d0
          endif
          !
          proj=sqrt (GRD_x_pl(n,ADM_KNONE,l,GRD_XDIR)*GRD_x_pl(n,ADM_KNONE,l,GRD_XDIR) &
                     + GRD_x_pl(n,ADM_KNONE,l,GRD_YDIR)*GRD_x_pl(n,ADM_KNONE,l,GRD_YDIR))
          if (proj<eps) then
             p_lat=sign (0.5d0*pi,GRD_x_pl(n,ADM_KNONE,l,GRD_ZDIR)) !# pole points
          else
             p_lat=atan (GRD_x_pl(n,ADM_KNONE,l,GRD_ZDIR)/proj)
          end if
          !
          f1 = 10.0d0/63.0d0 - 2.0d0*( sin(p_lat)**6)*( cos(p_lat)**2 + 1.0d0/3.0d0 )
          f2 = 1.6d0*( cos(p_lat)**3)*(sin(p_lat)**2 + 2.0d0/3.0d0 ) - 0.25d0*pi
          rsurf_p(n,l) = rsurf_p(n,l) + u00*cs32ev*( f1*u00*cs32ev + f2*rearth*rotatn )/gravity
       enddo
       enddo
       !
       if ( deep_atm ) then
          write (ADM_LOG_FID, '(A)') "|-- Deep atmosphere setting (pole) [jbw_init topo]"
          min_surf = 0.0d0
       else
          min_surf = minval(rsurf)
       endif
       do l=1, ADM_LALL_PL
       do n=1, ADM_GALL_PL
          GRD_zs_pl(n,ADM_KNONE,l,GRD_ZSFC) = rsurf_p(n,l) - min_surf
       enddo
       enddo
       !
    endif  !-------------------------------------------------------------

    write(ADM_LOG_FID,*) 'Msg : Sub[GRD_input_topograph]/Mod[grid]'
    write (ADM_LOG_FID, '("   *** Topography for JBW: -- MAX: ",F9.3,2X,"MIN: ",F9.3)') &
           maxval(GRD_zs(:,:,:,GRD_ZSFC)), minval(GRD_zs(:,:,:,GRD_ZSFC))
    return
  end subroutine GRD_jbw_init_topo

end module mod_grd
!-------------------------------------------------------------------------------