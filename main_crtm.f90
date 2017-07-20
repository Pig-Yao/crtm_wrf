!
! parallel CRTM main code for WRF output
!  
!---please set Parameters for WRf output, input file(FILE_NAME) in 3.5 & output file in  6.5.
!!

PROGRAM crtm 

  ! ============================================================================
  ! **** ENVIRONMENT SETUP FOR RTM USAGE ****
  !
  ! Module usage
  USE netcdf
  USE mpi_module
  USE CRTM_Module

  ! Disable all implicit typing
  !  IMPLICIT NONE
  ! ============================================================================


  ! ----------
  ! Parameters
  ! ----------
  CHARACTER(*), PARAMETER :: PROGRAM_NAME   = 'ctrm'
  ! ----------
  ! Parameters for WRf output
  ! ----------
   INTEGER, parameter :: xmax=360      !domain size in zonal direction
   INTEGER, parameter :: ymax=181      !domain size in meridional direction
   INTEGER, parameter :: zmax=31       !domain size in vertical direction
   INTEGER, parameter :: n_ch=4        !number of channles 
   INTEGER, parameter :: i_yy=2017     !initial year
   INTEGER, parameter :: i_mm=7        !initial month
   INTEGER, parameter :: i_dd=13       !initial day
   INTEGER, parameter :: i_hh=0        !initial hour
   INTEGER, parameter :: i_mn=0        !initial minute
   INTEGER, parameter :: f_yy=2017     !final year
   INTEGER, parameter :: f_mm=7        !final month
   INTEGER, parameter :: f_dd=13       !final day
   INTEGER, parameter :: f_hh=0        !final hour
   INTEGER, parameter :: f_mn=0        !final minutes
   INTEGER, parameter :: tint=60       !interval time [minutes] < 1 hour
   INTEGER, parameter :: hint=1        !interval time [minutes] in case tint>1h
   INTEGER, parameter :: dom =3        !WRF output domain
   CHARACTER(*), PARAMETER ::DATA_DIR='/home/yxl232/data2/GFS/gfsanl/201707/20170713'
   CHARACTER(*), PARAMETER ::OUTPUT_DIR='/home/yxl232/data2/GFS/gfsanl/201707/20170713'

   REAL, PARAMETER :: P1000MB=100000.D0
   REAL, PARAMETER :: R_D=287.D0
   REAL, PARAMETER :: CP=7.D0*R_D/2.D0
   REAL, PARAMETER :: Re=6378000.0
   REAL, PARAMETER :: sat_h=35780000.0
   REAL, PARAMETER :: sat_lon=-89.5/180.0*3.14159

  ! ============================================================================
  ! 0. **** SOME SET UP PARAMETERS FOR THIS EXAMPLE ****
  !
  ! Profile dimensions...
  INTEGER, PARAMETER :: N_PROFILES  = 1  ! 11934=117*102
  INTEGER, PARAMETER :: N_LAYERS    = zmax
  INTEGER, PARAMETER :: N_ABSORBERS = 2 
  INTEGER, PARAMETER :: N_CLOUDS    = zmax*5
  INTEGER, PARAMETER :: N_AEROSOLS  = 0
  ! ...but only ONE Sensor at a time
  INTEGER, PARAMETER :: N_SENSORS = 1
 
  ! Test GeometryInfo angles. The test scan angle is based
  ! on the default Re (earth radius) and h (satellite height)
  REAL(fp) :: ZENITH_ANGLE, SCAN_ANGLE, sat_dis
