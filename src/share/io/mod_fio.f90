!-------------------------------------------------------------------------------
!>
!! File I/O module
!!
!! @par Description
!!         This module is continer for file I/O (PaNDa format)
!!
!! @author H.Tomita, H.Yashiro
!!
!! @par History
!! @li      2011-07-27 (H.Tomita)  [NEW]
!! @li      2011-08-19 (H.Yashiro) Incorporate into NICAM
!! @li      2011-09-03 (H.Yashiro) Complete format specification
!! @li      2011-12-14 (T.Seiki)   allocatable => pointer in type structure
!! @li      2012-02-01 (T.Seiki)   fix array size over in array assignment
!!
!<
module mod_fio
  !-----------------------------------------------------------------------------
  !
  !++ Used modules
  !
  use mod_precision
  use mod_io_param
  use mod_stdio
  use mod_debug
  !-----------------------------------------------------------------------------
  implicit none
  private
  !-----------------------------------------------------------------------------
  !
  !++ Public procedures
  !
  public :: FIO_setup
  public :: FIO_input
  public :: FIO_seek
  public :: FIO_output
  public :: FIO_close
  public :: FIO_finalize

  interface FIO_input
     module procedure FIO_input_SP
     module procedure FIO_input_DP
  end interface FIO_input

  interface FIO_output
     module procedure FIO_output_SP
     module procedure FIO_output_DP
  end interface FIO_output

  !-----------------------------------------------------------------------------
  !
  !++ Public parameters & variables
  !
  !> struct for package infomation
  type, public :: headerinfo
     character(len=H_LONG)  :: fname         !< file name
     character(len=H_MID)   :: description   !< file description
     character(len=H_LONG)  :: note          !< longer note of file
     integer                :: num_of_data   !< number of data
     integer                :: fmode         !< file mode(0,1,2)
     integer                :: endiantype    !< endian type(0,1,2)
     integer                :: grid_topology !< grid topology(0,1,2)
     integer                :: glevel        !< glevel
     integer                :: rlevel        !< rlevel
     integer                :: num_of_rgn    !< number of region
     integer, pointer       :: rgnid(:)      !< array of region id
  endtype headerinfo

  !> struct for data infomation
  type, public :: datainfo
     character(len=H_SHORT) :: varname      !< variable name
     character(len=H_MID)   :: description  !< variable description
     character(len=H_SHORT) :: unit         !< unit of variable
     character(len=H_SHORT) :: layername    !< layer name
     character(len=H_LONG)  :: note         !< longer note of variable
     integer(DP)            :: datasize     !< data size
     integer                :: datatype     !< data type(0,1,2,3)
     integer                :: num_of_layer !< number of layer
     integer                :: step
     integer(DP)            :: time_start
     integer(DP)            :: time_end
  endtype datainfo

  !-----------------------------------------------------------------------------
  !
  !++ Private procedures
  !
  !-----------------------------------------------------------------------------
  !
  !++ Private parameters & variables
  !
  integer,               private, parameter :: FIO_nmaxfile = 64
  character(len=H_LONG), private            :: FIO_fname_list(FIO_nmaxfile)
  integer,               private            :: FIO_fid_list  (FIO_nmaxfile)
  integer,               private            :: FIO_fid_count = 1

  type(headerinfo), private :: hinfo
  type(datainfo),   private :: dinfo

  integer, private, parameter :: max_num_of_data = 2500 !--- max time step num
  integer, private, parameter :: preclist(0:3) = (/ 4, 8, 4, 8 /)

  !-----------------------------------------------------------------------------
