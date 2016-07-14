!-------------------------------------------------------------------------------
!>
!! History module
!!
!! @par Description
!!         This module is for managing the output variables
!!
!! @author M.Satoh
!!
!! @par History
!! @li      2005-11-29 (M.Satoh)    [new]
!! @li      2005-12-14 (S.Iga)      ADM_gall
!! @li      2006-02-16 (M.Satoh)    T. Mitsui: correct timing
!! @li      2006-08-07 (W.Yanase)   v_save=0 in history_setup, NO_VINTRPL
!! @li      2007-01-19 (K.Suzuki)   higher vectorized rate and allowing undefined value in average
!! @li      2007-06-27 (Y.Niwa)     add MONTHLY_AVERAGE option add ktype 'GL' 'GO' options
!! @li      2007-07-02 (Y.Niwa)     bug fix
!! @li      2007-11-30 (Y.Niwa)     add option for output at pressure levels
!! @li      2007-12-05 (T.Mitsui)   bug fix
!! @li      2008-05-30 (T.Mitsui)   distinguish w-grid, and option of v_interpolation
!! @li      2009-07-13 (S.Iga)      check_count is added. (nmhist miswriting checker)
!! @li      2010-05-11 (M.Satoh)    add l_region in history_in
!! @li      2011-04-26 (C.Kodama)   support >10000 time steps
!! @li      2011-09-03 (H.Yashiro)  New I/O
!! @li      2012-01-26 (Y.Yamada)   trivial bug fix
!! @li      2012-03-28 (T.Seiki)    fix undefined reference
!! @li      2012-06-07 (T.Seiki)    add output_path for multi-job run
!! @li      2012-11-05 (H.Yashiro)  NICAM milestone project (Phase I:cleanup of shared module)
!!
!<
module mod_history
  !-----------------------------------------------------------------------------
  !
  !++ Used modules
  !
  use mod_precision
  use mod_stdio
  !-----------------------------------------------------------------------------
  implicit none
  private
  !-----------------------------------------------------------------------------
  !
  !++ Public procedure
  !
  public :: history_setup
  public :: history_in
  public :: history_out

  !-----------------------------------------------------------------------------
  !
  !++ Public parameters & variables
  !
  integer,                public              :: HIST_req_nmax
  character(len=H_SHORT), public, allocatable :: item_save(:)
  logical,                public              :: HIST_output_step0 = .false.

  !-----------------------------------------------------------------------------
  !
  !++ Private procedure
  !
  private :: history_outlist
  private :: get_log_pres

  !-----------------------------------------------------------------------------
  !
  !++ Private parameters & variables
  !
  integer, private, parameter :: HIST_req_limit = 1000
  real(RP),private, parameter :: EPS_ZERO = 1.E-16_RP

  character(len=H_LONG),  private :: HIST_io_fname  = ''
  character(len=H_MID),   private :: HIST_io_desc   = ''
  integer,                private :: HIST_dtype     = -1
  character(len=H_LONG),  private :: output_path    = ''
  character(len=H_LONG),  private :: histall_fname  = ''
  character(len=H_SHORT), private :: output_io_mode
  integer,                private :: output_size    = 4
  integer,                private :: npreslev       = 1
  real(RP),               private :: pres_levs(60)  != CONST_PRE00
  logical,                private :: check_flag     = .true.

  integer,                private :: ksum
  logical,                private :: calc_pressure = .false.

  character(len=H_LONG),  private, allocatable :: file_save (:)
  character(len=H_MID),   private, allocatable :: desc_save (:)
  character(len=H_SHORT), private, allocatable :: unit_save (:)
  integer,                private, allocatable :: step_save (:)
  character(len=H_SHORT), private, allocatable :: ktype_save(:)
  integer,                private, allocatable :: kstr_save (:)
  integer,                private, allocatable :: kend_save (:)
  integer,                private, allocatable :: kmax_save (:)
  character(len=H_SHORT), private, allocatable :: output_type_save  (:)
  logical,                private, allocatable :: out_prelev_save   (:)
  logical,                private, allocatable :: out_vintrpl_save  (:)
  logical,                private, allocatable :: opt_wgrid_save    (:)
  logical,                private, allocatable :: opt_lagintrpl_save(:)

  character(len=H_SHORT), private, allocatable :: lname_save   (:)
  integer,                private, allocatable :: tmax_save    (:)
  real(DP),               private, allocatable :: tstr_save    (:)
  real(DP),               private, allocatable :: tend_save    (:)
  integer,                private, allocatable :: month_old    (:)
  integer,                private, allocatable :: l_region_save(:)

  integer,                public,  allocatable :: ksumstr  (:)
  integer,                private, allocatable :: ksumend  (:)
  real(RP),               private, allocatable :: tsum_save(:,:)
  logical,                private, allocatable :: flag_save(:)

  real(RP),               public,  allocatable :: v_save   (:,:,:,:)
  real(RP),               private, allocatable :: v_save_pl(:,:,:,:)
  real(RP),               private, allocatable :: zlev_save(:)

  real(RP),               private, allocatable :: pres_levs_ln(:)
  integer,                public,  allocatable :: cnvpre_klev(:,:,:)
  real(RP),               public,  allocatable :: cnvpre_fac1(:,:,:)
  real(RP),               public,  allocatable :: cnvpre_fac2(:,:,:)
  !-----------------------------------------------------------------------------