!  REAL(fp), PARAMETER :: ZENITH_ANGLE = 20.0_fp
!  REAL(fp), PARAMETER :: SCAN_ANGLE   = 10.782   !atan((6378km*PI*20deg/180deg)/(2*35780km)) !26.37293341421_fp
  ! ============================================================================


  ! ---------
  ! Variables
  ! ---------
  CHARACTER(256) :: Message
  CHARACTER(256) :: Version
  CHARACTER(256) :: Sensor_Id
  CHARACTER(256) :: FILE_NAME
  INTEGER :: Error_Status
  INTEGER :: Allocate_Status
  INTEGER :: n_Channels
  INTEGER :: l, m, irec
  integer :: fid, ncerr, x_dimid, y_dimid, ch_dimid, t_dimid, varid
  integer :: dimids(4)
  
  ! ============================================================================
  ! ---------
  ! Variables for WRF
  ! ---------
  integer :: ncid,ncrcode
  character(LEN=16)  :: var_name
  character(LEN=18)  :: file_date
  character(LEN=3)   :: file_ens
  INTEGER :: k1, k2
  integer :: x, y, tt, v, z, n, reci, ens, n_ec,yy,mm,dd,hh,mn
  INTEGER :: ncl,icl
  real :: level_p(zmax)
  real :: xlat(ymax)  ! latitude
  real :: xlong(xmax) ! longitude
  real :: lat(ymax)   ! in radian
  real :: lon(xmax)   ! in radian
  real :: p(xmax,ymax,zmax)
  real :: pb(xmax,ymax,zmax)
  real :: pres(xmax,ymax,zmax)
  real :: ph(xmax,ymax,zmax+1)
  real :: phb(xmax,ymax,zmax+1)
  real :: delz(zmax)
  real :: t(xmax,ymax,zmax)
  real :: tk(xmax,ymax,zmax)
  real :: qvapor(xmax,ymax,zmax)
  real :: qcloud(xmax,ymax,zmax)
  real :: qrain(xmax,ymax,zmax)
  real :: qice(xmax,ymax,zmax)
  real :: qsnow(xmax,ymax,zmax)
  real :: qgraup(xmax,ymax,zmax)
  real :: psfc(xmax,ymax)
  real :: hgt(xmax,ymax)
  real :: tsk(xmax,ymax)
  real :: landmask(xmax,ymax)
  real :: Tbsend(xmax,ymax,n_ch)
  real :: Tb(xmax,ymax,n_ch)

  ! ============================================================================

  ! ============================================================================
  ! 1. **** DEFINE THE CRTM INTERFACE STRUCTURES ****
  !
  TYPE(CRTM_ChannelInfo_type)             :: ChannelInfo(N_SENSORS)
  TYPE(CRTM_Geometry_type)                :: Geometry(N_PROFILES)
  TYPE(CRTM_Atmosphere_type)              :: Atm(N_PROFILES)
  TYPE(CRTM_Surface_type)                 :: Sfc(N_PROFILES)
  TYPE(CRTM_RTSolution_type), ALLOCATABLE :: RTSolution(:,:)
  TYPE(CRTM_Options_type)                 :: Options(N_PROFILES)
  ! ============================================================================

  call parallel_start()

  ! Program header
  ! --------------
  CALL CRTM_Version( Version )
  if(my_proc_id==0)  write(*,*) "CRTM ver.",TRIM(Version) 

  ! Get sensor id from user
  ! -----------------------
  !WRITE( *,'(/5x,"Enter sensor id [hirs4_n18, amsua_metop-a, or mhs_n18]:")',ADVANCE='NO' )
  !READ( *,'(a)' ) Sensor_Id
  !Sensor_Id = ADJUSTL(Sensor_Id)
  Sensor_Id = ADJUSTL('ahi_h8') !abi_gr
  !WRITE( *,'(//5x,"Running CRTM for ",a," sensor...")' ) TRIM(Sensor_Id)


  ! ============================================================================
  ! 2. **** INITIALIZE THE CRTM ****
  !
  ! 2a. This initializes the CRTM for the sensors
  !     predefined in the example SENSOR_ID parameter.
  !     NOTE: The coefficient data file path is hard-
  !           wired for this example.
  ! --------------------------------------------------
  if(my_proc_id==0) WRITE( *,'(/5x,"Initializing the CRTM...")' )
  Error_Status = CRTM_Init( (/Sensor_Id/), &  ! Input... must be an array, hencethe (/../)
                            ChannelInfo  , &  ! Output
                            IRwaterCoeff_File='Nalli.IRwater.EmisCoeff.bin',&
                            IRlandCoeff_File='IGBP.IRland.EmisCoeff.bin',&
                            File_Path='coefficients/')
  IF ( Error_Status /= SUCCESS ) THEN
    Message = 'Error initializing CRTM'
    CALL Display_Message( PROGRAM_NAME, Message, FAILURE )
    STOP
  END IF

  ! 2b. Determine the total number of channels
  !     for which the CRTM was initialized
  ! ------------------------------------------
  ! Specify channel 14 for GOES-R ABI
  if (Sensor_Id == 'abi_gr' .or. Sensor_Id == 'ahi_h8') then
    Error_Status = CRTM_ChannelInfo_Subset( ChannelInfo(1),Channel_Subset=(/13,14,15,16/) )
    IF ( Error_Status /= SUCCESS ) THEN
      Message = 'Error initializing CRTM'
      CALL Display_Message( PROGRAM_NAME, Message, FAILURE )
      STOP
    END IF
  endif
  n_Channels = SUM(CRTM_ChannelInfo_n_Channels(ChannelInfo))
  ! ============================================================================



  ! ============================================================================
  ! 3. **** ALLOCATE STRUCTURE ARRAYS ****
  !
  ! 3a. Allocate the ARRAYS
  ! -----------------------
  ! Note that only those structure arrays with a channel
  ! dimension are allocated here because we've parameterized
  ! the number of profiles in the N_PROFILES parameter.
  !
  ! Users can make the 
  ! then the INPUT arrays (Atm, Sfc) will also have to be allocated.
  ALLOCATE( RTSolution( n_Channels, N_PROFILES ), STAT=Allocate_Status )
  IF ( Allocate_Status /= 0 ) THEN
    Message = 'Error allocating structure arrays'
    CALL Display_Message( PROGRAM_NAME, Message, FAILURE )
    STOP
  END IF

  call CRTM_RTSolution_Create( RTSolution,  N_LAYERS )
  ! 3b. Allocate the STRUCTURES
  ! ---------------------------
  ! The input FORWARD structure
  CALL CRTM_Atmosphere_Create( Atm, N_LAYERS, N_ABSORBERS, N_CLOUDS, N_AEROSOLS)
  IF ( ANY(.NOT. CRTM_Atmosphere_Associated(Atm)) ) THEN
    Message = 'Error allocating CRTM Atmosphere structures'
    CALL Display_Message( PROGRAM_NAME, Message, FAILURE )
    STOP
  END IF
  ! ============================================================================

  ! ============================================================================
  ! 3.5. **** time-loop ****
  !
  do yy=i_yy,f_yy
   mm_min = 1
   mm_max = 12
   if(yy.eq.f_yy) mm_max = f_mm
   if(yy.eq.i_yy) mm_min = i_mm
   do mm=mm_min,mm_max
    dd_min = 1
    if(mm.eq.1) dd_max = 31
    if(mm.eq.2) dd_max = 28
    if(mm.eq.3) dd_max = 31
    if(mm.eq.4) dd_max = 30
    if(mm.eq.5) dd_max = 31
    if(mm.eq.6) dd_max = 30
    if(mm.eq.7) dd_max = 31
    if(mm.eq.8) dd_max = 31
    if(mm.eq.9) dd_max = 30
    if(mm.eq.10) dd_max = 31
    if(mm.eq.11) dd_max = 30
    if(mm.eq.12) dd_max = 31
    if(mm.eq.f_mm) dd_max = f_dd
    if(mm.eq.i_mm) dd_min = i_dd
    do dd=dd_min,dd_max
     hh_min = 0
     hh_max = 23
     if(dd .eq. f_dd) hh_max = f_hh
     if(dd .eq. i_dd) hh_min = i_hh
     do hh=hh_min,hh_max, hint
      mn_min = 0
      mn_max = 59
      if((hh .eq. f_hh).and.(dd .eq. f_dd)) mn_max = f_mn
      if((hh .eq. i_hh).and.(dd .eq. i_dd)) mn_min = i_mn
      do mn=mn_min,mn_max,tint
      write(file_date,'(i1,a1,i4.4,a1,i2.2,a1,i2.2,a1,i2.2,a1,i2.2)')dom,'_',yy,'-',mm,'-',dd,'_',hh,':',mn
      FILE_NAME = DATA_DIR//'/wrfout_d0'//file_date//':00'
      FILE_NAME = ADJUSTL(FILE_NAME)
      if(my_proc_id==0)write(*,*) FILE_NAME
  ! ============================================================================
  ! 4. **** ASSIGN INPUT DATA ****
  !
  ! Fill the Atm structure array.
  ! NOTE: This is an example program for illustrative purposes only.
  !       Typically, one would not assign the data as shown below,
  !       but rather read it from file

  ! 4a1. Loading Atmosphere and Surface input
  ! --------------------------------
  !   CALL Load_wrf_Data()