contains
  !-----------------------------------------------------------------------------
  !> Setup this module.
  !!
  !! Must be called first.
  !!
  subroutine FIO_setup
    use mod_adm, only: &
       ADM_prc_tab, &
       ADM_prc_me,  &
       ADM_glevel,  &
       ADM_rlevel,  &
       ADM_lall
    implicit none

    integer, allocatable :: prc_tab(:)
    !---------------------------------------------------------------------------

    write(IO_FID_LOG,*)
    write(IO_FID_LOG,*) '+++ Module[fio]/Category[common share]'

    ! dummy call
    call DEBUG_rapstart('FILEIO_in')
    call DEBUG_rapend  ('FILEIO_in')
    call DEBUG_rapstart('FILEIO_out')
    call DEBUG_rapend  ('FILEIO_out')

    allocate( prc_tab(ADM_lall) )
    prc_tab(1:ADM_lall) = ADM_prc_tab(1:ADM_lall,ADM_prc_me)-1

    call fio_syscheck()
    call fio_put_commoninfo( IO_SPLIT_FILE,  &
                             IO_BIG_ENDIAN,  &
                             IO_ICOSAHEDRON, &
                             ADM_glevel,     &
                             ADM_rlevel,     &
                             ADM_lall,       &
                             prc_tab         )

    deallocate(prc_tab)

    allocate( hinfo%rgnid(ADM_lall) )

    return
  end subroutine FIO_setup

  !-----------------------------------------------------------------------------
  !> Get file ID of given basename.
  !!
  !! Open it if not opened yet.
  !!
  subroutine FIO_getfid( &
       fid,      &
       basename, &
       rwtype,   &
       pkg_desc, &
       pkg_note  )
    use mod_adm, only: &
       ADM_prc_me
    implicit none

    integer,          intent(out) :: fid      !< file ID
    character(len=*), intent(in)  :: basename !< basename of file
    integer,          intent(in)  :: rwtype   !< file access type
    character(len=*), intent(in)  :: pkg_desc !< package(file) description
    character(len=*), intent(in)  :: pkg_note !< package(file) note

    character(len=H_SHORT) :: rwname(0:2)
    data rwname / 'READ','WRITE','APPEND' /

    character(len=H_LONG) :: fname
    integer               :: n
    !---------------------------------------------------------------------------

    !--- search existing file
    fid = -1
    do n = 1, FIO_fid_count
       if ( basename == FIO_fname_list(n) ) fid = FIO_fid_list(n)
    enddo

    if ( fid < 0 ) then ! file registration
       !--- register new file and open
       call fio_mk_fname(fname,trim(basename),'pe',ADM_prc_me-1,6)
       call fio_register_file(fid,fname)

       if ( rwtype == IO_FREAD ) then