contains
  !-----------------------------------------------------------------------------
  subroutine history_setup
    use mod_process, only: &
       PRC_MPIstop
    use mod_io_param, only: &
       IO_REAL4, &
       IO_REAL8
    use mod_const, only: &
       PRE00 => CONST_PRE00
    use mod_calendar, only: &
       CALENDAR_ss2yh
    use mod_adm, only: &
       ADM_lall,      &
       ADM_lall_pl,   &
       ADM_gall,      &
       ADM_gall_pl,   &
       ADM_kmin,      &
       ADM_kmax,      &
       ADM_vlayer
    use mod_grd, only: &
       GRD_gz
    use mod_time, only: &
       TIME_CTIME
    use mod_runconf, only: &
       RUNNAME
    implicit none

    character(len=H_SHORT) :: hist3D_layername  != ''
    integer                :: step_def          = 1
    character(len=H_SHORT) :: ktype_def         != ''
    integer                :: kstr_def          = 1
    integer                :: kend_def          != ADM_vlayer
    integer                :: kmax_def          != ADM_vlayer
    character(len=H_SHORT) :: output_type_def   != 'SNAPSHOT'
    logical                :: out_prelev_def    = .false.
    logical                :: no_vintrpl        = .true.
    logical                :: opt_wgrid_def     = .false.
    logical                :: opt_lagintrpl_def = .true.
    logical                :: doout_step0

    character(len=H_SHORT) :: item
    character(len=H_LONG)  :: file
    character(len=H_MID)   :: desc
    character(len=H_SHORT) :: unit
    integer                :: step
    character(len=H_SHORT) :: ktype
    integer                :: kstr
    integer                :: kend
    integer                :: kmax
    character(len=H_SHORT) :: output_type
    logical                :: out_prelev
    logical                :: out_vintrpl
    logical                :: opt_wgrid
    logical                :: opt_lagintrpl

    namelist / NMHISD / &
         output_path,       &
         histall_fname,     &
         hist3D_layername,  &
         output_io_mode,    &
         output_size,       &
         step,              &
         ktype,             &
         kstr,              &
         kend,              &
         kmax,              &
         output_type,       &
         out_prelev,        &
         no_vintrpl,        &
         opt_wgrid_def,     &
         opt_lagintrpl_def, &
         npreslev,          &
         pres_levs,         &
         check_flag,        &
         doout_step0

    namelist / NMHIST / &
         item,         &
         file,         &
         desc,         &
         unit,         &
         step,         &
         ktype,        &
         kstr,         &
         kend,         &
         kmax,         &
         output_type,  &
         out_prelev,   &
         out_vintrpl,  &
         opt_wgrid,    &
         opt_lagintrpl

    character(len=H_SHORT) :: lname

    integer :: idate(6)
    integer :: ierr
    integer :: n
    !---------------------------------------------------------------------------

    ! set default
    output_path       = ''
    histall_fname     = ''
    hist3D_layername  = ''
    output_io_mode    = 'ADVANCED'
    ktype_def         = 'unknown'
    kend_def          = ADM_vlayer
    kmax_def          = ADM_vlayer
    output_type_def   = 'SNAPSHOT'
    pres_levs(:)      = PRE00

    ! nonsence prepare
    step        = step_def
    ktype       = ktype_def
    kstr        = kstr_def
    kend        = kend_def
    kmax        = kmax_def
    output_type = output_type_def
    out_prelev  = out_prelev_def

    doout_step0 = HIST_output_step0

    !--- read parameters
    write(IO_FID_LOG,*)
    write(IO_FID_LOG,*) '+++ Module[history]/Category[nhm share]'
    rewind(IO_FID_CONF)
    read(IO_FID_CONF,nml=NMHISD,iostat=ierr)
    if ( ierr < 0 ) then
       write(IO_FID_LOG,*) '*** NMHISD is not specified. use default.'
    elseif( ierr > 0 ) then
       write(*         ,*) 'xxx Not appropriate names in namelist NMHISD. STOP.'
       write(IO_FID_LOG,*) 'xxx Not appropriate names in namelist NMHISD. STOP.'
       call PRC_MPIstop
    endif
    write(IO_FID_LOG,nml=NMHISD)

    ! nonsence restore
    step_def        = step
    ktype_def       = ktype
    kstr_def        = kstr
    kend_def        = kend
    kmax_def        = kmax
    output_type_def = output_type
    out_prelev_def  = out_prelev

    HIST_output_step0 = doout_step0

    if (      trim(output_io_mode) == 'HIO'      &
         .OR. trim(output_io_mode) == 'ADVANCED' ) then
       write(IO_FID_LOG,*) '*** History output type:', trim(output_io_mode)
    else
       write(IO_FID_LOG,*) 'xxx Invalid output_io_mode!', trim(output_io_mode)
       call PRC_MPIstop
    endif
    HIST_io_fname = trim(output_path)//trim(histall_fname)
    HIST_io_desc  = trim(RUNNAME)

    if    ( output_size == 4 ) then
       HIST_dtype = IO_REAL4
    elseif( output_size == 8 ) then
       HIST_dtype = IO_REAL8
    else
       write(*,*) 'output_size is not appropriate:',output_size
       call PRC_MPIstop
    endif


    ! listup history request
    rewind(IO_FID_CONF)
    do n = 1, HIST_req_limit
       read(IO_FID_CONF,nml=NMHIST,iostat=ierr)
       if ( ierr < 0 ) then
          exit
       elseif( ierr > 0 ) then
          write(*         ,*) 'xxx Not appropriate names in namelist NMHIST. STOP.'
          write(IO_FID_LOG,*) 'xxx Not appropriate names in namelist NMHIST. STOP.'
          call PRC_MPIstop
      endif
    enddo
    HIST_req_nmax = n - 1

    if    ( HIST_req_nmax > HIST_req_limit ) then
       write(IO_FID_LOG,*) '*** request of history file is exceed! n >', HIST_req_limit
    elseif( HIST_req_nmax == 0 ) then
       write(IO_FID_LOG,*) '*** No history file specified.'
       return
    else
       write(IO_FID_LOG,*) '*** Number of requested history item : ', HIST_req_nmax
    endif

    allocate( item_save         (HIST_req_nmax) )
    allocate( file_save         (HIST_req_nmax) )
    allocate( desc_save         (HIST_req_nmax) )
    allocate( unit_save         (HIST_req_nmax) )
    allocate( step_save         (HIST_req_nmax) )
    allocate( ktype_save        (HIST_req_nmax) )
    allocate( kstr_save         (HIST_req_nmax) )
    allocate( kend_save         (HIST_req_nmax) )
    allocate( kmax_save         (HIST_req_nmax) )
    allocate( output_type_save  (HIST_req_nmax) )
    allocate( out_prelev_save   (HIST_req_nmax) )
    allocate( out_vintrpl_save  (HIST_req_nmax) )
    allocate( opt_wgrid_save    (HIST_req_nmax) )
    allocate( opt_lagintrpl_save(HIST_req_nmax) )
    item_save         (:) = ""
    file_save         (:) = ""
    desc_save         (:) = ""
    unit_save         (:) = ""
    step_save         (:) = 0
    ktype_save        (:) = ""
    kstr_save         (:) = -1
    kend_save         (:) = -1
    kmax_save         (:) = 0
    output_type_save  (:) = ""
    out_prelev_save   (:) = .false.
    out_vintrpl_save  (:) = .false.
    opt_wgrid_save    (:) = .false.
    opt_lagintrpl_save(:) = .false.

    allocate( lname_save        (HIST_req_nmax) )
    allocate( tmax_save         (HIST_req_nmax) )
    allocate( tstr_save         (HIST_req_nmax) )
    allocate( tend_save         (HIST_req_nmax) )
    allocate( month_old         (HIST_req_nmax) )
    allocate( l_region_save     (HIST_req_nmax) )
    allocate( flag_save         (HIST_req_nmax) )
    lname_save        (:) = ""
    tmax_save         (:) = 0
    tstr_save         (:) = 0.0_DP
    tend_save         (:) = 0.0_DP
    month_old         (:) = 0
    l_region_save     (:) = 0
    flag_save         (:) = .false.

    call CALENDAR_ss2yh( idate, TIME_CTIME )

    rewind(IO_FID_CONF)
    do n = 1, HIST_req_limit

       ! set default
       item          = ''
       file          = ''
       desc          = ''
       unit          = 'NIL'
       step          = step_def
       ktype         = ktype_def
       kstr          = kstr_def
       kend          = kend_def
       kmax          = -1
       output_type   = output_type_def
       out_prelev    = out_prelev_def
       if ( no_vintrpl ) then
          out_vintrpl  = .false.
       else
          out_vintrpl  = .true.
       endif
       opt_wgrid     = opt_wgrid_def
       opt_lagintrpl = opt_lagintrpl_def

       ! read namelist
       read(IO_FID_CONF,nml=NMHIST,iostat=ierr)
       if( ierr /= 0 ) exit

       if ( item == '' ) then
          write(IO_FID_LOG,*) 'xxx Not appropriate names in namelist NMHIST. STOP.'
          call PRC_MPIstop
       endif

       if( file == '' ) file = item

       ! set default layername
       if ( kmax == 1 ) then
          lname = "ZSSFC1"
       else
          lname = "LAYERNM"
       endif

       select case( trim(ktype) )
       case('3D')
          if ( out_prelev ) then
             kstr = 1
             kend = npreslev
          else
             kstr = ADM_kmin
             kend = ADM_kmax
          endif
          lname = hist3D_layername
       case('2D')
          kstr = 1
          kend = 1
          lname = "ZSSFC1"
       endselect

       ! check consistensy between kend and kmax
       if ( kmax > 0 ) then
          if ( kmax /= kend - kstr + 1 ) then
             kend = kstr + kmax - 1
          endif
       else
          kmax = kend - kstr + 1
       endif

       if ( out_prelev ) then
          if ( ktype /= '3D' ) then
             write(IO_FID_LOG,*) '*** Only 3D vars can be output by pressure coordinates. item=', trim(item)
             out_prelev = .false.
          else
             calc_pressure = .true.
          endif
       endif

       if ( out_vintrpl ) then
          if ( ktype /= '3D' ) then
             out_vintrpl = .false.
          endif
       endif

       item_save         (n) = item
       file_save         (n) = file
       desc_save         (n) = desc
       unit_save         (n) = unit
       step_save         (n) = step
       ktype_save        (n) = ktype
       kstr_save         (n) = kstr
       kend_save         (n) = kend
       kmax_save         (n) = kmax
       output_type_save  (n) = output_type
       out_prelev_save   (n) = out_prelev
       out_vintrpl_save  (n) = out_vintrpl
       opt_wgrid_save    (n) = opt_wgrid
       opt_lagintrpl_save(n) = opt_lagintrpl

       lname_save        (n) = lname
       tmax_save         (n) = 0
       tstr_save         (n) = TIME_CTIME
       tend_save         (n) = 0.0_DP

       month_old         (n) = idate(2)
       l_region_save     (n) = 0
    enddo

    allocate( ksumstr(HIST_req_nmax) )
    allocate( ksumend(HIST_req_nmax) )

    ksum = 0
    do n = 1, HIST_req_nmax
       ksumstr(n) = ksum + 1
       ksumend(n) = ksum + kmax_save(n)
       ksum       = ksum + kmax_save(n)
    enddo

    allocate( tsum_save(HIST_req_nmax,ADM_lall) )
    tsum_save(:,:) = 0.0_RP

    ! k-merged history container
    allocate( v_save   (ADM_gall,   ksum,ADM_lall,   1) )
    allocate( v_save_pl(ADM_gall_pl,ksum,ADM_lall_pl,1) )
    v_save   (:,:,:,:) = 0.0_RP
    v_save_pl(:,:,:,:) = 0.0_RP

    allocate( zlev_save(ksum) )

    do n = 1, HIST_req_nmax
       select case( trim(ktype_save(n)) )
       case('3D')
          if ( out_prelev_save(n) ) then
             zlev_save( ksumstr(n):ksumend(n) ) = pres_levs(1:kmax_save(n))
          else
             zlev_save( ksumstr(n):ksumend(n) ) = GRD_gz(ADM_kmin:ADM_kmax)
          endif
       case('2D')
          zlev_save( ksumstr(n):ksumend(n) ) = 0.0_RP