!  call get_variable2d(FILE_NAME,'XLAT',xmax,ymax,1,xlat)
!  call get_variable2d(FILE_NAME,'XLONG',xmax,ymax,1,xlong)
!  call get_variable3d(FILE_NAME,'P',xmax,ymax,zmax,1,p)
!  call get_variable3d(FILE_NAME,'PB',xmax,ymax,zmax,1,pb)
!  call get_variable3d(FILE_NAME,'PH',xmax,ymax,zmax+1,1,ph)
!  call get_variable3d(FILE_NAME,'PHB',xmax,ymax,zmax+1,1,phb)
!  call get_variable3d(FILE_NAME,'T',xmax,ymax,zmax,1,t)
!  call get_variable3d(FILE_NAME,'QVAPOR',xmax,ymax,zmax,1,qvapor)
!  call get_variable3d(FILE_NAME,'QCLOUD',xmax,ymax,zmax,1,qcloud)
!  call get_variable3d(FILE_NAME,'QRAIN',xmax,ymax,zmax,1,qrain)
!  call get_variable3d(FILE_NAME,'QICE',xmax,ymax,zmax,1,qice)
!  call get_variable3d(FILE_NAME,'QSNOW',xmax,ymax,zmax,1,qsnow)
!  call get_variable3d(FILE_NAME,'QGRAUP',xmax,ymax,zmax,1,qgraup)
!  call get_variable2d(FILE_NAME,'PSFC',xmax,ymax,1,psfc)
!  call get_variable2d(FILE_NAME,'TSK',xmax,ymax,1,tsk)
!  call get_variable2d(FILE_NAME,'HGT',xmax,ymax,1,hgt)
!  call get_variable2d(FILE_NAME,'LANDMASK',xmax,ymax,1,landmask)

  ! hardware the file name for testing
  FILE_NAME='/home/yxl232/data2/GFS/gfsanl/201707/20170713/gfsanl_3_20170713_0000_000.nc'
  print *, FILE_NAME
  call get_variable1d(FILE_NAME,'pressure',zmax,1,level_p)
  call get_variable1d(FILE_NAME,'latitude',ymax,1,xlat)
  call get_variable1d(FILE_NAME,'longitude',xmax,1,xlong)