!          call fio_dump_finfo(n,FIO_BIG_ENDIAN,FIO_DUMP_HEADER) ! dump to stdout(check)
          call fio_fopen(fid,rwtype)
          call fio_read_allinfo(fid)

       elseif( rwtype == IO_FWRITE ) then

          call fio_fopen(fid,rwtype)
          call fio_put_write_pkginfo(fid,pkg_desc,pkg_note)

       elseif( rwtype == IO_FAPPEND ) then

          call fio_fopen(fid,rwtype)
          call fio_read_pkginfo(fid)
          call fio_write_pkginfo(fid)

       endif

       write(IO_FID_LOG,'(1x,A,A,A,I3)') '*** [FIO] File registration (ADVANCED) : ', &
                            trim(rwname(rwtype)),' - ', FIO_fid_count
       write(IO_FID_LOG,'(1x,A,I3,A,A)') '*** fid= ', fid, ', name: ', trim(fname)

       FIO_fname_list(FIO_fid_count) = trim(basename)
       FIO_fid_list  (FIO_fid_count) = fid
       FIO_fid_count = FIO_fid_count + 1
    endif

    return
  end subroutine FIO_getfid

  !-----------------------------------------------------------------------------
  !> Input(read) one variable at one step.
  subroutine FIO_input_SP( &
       var,           &
       basename,      &
       varname,       &
       layername,     &
       k_start,       &
       k_end,         &
       step,          &
       allow_missingq ) !--- optional
    use mod_process, only: &
       PRC_MPIstop
    use mod_adm, only: &
       ADM_gall, &
       ADM_lall
    implicit none

    real(SP),         intent(out) :: var(:,:,:) !< variable(ij,k,l)
    character(len=*), intent(in)  :: basename   !< basename of file
    character(len=*), intent(in)  :: varname    !< variable name
    character(len=*), intent(in)  :: layername  !< layer name
    integer,          intent(in)  :: k_start    !< start index of vertical level
    integer,          intent(in)  :: k_end      !< end   index of vertical level
    integer,          intent(in)  :: step       !< step to be read

    logical, intent(in), optional :: allow_missingq !< if data is missing, set value to zero, else execution stops.

    real(SP) :: var4(ADM_gall,k_start:k_end,ADM_lall)
    real(DP) :: var8(ADM_gall,k_start:k_end,ADM_lall)

    integer :: did, fid
    !---------------------------------------------------------------------------

    call DEBUG_rapstart('FILEIO_in')

    !--- search/register file
    call FIO_getfid( fid, basename, IO_FREAD, '', '' )

    !--- seek data ID and get information
    call fio_seek_datainfo(did,fid,varname,step)
    call fio_get_datainfo(fid,did,dinfo)

    !--- verify
    if ( did == -1 ) then
       if ( present(allow_missingq) ) then
          if ( allow_missingq ) then
             write(IO_FID_LOG,*) '*** [INPUT]/[FIO] data not found! : ', &
                                  'varname= ',trim(varname),', step=',step
             write(IO_FID_LOG,*) '*** [INPUT]/[FIO] Q Value is set to 0.'

             var(:,k_start:k_end,:) = 0.0_SP

             call DEBUG_rapend('FILEIO_in')
             return
          endif
       else
          write(IO_FID_LOG,*) 'xxx [INPUT]/[FIO] data not found! : ', &
                               'varname= ',trim(varname),', step=',step
          call PRC_MPIstop
       endif
    endif

    if ( dinfo%layername /= layername ) then
       write(IO_FID_LOG,*) 'xxx [INPUT]/[FIO] layername mismatch! ', &
                            '[',trim(dinfo%layername),':',trim(layername),']'
       call PRC_MPIstop
    elseif( dinfo%num_of_layer /= k_end-k_start+1 ) then
       write(IO_FID_LOG,*) 'xxx [INPUT]/[FIO] num_of_layer mismatch! ', &
                            dinfo%num_of_layer,k_end-k_start+1
       call PRC_MPIstop
    endif

    !--- read data
    if ( dinfo%datatype == IO_REAL4 ) then

       call fio_read_data(fid,did,var4(:,:,:))
       var(:,k_start:k_end,:) = real( var4(:,1:dinfo%num_of_layer,:), kind=SP )

    elseif( dinfo%datatype == IO_REAL8 ) then

       call fio_read_data(fid,did,var8(:,:,:))
       var(:,k_start:k_end,:) = real( var8(:,1:dinfo%num_of_layer,:), kind=SP )

    endif

    call DEBUG_rapend('FILEIO_in')

    return
  end subroutine FIO_input_SP

  !-----------------------------------------------------------------------------
  !> Input(read) one variable at one step.
  subroutine FIO_input_DP( &
       var,           &
       basename,      &
       varname,       &
       layername,     &
       k_start,       &
       k_end,         &
       step,          &
       allow_missingq ) !--- optional
    use mod_process, only: &
       PRC_MPIstop
    use mod_adm, only: &
       ADM_gall, &
       ADM_lall
    implicit none

    real(DP),         intent(out) :: var(:,:,:) !< variable(ij,k,l)
    character(len=*), intent(in)  :: basename   !< basename of file
    character(len=*), intent(in)  :: varname    !< variable name
    character(len=*), intent(in)  :: layername  !< layer name
    integer,          intent(in)  :: k_start    !< start index of vertical level
    integer,          intent(in)  :: k_end      !< end   index of vertical level
    integer,          intent(in)  :: step       !< step to be read

    logical, intent(in), optional :: allow_missingq !< if data is missing, set value to zero, else execution stops.

    real(SP) :: var4(ADM_gall,k_start:k_end,ADM_lall)
    real(DP) :: var8(ADM_gall,k_start:k_end,ADM_lall)

    integer :: did, fid
    !---------------------------------------------------------------------------

    call DEBUG_rapstart('FILEIO_in')

    !--- search/register file
    call FIO_getfid( fid, basename, IO_FREAD, '', '' )

    !--- seek data ID and get information
    call fio_seek_datainfo(did,fid,varname,step)
    call fio_get_datainfo(fid,did,dinfo)

    !--- verify
    if ( did == -1 ) then
       if ( present(allow_missingq) ) then
          if ( allow_missingq ) then
             write(IO_FID_LOG,*) '*** [INPUT]/[FIO] data not found! : ', &
                                  'varname= ',trim(varname),', step=',step
             write(IO_FID_LOG,*) '*** [INPUT]/[FIO] Q Value is set to 0.'

             var(:,k_start:k_end,:) = 0.0_DP

             call DEBUG_rapend('FILEIO_in')
             return
          endif
       else
          write(IO_FID_LOG,*) 'xxx [INPUT]/[FIO] data not found! : ', &
                               'varname= ',trim(varname),', step=',step
          call PRC_MPIstop
       endif
    endif

    if ( dinfo%layername /= layername ) then
       write(IO_FID_LOG,*) 'xxx [INPUT]/[FIO] layername mismatch! ', &
                            '[',trim(dinfo%layername),':',trim(layername),']'
       call PRC_MPIstop
    elseif( dinfo%num_of_layer /= k_end-k_start+1 ) then
       write(IO_FID_LOG,*) 'xxx [INPUT]/[FIO] num_of_layer mismatch! ', &
                            dinfo%num_of_layer,k_end-k_start+1
       call PRC_MPIstop
    endif

    !--- read data
    if ( dinfo%datatype == IO_REAL4 ) then

       call fio_read_data(fid,did,var4(:,:,:))
       var(:,k_start:k_end,:) = real( var4(:,1:dinfo%num_of_layer,:), kind=DP )

    elseif( dinfo%datatype == IO_REAL8 ) then

       call fio_read_data(fid,did,var8(:,:,:))
       var(:,k_start:k_end,:) = real( var8(:,1:dinfo%num_of_layer,:), kind=DP )

    endif

    call DEBUG_rapend('FILEIO_in')

    return
  end subroutine FIO_input_DP

  !-----------------------------------------------------------------------------
  !> Read in all steps of given `varname`, returns total data
  !! size(`num_of_step`) and mid of (time_start+time_end) of each
  !! step(`data_date`).
  !!
  !! `start_step` is maximum step where `ctime < 0.5*(ts(step)+te(step))` is true.
  !!
  !! `prec` is presicion, 4 or 8.
  !!
  !! If `opt_periodic_year` is T, data_date(:,1) is set as cdate(1) on
  !! return, else cdate(:) is neglected.
  !!
  subroutine FIO_seek( &
       start_step,       &
       num_of_step,      &
       data_date,        &
       prec,             &
       basename,         &
       varname,          &
       layername,        &
       k_start,          &
       k_end,            &
       ctime,            &
       cdate,            &
       opt_periodic_year )
    use mod_process, only: &
       PRC_MPIstop
    use mod_calendar, only: &
       calendar_ss2yh, &
       calendar_yh2ss
    implicit none

    integer,          intent(inout) :: start_step
    integer,          intent(inout) :: num_of_step
    integer,          intent(inout) :: data_date(6,max_num_of_data)
    integer,          intent(inout) :: prec
    character(len=*), intent(in)    :: basename
    character(len=*), intent(in)    :: varname
    character(len=*), intent(in)    :: layername      ! for verification only
    integer,          intent(in)    :: k_start, k_end ! for verification only
    real(DP),         intent(in)    :: ctime
    integer,          intent(in)    :: cdate(6)       ! cdate(1) is only used only when opt_periodic_year is T.
    logical,          intent(in)    :: opt_periodic_year

    real(DP) :: midtime !--- [sec]
    logical  :: startflag
    integer  :: did, fid
    integer  :: i
    !---------------------------------------------------------------------------

    call DEBUG_rapstart('FILEIO_in')

    !--- search/register file
    call FIO_getfid( fid, basename, IO_FREAD, '', '' )

    startflag = .false.

    do i = 1, max_num_of_data
       !--- seek data ID and get information
       call fio_seek_datainfo(did,fid,varname,i)
       call fio_get_datainfo (fid,did,dinfo)

       if ( did == -1 ) then
          num_of_step = i - 1
          exit
       endif

       !--- verify
       if ( dinfo%layername /= layername ) then
          write(IO_FID_LOG,*) 'xxx [INPUT]/[FIO] layername mismatch! ', &
                               '[',trim(dinfo%layername),':',trim(layername),']'
          call PRC_MPIstop
       elseif( dinfo%num_of_layer /= k_end-k_start+1 ) then
          write(IO_FID_LOG,*) 'xxx [INPUT]/[FIO] num_of_layer mismatch!', &
                               dinfo%num_of_layer,k_end-k_start+1
          call PRC_MPIstop
       endif

       midtime = real( int( (dinfo%time_start+dinfo%time_end)*0.5_DP+1.0_DP, kind=DP ), kind=DP )
       call calendar_ss2yh( data_date(:,i), midtime )

       if ( opt_periodic_year ) then
          data_date(1,i) = cdate(1)
          call calendar_yh2ss( midtime, data_date(:,i) )
       endif

       if (       ( .not. startflag ) &
            .AND. ( ctime < midtime ) ) then
          startflag  = .true.
          start_step = i
          prec       = preclist(dinfo%datatype)
       endif
    enddo

    call DEBUG_rapend('FILEIO_in')

    return
  end subroutine FIO_seek

  !-----------------------------------------------------------------------------
  !> Append data with data header
  subroutine FIO_output_SP( &
       var,       &
       basename,  &
       pkg_desc,  &
       pkg_note,  &
       varname,   &
       data_desc, &
       data_note, &
       unit,      &
       dtype,     &
       layername, &
       k_start,   &
       k_end,     &
       step,      &
       t_start,   &
       t_end,     &
       append     )
    use mod_process, only: &
       PRC_MPIstop
    use mod_adm, only: &
       ADM_gall, &
       ADM_lall
    use mod_const, only: &
       UNDEF4 => CONST_UNDEF4
    implicit none

    real(SP),         intent(in) :: var(:,:,:)
    character(len=*), intent(in) :: basename
    character(len=*), intent(in) :: pkg_desc
    character(len=*), intent(in) :: pkg_note
    character(len=*), intent(in) :: varname
    character(len=*), intent(in) :: data_desc
    character(len=*), intent(in) :: data_note
    character(len=*), intent(in) :: unit
    integer,          intent(in) :: dtype
    character(len=*), intent(in) :: layername
    integer,          intent(in) :: k_start, k_end
    integer,          intent(in) :: step
    real(DP),         intent(in) :: t_start, t_end

    logical,intent(in), optional :: append

    real(SP) :: var4(ADM_gall,k_start:k_end,ADM_lall)
    real(DP) :: var8(ADM_gall,k_start:k_end,ADM_lall)

    integer :: did, fid
    !---------------------------------------------------------------------------

    call DEBUG_rapstart('FILEIO_out')

    !--- search/register file
    call FIO_getfid( fid, basename, IO_FWRITE, pkg_desc, pkg_note )

    !--- append data to the file
    dinfo%varname      = varname
    dinfo%description  = data_desc
    dinfo%unit         = unit
    dinfo%layername    = layername
    dinfo%note         = data_note
    dinfo%datasize     = int( ADM_gall * ADM_lall * (k_end-k_start+1) * preclist(dtype), kind=DP )
    dinfo%datatype     = dtype
    dinfo%num_of_layer = k_end-k_start+1
    dinfo%step         = step
    dinfo%time_start   = int( t_start, kind=DP )
    dinfo%time_end     = int( t_end,   kind=DP )

    if ( dtype == IO_REAL4 ) then

       var4(:,k_start:k_end,:) = real( var(:,k_start:k_end,:), kind=SP )
       where( var4(:,:,:) < (UNDEF4+1.0_SP) )
          var4(:,:,:) = UNDEF4
       endwhere

       call fio_put_write_datainfo_data(did,fid,dinfo,var4(:,:,:))

    elseif( dtype == IO_REAL8 ) then

       var8(:,k_start:k_end,:) = real( var(:,k_start:k_end,:), kind=DP )

       call fio_put_write_datainfo_data(did,fid,dinfo,var8(:,:,:))

    else
       write(IO_FID_LOG,*) 'xxx [OUTPUT]/[FIO] Unsupported datatype!', dtype
       call PRC_MPIstop
    endif

    call DEBUG_rapend('FILEIO_out')

    return
  end subroutine FIO_output_SP

  !-----------------------------------------------------------------------------
  !> Append data with data header
  subroutine FIO_output_DP( &
       var,       &
       basename,  &
       pkg_desc,  &
       pkg_note,  &
       varname,   &
       data_desc, &
       data_note, &
       unit,      &
       dtype,     &
       layername, &
       k_start,   &
       k_end,     &
       step,      &
       t_start,   &
       t_end,     &
       append     )
    use mod_process, only: &
       PRC_MPIstop
    use mod_adm, only: &
       ADM_gall, &
       ADM_lall
    use mod_const, only: &
       UNDEF4 => CONST_UNDEF4
    implicit none

    real(DP),         intent(in) :: var(:,:,:)
    character(len=*), intent(in) :: basename
    character(len=*), intent(in) :: pkg_desc
    character(len=*), intent(in) :: pkg_note
    character(len=*), intent(in) :: varname
    character(len=*), intent(in) :: data_desc
    character(len=*), intent(in) :: data_note
    character(len=*), intent(in) :: unit
    integer,          intent(in) :: dtype
    character(len=*), intent(in) :: layername
    integer,          intent(in) :: k_start, k_end
    integer,          intent(in) :: step
    real(DP),         intent(in) :: t_start, t_end

    logical,intent(in), optional :: append

    real(SP) :: var4(ADM_gall,k_start:k_end,ADM_lall)
    real(DP) :: var8(ADM_gall,k_start:k_end,ADM_lall)

    integer :: did, fid
    !---------------------------------------------------------------------------

    call DEBUG_rapstart('FILEIO_out')

    !--- search/register file
    call FIO_getfid( fid, basename, IO_FWRITE, pkg_desc, pkg_note )

    !--- append data to the file
    dinfo%varname      = varname
    dinfo%description  = data_desc
    dinfo%unit         = unit
    dinfo%layername    = layername
    dinfo%note         = data_note
    dinfo%datasize     = int( ADM_gall * ADM_lall * (k_end-k_start+1) * preclist(dtype), kind=DP )
    dinfo%datatype     = dtype
    dinfo%num_of_layer = k_end-k_start+1
    dinfo%step         = step
    dinfo%time_start   = int( t_start, kind=DP )
    dinfo%time_end     = int( t_end,   kind=DP )

    if ( dtype == IO_REAL4 ) then

       var4(:,k_start:k_end,:) = real( var(:,k_start:k_end,:), kind=SP )
       where( var4(:,:,:) < (UNDEF4+1.0_SP) )
          var4(:,:,:) = UNDEF4
       endwhere

       call fio_put_write_datainfo_data(did,fid,dinfo,var4(:,:,:))

    elseif( dtype == IO_REAL8 ) then

       var8(:,k_start:k_end,:) = real( var(:,k_start:k_end,:), kind=DP )

       call fio_put_write_datainfo_data(did,fid,dinfo,var8(:,:,:))

    else
       write(IO_FID_LOG,*) 'xxx [OUTPUT]/[FIO] Unsupported datatype!', dtype
       call PRC_MPIstop
    endif

    call DEBUG_rapend('FILEIO_out')

    return
  end subroutine FIO_output_DP

  !-----------------------------------------------------------------------------
  subroutine FIO_close( &
       basename )
    use mod_adm, only: &
       ADM_prc_me
    implicit none

    character(len=*), intent(in) :: basename

    character(len=H_LONG) :: fname

    integer :: fid
    integer :: n
    !---------------------------------------------------------------------------

    !--- search/register file
    do n = 1, FIO_fid_count
       if ( basename == FIO_fname_list(n) ) then
          fid = FIO_fid_list(n)

          call fio_fclose(fid)
          call fio_mk_fname(fname,trim(FIO_fname_list(n)),'pe',ADM_prc_me-1,6)

          write(IO_FID_LOG,'(1x,A,I3,A,A)') &
          '*** [FIO] File close (ADVANCED) fid= ', fid, ', name: ', trim(fname)

          ! remove closed file info from the list
          FIO_fname_list(n) = ''
          FIO_fid_list  (n) = -1
       endif
    enddo

    return
  end subroutine FIO_close

  !-----------------------------------------------------------------------------
  subroutine FIO_finalize
    use mod_adm, only: &
       ADM_prc_me
    implicit none

    character(len=H_LONG) :: fname
    integer               :: n, fid
    !---------------------------------------------------------------------------

    do n = 1, FIO_fid_count
       fid = FIO_fid_list(n)

       call fio_fclose(fid)
       call fio_mk_fname(fname,trim(FIO_fname_list(n)),'pe',ADM_prc_me-1,6)

       write(IO_FID_LOG,'(1x,A,I3,A,A)') &
       '*** [FIO] File close (ADVANCED) fid= ', fid, ', name: ', trim(fname)
    enddo

    return
  end subroutine FIO_finalize

end module mod_fio