!       case('ISCCP')
!          do k = 1, NTAU_ISCCP*NPRES_ISCCP
!             zlev_save( ksumstr(n) + k-1 ) = real(k,kind=RP)
!          enddo
!       case('GL')
!       case('GO')
!          do k = 1, kmax_save(n)
!             zlev_save( ksumstr(n) + k-1 ) = real(k,kind=RP)
!          enddo
       case default
          zlev_save( ksumstr(n):ksumend(n) ) = GRD_gz( ADM_kmin+kstr_save(n)-1:ADM_kmin+kend_save(n)-1 )
       endselect
    enddo

    allocate( pres_levs_ln(npreslev) )
    pres_levs_ln(1:npreslev) = log( pres_levs(1:npreslev) * 100 )

    allocate( cnvpre_klev(ADM_gall,npreslev,ADM_lall) )
    allocate( cnvpre_fac1(ADM_gall,npreslev,ADM_lall) )
    allocate( cnvpre_fac2(ADM_gall,npreslev,ADM_lall) )

    return
  end subroutine history_setup

  !-----------------------------------------------------------------------------
  subroutine  history_in( item, gd, l_region )
    use mod_process, only : &
       PRC_MPIstop
    use mod_const, only: &
       UNDEF => CONST_UNDEF
    use mod_calendar, only: &
       CALENDAR_ss2yh
    use mod_adm, only: &
       ADM_l_me,    &
       ADM_lall,    &
       ADM_gall,    &
       ADM_gall_in, &
       ADM_gmin,    &
       ADM_gmax,    &
       ADM_kmin
    use mod_time, only: &
       TIME_CSTEP, &
       TIME_DTL
    implicit none

    character(len=*), intent(in) :: item
    real(RP),         intent(in) :: gd(:,:)
    integer,          intent(in), optional :: l_region

    character(len=H_SHORT) :: hitem
    integer                 :: ijdim_input
    integer                 :: kdim_input

    logical :: save_var
    integer :: kmax
    integer :: i, j, g, g2, k, k2, l, n
    !---------------------------------------------------------------------------

    hitem = trim(item)

    ijdim_input = size(gd,1)
    kdim_input  = size(gd,2)

    if (       ijdim_input /= ADM_gall_in &
         .AND. ijdim_input /= ADM_gall    ) then
       write(IO_FID_LOG,*) '+++ Module[history]/Category[nhm share]'
       write(IO_FID_LOG,*) 'xxx invalid dimension, item=', hitem, &
                           ', ijdim_input=', ijdim_input, &
                           ', ADM_gall_in=', ADM_gall_in, &
                           ', ADM_gall=',    ADM_gall
       call PRC_MPIstop
    endif

    if ( calc_pressure ) then
       call get_log_pres
    endif

    do n = 1, HIST_req_nmax

       save_var = .false.

       ! Item is required or not? ( Same name can be contained in item_save )
       if ( hitem == item_save(n) ) then

          flag_save(n) = .true.

          if ( ktype_save(n) == '3D' ) then ! trim HALO
             if ( kdim_input-2 /= kmax_save(n) ) then
                write(IO_FID_LOG,*) '+++ Module[history]/Category[nhm share]'
                write(IO_FID_LOG,*) '*** Size unmatch, item=', hitem, &
                                    ', kdim_input=', kdim_input, &
                                    ', kmax_save=',  kmax_save(n)
             endif
          else
             if ( kdim_input /= kmax_save(n) ) then
                write(IO_FID_LOG,*) '+++ Module[history]/Category[nhm share]'
                write(IO_FID_LOG,*) '*** Size unmatch, item=', hitem, &
                                    ', kdim_input=', kdim_input, &
                                    ', kmax_save=',  kmax_save(n)
             endif
          endif

          ! add data or not?
          if ( trim(output_type_save(n)) == 'SNAPSHOT' ) then
             if( mod(TIME_CSTEP+1,step_save(n)) == 0 ) save_var = .true.
          else
             save_var = .true.
          endif
       endif

       if ( save_var ) then

          if ( present(l_region) ) then
             l_region_save(n) = l_region
          elseif( ADM_l_me >= 1 .and. ADM_l_me <= ADM_lall ) then
             l_region_save(n) = ADM_l_me
          else
             l_region_save(n) = l_region_save(n) + 1
             if( l_region_save(n) > ADM_lall ) l_region_save(n) = 1 ! cyclic
          endif

          kmax = min( kmax_save(n), kdim_input )
          l    = l_region_save(n)

          if ( .NOT. out_prelev_save(n) ) then ! normal

             if ( ktype_save(n) == '3D' ) then ! trim HALO

                if ( ijdim_input == ADM_gall_in ) then
                   do k = 1, kmax
                      g = 1
                      do j = ADM_gmin, ADM_gmax+1
                      do i = ADM_gmin, ADM_gmax+1
                         g2 = suf(i,j)
                         k2 = ksumstr(n)-1 + k

                         v_save(g2,k2,l,1) = v_save(g2,k2,l,1) + gd(g,k+ADM_kmin-1) * TIME_DTL

                         g = g + 1
                      enddo
                      enddo
                   enddo
                else ! ijdim_input == ADM_gall
                   do k = 1, kmax
                   do g = 1, ADM_gall
                      k2 = ksumstr(n)-1 + k

                      v_save(g,k2,l,1) = v_save(g,k2,l,1) + gd(g,k+ADM_kmin-1) * TIME_DTL
                   enddo
                   enddo
                endif

             else

                if (ijdim_input == ADM_gall_in) then
                   do k = 1, kmax
                      g = 1
                      do j = ADM_gmin, ADM_gmax+1
                      do i = ADM_gmin, ADM_gmax+1
                         g2 = suf(i,j)
                         k2 = ksumstr(n)-1 + k

                         v_save(g2,k2,l,1) = v_save(g2,k2,l,1) + gd(g,k) * TIME_DTL

                         g = g + 1
                      enddo
                      enddo
                   enddo
                else ! ijdim_input == ADM_gall
                   do k = 1, kmax
                   do g = 1, ADM_gall
                      k2 = ksumstr(n)-1 + k

                      v_save(g,k2,l,1) = v_save(g,k2,l,1) + gd(g,k) * TIME_DTL
                   enddo
                   enddo
                endif

             endif

          else ! convert to pressure level

             if (ijdim_input == ADM_gall_in) then
                do k2 = 1, npreslev
                   g = 1
                   do j = ADM_gmin, ADM_gmax+1
                   do i = ADM_gmin, ADM_gmax+1
                      g2 = suf(i,j)
                      k  = cnvpre_klev(g2,k,l)

                      if ( k > ADM_kmin ) then
                         v_save(g2,k2,l,1) = ( cnvpre_fac1(g2,k2,l) * gd(g,k-1) &
                                             + cnvpre_fac2(g2,k2,l) * gd(g,k  ) ) * TIME_DTL
                      else
                         v_save(g2,k2,l,1) = UNDEF
                      endif

                      g = g + 1
                   enddo
                   enddo
                enddo
             else ! ijdim_input == ADM_gall
                do k = 1, kmax
                do g = 1, ADM_gall
                   k2 = ksumstr(n)-1 + k

                   if ( k > ADM_kmin ) then
                      v_save(g,k2,l,1) = ( cnvpre_fac1(g,k2,l) * gd(g,k-1) &
                                         + cnvpre_fac2(g,k2,l) * gd(g,k  ) ) * TIME_DTL
                   else
                      v_save(g,k2,l,1) = UNDEF
                   endif
                enddo
                enddo
             endif

          endif ! z*-level or p-level

          tsum_save(n,l) = tsum_save(n,l) + TIME_DTL

       endif ! save data ?
    enddo

    return
  end subroutine history_in

  !----------------------------------------------------------------------------
  subroutine history_out
    use mod_process, only : &
       PRC_MPIstop
    use mod_calendar, only : &
       CALENDAR_ss2yh, &
       CALENDAR_ss2cc
    use mod_adm, only: &
       ADM_gall,      &
       ADM_gall_pl,   &
       ADM_lall,      &
       ADM_lall_pl,   &
       ADM_kall,      &
       ADM_kmax,      &
       ADM_kmin
    use mod_comm, only : &
       COMM_var
    use mod_fio, only: &
       FIO_output
    use mod_hio, only: &
       HIO_output
    use mod_time, only: &
       TIME_CSTEP, &
       TIME_CTIME
    use mod_gtl, only: &
       GTL_max, &
       GTL_min
    use mod_vintrpl, only: &
       VINTRPL_z_level, &
       VINTRPL_z_level2
    implicit none

    real(RP) :: tmp   (ADM_gall,   ADM_kall,ADM_lall   )
    real(RP) :: tmp_pl(ADM_gall_pl,ADM_kall,ADM_lall_pl)
    real(RP) :: val_max, val_min

    character(len=20)      :: HTIME
    character(len=H_SHORT) :: item

    logical, save :: first = .true.

    integer :: idate(6)
    logical :: out_var(HIST_req_limit)
    integer :: num_output
    integer :: g, k, l, n
    !---------------------------------------------------------------------------

    if ( first ) then
       call history_outlist
       first = .false.
    endif

    call CALENDAR_ss2yh( idate, TIME_CTIME )

    ! count up output vars at this time
    out_var(:) = .false.
    num_output = 0
    do n = 1, HIST_req_nmax
       if ( flag_save(n) ) then
          if ( trim(output_type_save(n)) == 'MONTHLY_AVERAGE' ) then
             if ( idate(2) /= month_old(n) ) then
                out_var(n)   = .true.
                month_old(n) = idate(2)

                num_output = num_output + 1
             endif
          else
             if ( mod( TIME_CSTEP, step_save(n) ) == 0 ) then
                out_var(n) = .true.

                num_output = num_output + 1
             endif
          endif
       endif
    enddo

    ! At least one variable will output, do communication
    if ( num_output > 0 ) then
       write(IO_FID_LOG,*) '### HISTORY num_output = ', num_output
       call CALENDAR_ss2cc( HTIME, TIME_CTIME )
       write(IO_FID_LOG,*) '###         date-time  = ', HTIME

       call COMM_var( v_save, v_save_pl, KSUM, 1 )
    else
       return
    endif

    do n = 1, HIST_req_nmax

       if ( out_var(n) ) then

          tmax_save(n) = tmax_save(n) + 1
          tend_save(n) = TIME_CTIME

          do l = 1, ADM_lall
          do k = ksumstr(n), ksumend(n)
          do g = 1, ADM_gall
             if ( abs(v_save(g,k,l,1)) < EPS_ZERO ) then ! tentaive: to avode floating invalid
                v_save(g,k,l,1) = EPS_ZERO
             else
                v_save(g,k,l,1) = v_save(g,k,l,1) / tsum_save(n,l)
             endif
          enddo
          enddo
          enddo

          do l = 1, ADM_lall_pl
          do k = ksumstr(n), ksumend(n)
          do g = 1, ADM_gall_pl
             if ( abs(v_save_pl(g,k,l,1)) < EPS_ZERO ) then ! tentaive: to avode floating invalid
                v_save_pl(g,k,l,1) = EPS_ZERO
             else
                v_save_pl(g,k,l,1) = v_save_pl(g,k,l,1) / tsum_save(n,1)
             endif
          enddo
          enddo
          enddo

          item = item_save(n)
          val_max =  GTL_max( v_save   (:,:,:,1),          &
                              v_save_pl(:,:,:,1),          &
                              ksum, ksumstr(n), ksumend(n) )
          val_min =  GTL_min( v_save   (:,:,:,1),          &
                              v_save_pl(:,:,:,1),          &
                              ksum, ksumstr(n), ksumend(n) )

          if ( out_vintrpl_save(n) ) then
             do k = Adm_kmin, Adm_kmax
                tmp   (:,k,:) = v_save   (:,ksumstr(n)+k-2,:,1)
                tmp_pl(:,k,:) = v_save_pl(:,ksumstr(n)+k-2,:,1)
             enddo

             tmp   (:,ADM_kmin-1,:) = tmp   (:,ADM_kmin,:)
             tmp   (:,ADM_kmax+1,:) = tmp   (:,ADM_kmax,:)
             tmp_pl(:,ADM_kmin-1,:) = tmp_pl(:,ADM_kmin,:)
             tmp_pl(:,ADM_kmax+1,:) = tmp_pl(:,ADM_kmax,:)

             if ( opt_lagintrpl_save(n) ) then
                call VINTRPL_z_level ( tmp, tmp_pl, opt_wgrid_save(n) )
             else
                call VINTRPL_z_level2( tmp, tmp_pl, opt_wgrid_save(n) )
             endif

             do k = ADM_kmin, ADM_kmax
                v_save   (:,ksumstr(n)+k-2,:,1) = tmp   (:,k,:)
                v_save_pl(:,ksumstr(n)+k-2,:,1) = tmp_pl(:,k,:)
             enddo
          endif

          write(IO_FID_LOG,'(A,A16,A,1PE24.17,A,E24.17)') ' [', item(1:16), '] max=', val_max, ', min=', val_min

          if ( trim(output_io_mode) == 'POH5' ) then

             if ( trim(output_type_save(n)) == 'SNAPSHOT' ) then

                call HIO_output( v_save(:,:,:,1),                             & ! [IN]
                                 HIST_io_fname,    HIST_io_desc    , '',      & ! [IN]
                                 file_save(n),     desc_save(n), '',          & ! [IN]
                                 unit_save(n),     HIST_dtype,                & ! [IN]
                                 lname_save(n),    ksumstr(n),   ksumend(n),  & ! [IN]
                                 tmax_save(n),     tend_save(n), tend_save(n) ) ! [IN]

             elseif(trim(output_type_save(n)) == 'AVERAGE') then

                call HIO_output( v_save(:,:,:,1),                             & ! [IN]
                                 HIST_io_fname,    HIST_io_desc    , '',      & ! [IN]
                                 file_save(n),     desc_save(n), '',          & ! [IN]
                                 unit_save(n),     HIST_dtype,                & ! [IN]
                                 lname_save(n),    ksumstr(n),   ksumend(n),  & ! [IN]
                                 tmax_save(n),     tstr_save(n), tend_save(n) ) ! [IN]

             endif

          elseif( trim(output_io_mode) == 'ADVANCED' ) then

             if ( trim(output_type_save(n)) == 'SNAPSHOT' ) then

                call FIO_output( v_save(:,:,:,1),                             & ! [IN]
                                 HIST_io_fname,    HIST_io_desc    , '',      & ! [IN]
                                 file_save(n),     desc_save(n), '',          & ! [IN]
                                 unit_save(n),     HIST_dtype,                & ! [IN]
                                 lname_save(n),    ksumstr(n),   ksumend(n),  & ! [IN]
                                 tmax_save(n),     tend_save(n), tend_save(n) ) ! [IN]

             elseif(trim(output_type_save(n)) == 'AVERAGE') then

                call FIO_output( v_save(:,:,:,1),                             & ! [IN]
                                 HIST_io_fname,    HIST_io_desc    , '',      & ! [IN]
                                 file_save(n),     desc_save(n), '',          & ! [IN]
                                 unit_save(n),     HIST_dtype,                & ! [IN]
                                 lname_save(n),    ksumstr(n),   ksumend(n),  & ! [IN]
                                 tmax_save(n),     tstr_save(n), tend_save(n) ) ! [IN]

             endif

          endif

          ! reset saved variable
          v_save   (:,ksumstr(n):ksumend(n),:,1) = 0.0_RP
          v_save_pl(:,ksumstr(n):ksumend(n),:,1) = 0.0_RP

          tstr_save(n) = TIME_CTIME
          tsum_save(n,:) = 0.0_RP
       endif
    enddo

  end subroutine history_out

  !-----------------------------------------------------------------------------
  subroutine history_outlist
    use mod_process, only : &
       PRC_MPIstop
    implicit none

    character(len=H_SHORT) :: item
    character(len=H_LONG)  :: file
    character(len=H_SHORT) :: unit
    character(len=H_SHORT) :: ktype
    character(len=H_SHORT) :: otype

    integer :: n
    !---------------------------------------------------------------------------

    write(IO_FID_LOG,*)
    write(IO_FID_LOG,*) '*** [HIST] Output item list '
    write(IO_FID_LOG,*) '*** Total number of requested history item :', HIST_req_nmax
    write(IO_FID_LOG,*) '============================================================================'
    write(IO_FID_LOG,*) 'NAME            :Save name       :UNIT            :Avg.type        :interval'
    write(IO_FID_LOG,*) '                :Vert.type       :# of layer      :p?  :z?  :zh? :lag.intrp?'
    write(IO_FID_LOG,*) '============================================================================'

    do n = 1, HIST_req_nmax
       item  = item_save(n)
       file  = file_save(n)
       unit  = unit_save(n)
       ktype = ktype_save(n)
       otype = output_type_save(n)

       write(IO_FID_LOG,'(1x,A16,A,A16,A,A16,A,A16,A,I8)')      item (1:16), &
                                                           ":", file (1:16), &
                                                           ":", unit (1:16), &
                                                           ":", otype(1:16), &
                                                           ":", step_save(n)

       write(IO_FID_LOG,'(17x,A,A16,A,I016,A,L04,A,L04,A,L04,A,L04)') ":", ktype(1:16),           &
                                                                      ":", kmax_save(n),          &
                                                                      ":", out_prelev_save   (n), &
                                                                      ":", out_vintrpl_save  (n), &
                                                                      ":", opt_wgrid_save    (n), &
                                                                      ":", opt_lagintrpl_save(n)

       if ( .NOT. flag_save(n) ) then ! not stored yet or never
          write(IO_FID_LOG,*) '+++ this variable is requested but not stored yet. check!'
          if ( check_flag ) then
             write(IO_FID_LOG,*) 'xxx history check_flag is on. stop!'
             call PRC_MPIstop
          endif
       endif
    enddo

    write(IO_FID_LOG,*) '============================================================================'
    write(IO_FID_LOG,*)

    return
  end subroutine history_outlist

  !-----------------------------------------------------------------------------
  subroutine get_log_pres
    use mod_adm, only: &
       ADM_KNONE,   &
       ADM_lall,    &
       ADM_lall_pl, &
       ADM_gall,    &
       ADM_gall_pl, &
       ADM_kall,    &
       ADM_kmax,    &
       ADM_kmin
    use mod_grd, only: &
       GRD_zs,   &
       GRD_ZSFC, &
       GRD_vz,   &
       GRD_Z
    use mod_vmtr, only: &
       VMTR_RGSGAM2
    use mod_runconf, only: &
       TRC_VMAX
    use mod_thrmdyn, only: &
       THRMDYN_tempre
    use mod_prgvar, only: &
       prgvar_get
    implicit none

    real(RP) :: rhog     (ADM_gall   ,ADM_kall,ADM_lall   )
    real(RP) :: rhog_pl  (ADM_gall_pl,ADM_kall,ADM_lall_pl)
    real(RP) :: rhogvx   (ADM_gall   ,ADM_kall,ADM_lall   )
    real(RP) :: rhogvx_pl(ADM_gall_pl,ADM_kall,ADM_lall_pl)
    real(RP) :: rhogvy   (ADM_gall   ,ADM_kall,ADM_lall   )
    real(RP) :: rhogvy_pl(ADM_gall_pl,ADM_kall,ADM_lall_pl)
    real(RP) :: rhogvz   (ADM_gall   ,ADM_kall,ADM_lall   )
    real(RP) :: rhogvz_pl(ADM_gall_pl,ADM_kall,ADM_lall_pl)
    real(RP) :: rhogw    (ADM_gall   ,ADM_kall,ADM_lall   )
    real(RP) :: rhogw_pl (ADM_gall_pl,ADM_kall,ADM_lall_pl)
    real(RP) :: rhoge    (ADM_gall   ,ADM_kall,ADM_lall   )
    real(RP) :: rhoge_pl (ADM_gall_pl,ADM_kall,ADM_lall_pl)
    real(RP) :: rhogq    (ADM_gall   ,ADM_kall,ADM_lall   ,TRC_VMAX)
    real(RP) :: rhogq_pl (ADM_gall_pl,ADM_kall,ADM_lall_pl,TRC_VMAX)

    real(RP) :: rho(ADM_gall,ADM_kall,ADM_lall)
    real(RP) :: ein(ADM_gall,ADM_kall,ADM_lall)
    real(RP) :: q  (ADM_gall,ADM_kall,ADM_lall,TRC_VMAX)
    real(RP) :: tem(ADM_gall,ADM_kall,ADM_lall)
    real(RP) :: pre(ADM_gall,ADM_kall,ADM_lall)

    real(RP) :: pre_sfc(ADM_gall,ADM_KNONE,ADM_lall)

    real(RP) :: lpres_sfc(ADM_gall)
    real(RP) :: lpres    (ADM_gall,ADM_kall)

    integer :: g, k, l, nq, kk
    !---------------------------------------------------------------------------

    cnvpre_fac1(:,:,:) = 0.0_RP
    cnvpre_fac2(:,:,:) = 0.0_RP
    cnvpre_klev(:,:,:) = -1

    call prgvar_get( rhog,   rhog_pl,   & ! [OUT]
                     rhogvx, rhogvx_pl, & ! [OUT]
                     rhogvy, rhogvy_pl, & ! [OUT]
                     rhogvz, rhogvz_pl, & ! [OUT]
                     rhogw,  rhogw_pl,  & ! [OUT]
                     rhoge,  rhoge_pl,  & ! [OUT]
                     rhogq,  rhogq_pl   ) ! [OUT]

    do l = 1, ADM_lall
    do k = 1, ADM_kall
    do g = 1, ADM_gall
       rho(g,k,l) = rhog (g,k,l) * VMTR_RGSGAM2(g,k,l)
       ein(g,k,l) = rhoge(g,k,l) / rhog(g,k,l)
    enddo
    enddo
    enddo

    do nq = 1, TRC_VMAX
    do l = 1, ADM_lall
    do k = 1, ADM_kall
    do g = 1, ADM_gall
       q(g,k,l,nq) = rhogq(g,k,l,nq) / rhog(g,k,l)
    enddo
    enddo
    enddo
    enddo

    call THRMDYN_tempre( ADM_gall,     & ! [IN]
                         ADM_kall,     & ! [IN]
                         ADM_lall,     & ! [IN]
                         ein(:,:,:),   & ! [IN]
                         rho(:,:,:),   & ! [IN]
                         q  (:,:,:,:), & ! [IN]
                         tem(:,:,:),   & ! [OUT]
                         pre(:,:,:)    ) ! [OUT]

    call diag_pre_sfc( ADM_gall,                & ! [IN]
                       ADM_kall,                & ! [IN]
                       ADM_lall,                & ! [IN]
                       GRD_vz (:,:,:,GRD_Z),    & ! [IN]
                       rho    (:,:,:),          & ! [IN]
                       pre    (:,:,:),          & ! [IN]
                       GRD_zs (:,:,:,GRD_ZSFC), & ! [IN]
                       pre_sfc(:,:,:)           ) ! [OUT]

    do l = 1, ADM_lall
       lpres_sfc(:)   = log( pre_sfc(:,ADM_KNONE,l) )
       lpres    (:,:) = log( pre(:,:,l) )

       do kk = 1, npreslev
       do g  = 1, ADM_gall

          if ( lpres_sfc(g) >= pres_levs_ln(kk) ) then

             do k = ADM_kmin, ADM_kmax
                if( pres_levs_ln(kk) > lpres(g,k) ) exit
             enddo

             if( k == ADM_kmin )     k = ADM_kmin + 1 ! extrapolation
             if( k == ADM_kmax + 1 ) k = ADM_kmax     ! extrapolation

             cnvpre_klev(g,kk,l) = k
             cnvpre_fac1(g,kk,l) = ( lpres(g,k) - pres_levs_ln(kk)   ) / ( lpres(g,k) - lpres(g,k-1) )
             cnvpre_fac2(g,kk,l) = ( pres_levs_ln(kk) - lpres(g,k-1) ) / ( lpres(g,k) - lpres(g,k-1) )

          endif
       enddo
       enddo
    enddo

    return
  end subroutine get_log_pres

  !-----------------------------------------------------------------------------
  subroutine diag_pre_sfc( &
       ijdim,  &
       kdim,   &
       ldim,   &
       z,      &
       rho,    &
       pre,    &
       z_sfc,  &
       pre_sfc )
    use mod_const, only: &
       GRAV => CONST_GRAV
    use mod_adm, only: &
       knone => ADM_KNONE, &
       kmin  => ADM_kmin
    implicit none

    integer,  intent(in)  :: ijdim
    integer,  intent(in)  :: kdim
    integer,  intent(in)  :: ldim
    real(RP), intent(in)  :: z      (ijdim,kdim ,ldim) ! altitude [m]
    real(RP), intent(in)  :: rho    (ijdim,kdim ,ldim) ! density  [kg/m3]
    real(RP), intent(in)  :: pre    (ijdim,kdim ,ldim) ! pressure [Pa]
    real(RP), intent(in)  :: z_sfc  (ijdim,knone,ldim) ! surface altitude [m]
    real(RP), intent(out) :: pre_sfc(ijdim,knone,ldim) ! surface pressure [Pa]

    real(RP) :: rho_sfc ! surface density [kg/m3]

    integer :: ij, l
    !---------------------------------------------------------------------------

    do l  = 1, ldim
    do ij = 1, ijdim
       ! surface density: extrapolation
       rho_sfc = ( (z_sfc(ij,knone ,l)-z(ij,kmin+1,l)) * (z_sfc(ij,knone ,l)-z(ij,kmin+2,l)) )                    &
               / ( (z    (ij,kmin  ,l)-z(ij,kmin+1,l)) * (z    (ij,kmin  ,l)-z(ij,kmin+2,l)) ) * rho(ij,kmin  ,l) &
               + ( (z_sfc(ij,knone ,l)-z(ij,kmin  ,l)) * (z_sfc(ij,knone ,l)-z(ij,kmin+2,l)) )                    &
               / ( (z    (ij,kmin+1,l)-z(ij,kmin  ,l)) * (z    (ij,kmin+1,l)-z(ij,kmin+2,l)) ) * rho(ij,kmin+1,l) &
               + ( (z_sfc(ij,knone ,l)-z(ij,kmin  ,l)) * (z_sfc(ij,knone ,l)-z(ij,kmin+1,l)) )                    &
               / ( (z    (ij,kmin+2,l)-z(ij,kmin  ,l)) * (z    (ij,kmin+2,l)-z(ij,kmin+1,l)) ) * rho(ij,kmin+2,l)

       ! surface pressure: hydrostatic balance
       pre_sfc(ij,knone,l) = pre(ij,kmin,l) + 0.5_RP * ( rho(ij,kmin,l)+rho_sfc           ) &
                                            * GRAV   * ( z  (ij,kmin,l)-z_sfc(ij,knone,l) )
    enddo
    enddo

    return
  end subroutine diag_pre_sfc

  !-----------------------------------------------------------------------------
  integer function suf(i,j)
    use mod_adm, only: &
       ADM_gall_1d
    implicit none

    integer :: i, j
    !---------------------------------------------------------------------------

    suf = ADM_gall_1d * (j-1) + i

  end function suf

end module mod_history
!-------------------------------------------------------------------------------