!  call get_variable3d(FILE_NAME,'P',xmax,ymax,zmax,1,p)
!  call get_variable3d(FILE_NAME,'PB',xmax,ymax,zmax,1,pb)
!  call get_variable3d(FILE_NAME,'PH',xmax,ymax,zmax+1,1,ph)
!  call get_variable3d(FILE_NAME,'PHB',xmax,ymax,zmax+1,1,phb)
  call get_variable3d(FILE_NAME,'TMP',xmax,ymax,zmax,1,t)
!  call get_variable3d(FILE_NAME,'QVAPOR',xmax,ymax,zmax,1,qvapor)
!  call get_variable3d(FILE_NAME,'QCLOUD',xmax,ymax,zmax,1,qcloud)
!  call get_variable3d(FILE_NAME,'QRAIN',xmax,ymax,zmax,1,qrain)
!  call get_variable3d(FILE_NAME,'QICE',xmax,ymax,zmax,1,qice)
!  call get_variable3d(FILE_NAME,'QSNOW',xmax,ymax,zmax,1,qsnow)
!  call get_variable3d(FILE_NAME,'QGRAUP',xmax,ymax,zmax,1,qgraup)
  call get_variable2d(FILE_NAME,'PRES_surface',xmax,ymax,1,psfc)
  call get_variable2d(FILE_NAME,'TMP_surface',xmax,ymax,1,tsk)
!  call get_variable2d(FILE_NAME,'HGT',xmax,ymax,1,hgt)
!  call get_variable2d(FILE_NAME,'LANDMASK',xmax,ymax,1,landmask)






  lat = xlat/180.0*3.14159
  lon = xlong/180.0*3.14159
  pres = P + PB
  tk = (T + 300.0) * ( (pres / P1000MB) ** (R_D/CP) )
  where(qvapor.lt.0.0) qvapor=1.0e-8
  where(qcloud.lt.0.0) qcloud=0.0
  where(qice.lt.0.0) qice=0.0
  where(qrain.lt.0.0) qrain=0.0
  where(qsnow.lt.0.0) qsnow=0.0
  where(qgraup.lt.0.0) qgraup=0.0


  ! 4a2. Converting WRF data for CRTM structure
  ! --------------------------------
  !--- calculating for every grid

  if(mod(ymax,nprocs).eq.0) then
     nyi=ymax/nprocs
  else
     nyi=ymax/nprocs+1
  endif
  ystart=my_proc_id*nyi+1
  yend=min(ymax,(my_proc_id+1)*nyi)
  do y=ystart,yend
  do x=1, xmax
  CALL Convert_wrf_crtm_nocloud()

  ! 4b. GeometryInfo input
  ! ----------------------
  ! All profiles are given the same value
  !  The Sensor_Scan_Angle is optional.
  CALL CRTM_Geometry_SetValue( Geometry, &
                               Sensor_Zenith_Angle = ZENITH_ANGLE, &
                               Sensor_Scan_Angle   = SCAN_ANGLE )


  ! 4c. Use the SOI radiative transfer algorithm
  ! --------------------------------------------
  Options%RT_Algorithm_ID = RT_SOI
  ! ============================================================================

  ! ============================================================================
  ! 5. **** CALL THE CRTM FORWARD MODEL ****
  !

if( zenith_angle > 0 .and. zenith_angle < 80) then
if( zenith_angle <2 .and. y==90) then
    print *, RTSolution(4,1)%Radiance
    call CRTM_RTSolution_ZERO(RTSolution)
endif
  Error_Status = CRTM_Forward( Atm        , &
                               Sfc        , &
                               Geometry   , &
                               ChannelInfo, &
                               RTSolution , &
                               Options = Options )
  IF ( Error_Status /= SUCCESS ) THEN
    Message = 'Error in CRTM Forward Model'
    CALL Display_Message( PROGRAM_NAME, Message, FAILURE )
    STOP
  END IF
if( zenith_angle <31 .and. zenith_angle >29 .and. y==90) then
    print *, RTSolution(4,1)%Is_Allocated
    call CRTM_RTSolution_Inspect(RTSolution(4,1))
    print *, sum(RTSolution(4,1)%Layer_Optical_Depth)
    
    
    print *, (RTSolution(4,1)%Surface_Planck_Radiance * RTSolution(4,1)%Surface_Emissivity + &
              RTSolution(4,1)%Down_Radiance           * RTSolution(4,1)%Surface_Reflectivity ) 
    
         
    print *, (RTSolution(4,1)%Surface_Planck_Radiance * RTSolution(4,1)%Surface_Emissivity + &
              RTSolution(4,1)%Down_Radiance           * RTSolution(4,1)%Surface_Reflectivity ) * &
            product( exp(-1.0 * (RTSolution(4,1)%Layer_Optical_Depth(1:31))/ cos(zenith_angle *PI/180.0) )) + &
             RTSolution(4,1)%Up_radiance 
endif
end if

  ! ============================================================================



  ! ============================================================================
  ! 6. **** OUTPUT THE RESULTS TO SCREEN ****
  !
  ! User should read the user guide or the source code of the routine
  ! CRTM_RTSolution_Inspect in the file CRTM_RTSolution_Define.f90 to
  ! select the needed variables for outputs.  These variables are contained
  ! in the structure RTSolution.
  !
  !DO m = 1, N_PROFILES
  !  WRITE( *,'(//7x,"Profile ",i0," output for ",a )') n, TRIM(Sensor_Id)
  !  DO l = 1, n_Channels
  !    WRITE( *, '(/5x,"Channel ",i0," results")') RTSolution(l,m)%Sensor_Channel
  !    CALL CRTM_RTSolution_Inspect(RTSolution(l,m))
  !  END DO
  !END DO

  !---for file output, edited 2014.9.26
if( zenith_angle > 0 .and. zenith_angle < 80) then
  do l = 1, n_Channels
    do m = 1, N_PROFILES
      Tbsend(x,y,l) = real(RTSolution(l,m)%Brightness_Temperature)
   enddo
  enddo
else
    Tbsend(x,y,:) = NF_FILL_FLOAT
endif
  !WRITE(*,'(7x,"Profile (",i0,", ",i0,") finished Tb = ",f6.2)')x,y,Tbsend(x,y,2)
  ! ============================================================================

!--- end of x,y-loop
  end do
  end do

  CALL MPI_Allreduce(Tbsend,Tb,xmax*ymax*n_ch,MPI_REAL,MPI_SUM,comm,ierr)

  ! ============================================================================
  !6.5  **** writing the output ****
  !
  if(my_proc_id==0) then
    open(10,file=OUTPUT_DIR//'/Radiance_d0'//file_date//'.bin',&
           form='unformatted',access='direct',recl=4)
    irec = 0
    do y = 1, ymax
    do x = 1, xmax
      irec= irec +1
      write( 10, rec=irec) xlong(x)
    enddo
    enddo
    do y = 1, ymax
    do x = 1, xmax
      irec= irec +1
      write( 10, rec=irec) xlat(y)
    enddo
    enddo

    do l = 1, n_ch
      do y = 1, ymax
      do x = 1, xmax
        irec= irec +1
        write( 10, rec=irec) Tb(x,y,l)
      enddo
      enddo
    enddo
    close (10)
  !  initializing the Tbsend fields for Bcast
    Tbsend = 0.0

    ncerr = nf_create(trim(FILE_NAME)//'.out.nc', nf_clobber, fid) 
    if (ncerr .ne. nf_noerror) then
        print *, 'Error: ', nf_strerror(ncerr)
    endif
    
    ncerr = nf_def_dim(fid, 'lat', ymax, x_dimid)
    if (ncerr .ne. nf_noerror) then
        print *, 'Error: ', nf_strerror(ncerr)
    endif
    ncerr = nf_def_dim(fid, 'lon', xmax, y_dimid)
    if (ncerr .ne. nf_noerror) then
        print *, 'Error: ', nf_strerror(ncerr)
    endif
    ncerr = nf_def_dim(fid, 'ch',  4,   ch_dimid)
    if (ncerr .ne. nf_noerror) then
        print *, 'Error: ', nf_strerror(ncerr)
    endif
    ncerr = nf_def_dim(fid, 'time',  4,   t_dimid)
    if (ncerr .ne. nf_noerror) then
        print *, 'Error: ', nf_strerror(ncerr)
    endif
    dimids(2) = x_dimid
    dimids(1) = y_dimid
    dimids(3) = ch_dimid
    dimids(4) = t_dimid
    ncerr = nf_def_var(fid, 'tb', NF_FLOAT, 4, dimids, varid)
    if (ncerr .ne. nf_noerror) then
        print *, 'Error: ', nf_strerror(ncerr)
    endif
    ncerr = nf_enddef(fid)

    call write_variable3d(fid, 'tb', xmax, ymax, 4, 1, TB)
    call close_file(fid)
  endif

  ! ============================================================================
  !  **** initializing all Tb and Tbsend fields ****
  !
  Tb = 0.0
  CALL MPI_BCAST(Tbsend,xmax*ymax*n_ch,MPI_REAL,0,comm,ierr)


  !---end of mn & dd & hh & mm & yy loop
  enddo 
  enddo 
  enddo 
  enddo 
  enddo



  ! ============================================================================
  ! 7. **** DESTROY THE CRTM ****
  !
  if(my_proc_id==0) WRITE( *, '( /5x, "Destroying the CRTM..." )' )
  Error_Status = CRTM_Destroy( ChannelInfo )
  IF ( Error_Status /= SUCCESS ) THEN
    Message = 'Error destroying CRTM'
    CALL Display_Message( PROGRAM_NAME, Message, FAILURE )
    STOP
  END IF
  ! ============================================================================

  call parallel_finish()

  ! ============================================================================
   !---for debug
   !write(*,*) 'lpres',atm(1)%Level_Pressure
   !write(*,*) 'Pres',atm(1)%Pressure
   !write(*,*) 'Temp', atm(1)%Temperature
   !write(*,*) 'H2O', atm(1)%Absorber(:,1)
   !write(*,*) 'delz',delz
   !write(*,*) 'hgt',hgt(x,y)
   !write(*,*) 'ph',ph(x,y,:)
   !write(*,*) 'phb',phb(x,y,:)
   !write(*,*) 'qcloud',qcloud(x,y,:)
   !write(*,*) 'qice',qice(x,y,:)
   !write(*,*) 'qsnow',qsnow(x,y,:)
   !write(*,*) 'qrain',qrain(x,y,:)
   !write(*,*) 'qgraup',qgraup(x,y,:)
   !do z=1,ncl
   !write(*,*)
   !'cloud',atm(1)%Cloud(z)%Type,minval(atm(1)%Cloud(z)%Water_Content),'~',maxval(atm(1)%Cloud(z)%Water_Content)
   !enddo
  ! ============================================================================


CONTAINS

  INCLUDE "Convert_wrf_crtm_nocloud.inc"

END PROGRAM crtm

