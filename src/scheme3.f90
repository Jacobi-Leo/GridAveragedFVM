module scheme3
  ! This module calculate the high order scheme based on nodal value
  use constant
  implicit none
  private

  real(kind=WP), parameter :: a = 1.0 ! coefficient in equation
  real(kind=WP), parameter :: L = 1.0 ! length of spatial region to solve
  real(kind=WP), parameter :: T = 1.5 ! length of temporal region to solve

  real(kind=WP) :: kappa

  real(kind=WP), public :: scheme_CFL, scheme_dt, scheme_dx
  integer, public :: scheme_maxStep, scheme_numOfGrid

  ! the primary data of region to solve
  real(kind=WP), public, allocatable, dimension(:) :: scheme_u

  real(kind=WP), public, allocatable, dimension(:) :: scheme_gridSize
  real(kind=WP), public, allocatable, dimension(:) :: scheme_gridNode
  real(kind=WP), public, allocatable, dimension(:) :: scheme_flux

  real(kind=WP), allocatable, dimension(:,:) :: diagonalizer

  public :: scheme_init, scheme_update, scheme_calculateErrorInfinity,&
       & scheme_writeToFile, scheme_uExact, scheme_calculateErrorL1


contains

  subroutine scheme_init ()
    implicit none
    integer :: i

    !! First, read and set input data
    !====================================
    ! Format of input data file (data.in)
    !====================================
    !0.99 \tab ! CFL
    !10   \tab ! numOfGrid
    !====================================
    open(unit=11, file='data.in', action='read', status='old')
    read(11, *) scheme_CFL
    read(11, *) scheme_numOfGrid
    scheme_dx = L / scheme_numOfGrid
    scheme_dt = scheme_dx * scheme_CFL / a
    scheme_maxStep = floor( T / scheme_dt ) + 1
    scheme_dt = T / scheme_maxStep
    kappa = calculateKappa( a )

    !! Second, allocate arrays
    associate( n => scheme_numOfGrid )
      allocate( scheme_gridSize(-1:n+2), scheme_gridNode(-1:n+2), &
           & scheme_u(-1:n+2), scheme_flux(0:n) )
    end associate

    !! Third, set data of arrays
    scheme_gridSize = scheme_dx
    forall ( i = -1:scheme_numOfGrid+2 )
       scheme_gridNode(i) = ( i - 0.5 ) * scheme_dx
    end forall
    
    do i = -1,scheme_numOfGrid+2
       scheme_u(i) = sin( 2.0 * PI * scheme_gridNode(i) )
    end do

    associate( n => scheme_numOfGrid )
      allocate( diagonalizer(1:n, 1:n) )
      call diagonalizerConstructor ()
    end associate
  end subroutine scheme_init

  subroutine scheme_update ()
    implicit none
    ! Update scheme for *ONE* step
    integer :: i
    real(kind=WP), allocatable, dimension(:) :: k1, k2, k3, k4
    real(kind=WP), allocatable, dimension(:) :: u1

    associate(n=>scheme_numOfGrid)
      allocate( u1(1:n) )
      allocate( k1(1:n), k2(1:n), k3(1:n), k4(1:n) )

      ! RK4 method

      u1 = scheme_u(1:n)

      call flux_update()
      forall ( i = 1:n )
         k1(i) = scheme_dt * ( scheme_flux(i-1) - scheme_flux(i) ) / scheme_dx
      end forall
      k1 = matmul( diagonalizer, k1 )
      scheme_u(1:n) = u1 + 0.5 * k1
      call flux_update()

      forall ( i = 1:n )
         k2(i) = scheme_dt * ( scheme_flux(i-1) - scheme_flux(i) ) / scheme_dx
      end forall
      k2 = matmul( diagonalizer, k2 )
      scheme_u(1:n) = u1 + 0.5 * k2
      call flux_update()

      forall ( i = 1:n )
         k3(i) = scheme_dt * ( scheme_flux(i-1) - scheme_flux(i) ) / scheme_dx
      end forall
      k3 = matmul( diagonalizer, k3 )
      scheme_u(1:n) = u1 + k3
      call flux_update()

      forall ( i = 1:n )
         k4(i) = scheme_dt * ( scheme_flux(i-1) - scheme_flux(i) ) / scheme_dx
      end forall
      k4 = matmul( diagonalizer, k4 )
      scheme_u(1:n) = u1 + (k1 + 2.0*k2 + 2.0*k3 + k4) / 6.0

      ! End of RK4

    end associate

  contains

    subroutine flux_update ()
      implicit none
      integer :: i
      real(kind=WP) :: tmp1, tmp2, tmp3

      call scheme_boudaryCondition ()
      do i = 1, scheme_numOfGrid
         tmp1 = scheme_u(i) + scheme_u(i+1)
         tmp2 = scheme_u(i-1) + scheme_u(i+2)
         tmp3 = scheme_u(i+2) - 3.0*scheme_u(i+1) +&
              & 3.0*scheme_u(i) - scheme_u(i-1)
         scheme_flux(i) = 9.0*a/16.0*tmp1 - tmp2*a/16.0 + kappa*a/16.0*tmp3
      end do
      scheme_flux(0) = scheme_flux(scheme_numOfGrid)
    end subroutine flux_update

  end subroutine scheme_update

  function scheme_calculateErrorInfinity (ue) result (error)
    implicit none
    real(kind=WP), intent(in), dimension(scheme_numOfGrid) :: ue
    real(kind=WP) :: error

    associate( n => scheme_numOfGrid )
      error = maxval( abs( ue(1:n) - scheme_u(1:n) ) )
    end associate
  end function scheme_calculateErrorInfinity

  function scheme_calculateErrorL1 (ue) result (error)
    implicit none
    real(kind=WP), intent(in), dimension(scheme_numOfGrid) :: ue
    real(kind=WP) :: error

    associate( n => scheme_numOfGrid )
      error = sum( abs( ue(1:n) - scheme_u(1:n) ) ) / n
    end associate
  end function scheme_calculateErrorL1

  subroutine scheme_boudaryCondition ()
    implicit none
    ! This is periodic boundary condition

    associate(n=>scheme_numOfGrid)
      scheme_u(0) = scheme_u(n)
      scheme_u(-1) = scheme_u(n-1)
      scheme_u(n+1) = scheme_u(1)
      scheme_u(n+2) = scheme_u(2)
    end associate

  end subroutine scheme_boudaryCondition

  subroutine scheme_writeToFile ( n )
    implicit none

    integer, intent(in) :: n
    integer :: i
    character( len = 2 ) :: cTemp

    write(cTemp, '(i2)') n

    open(unit=101, file='data' // trim(adjustl(cTemp)) // '.out',&
         & action='write', status='new')
    write(101, *) (scheme_u(i), i = 1, scheme_numOfGrid)
    close(101)
  end subroutine scheme_writeToFile

  function scheme_uExact () result ( u )
    real(kind=WP), dimension(scheme_numOfGrid) :: u 

    associate( n => scheme_numOfGrid )
      u = sin( 2.0 * PI * (scheme_gridNode(1:scheme_numOfGrid) - a * T ))
    end associate
  end function scheme_uExact

  subroutine diagonalizerConstructor ()
    implicit none

    integer :: i
    integer :: n = 2
    real(kind=WP), allocatable, dimension(:) :: beta

    if ( scheme_numOfGrid <= 5 ) then
       stop 'Need more gird points...'
    end if

    allocate( beta(-n:n) )

    beta(-2) = -1.0 / 384.0 * ( 7.0 + 8.0*kappa + abs(kappa) )
    beta(-1) = 1.0 / 96.0 * ( 11.0 + 4.0*kappa + abs(kappa) )
    beta(0) = 1.0 / 192.0 * ( 155.0 - 3.0*abs(kappa) )
    beta(1) = 1.0 / 96.0 * ( 11.0 - 4.0*kappa + abs(kappa) )
    beta(2) = -1.0 / 384.0 * ( 7.0 - 8.0*kappa + abs(kappa) )

    do i = 3, scheme_numOfGrid-2
       diagonalizer(i, i-2:i+2*n-2) = beta(-n:n)
    end do

    associate( m => scheme_numOfGrid )
      diagonalizer(1,m-1) = beta(-2)
      diagonalizer(1,m) = beta(-1)
      diagonalizer(1,1) = beta(0)
      diagonalizer(1,2) = beta(1)
      diagonalizer(1,3) = beta(2)

      diagonalizer(2,m) = beta(-2)
      diagonalizer(2,1) = beta(-1)
      diagonalizer(2,2) = beta(0)
      diagonalizer(2,3) = beta(1)
      diagonalizer(2,4) = beta(2)

      diagonalizer(m,m-2) = beta(-2)
      diagonalizer(m,m-1) = beta(-1)
      diagonalizer(m,m) = beta(0)
      diagonalizer(m,1) = beta(1)
      diagonalizer(m,2) = beta(2)
      
      diagonalizer(m-1,m-3) = beta(-2)
      diagonalizer(m-1,m-2) = beta(-1)
      diagonalizer(m-1,m-1) = beta(0)
      diagonalizer(m-1,m) = beta(1)
      diagonalizer(m-1,1) = beta(2)
    end associate

    ! calculate the inverse matrix of diagonalizer
    diagonalizer = inv( diagonalizer )

  end subroutine diagonalizerConstructor

  function calculateKappa (a) result (k)
    real(kind=WP) :: k
    real(kind=WP), intent(in) :: a

    if ( abs(a) > epsilon(a) ) then
       k = a / abs(a)
    else
       k = a / (a*a + epsilon(a)*epsilon(a)) / (2 * epsilon(a))
    end if
  end function calculateKappa

  function inv(A) result(Ainv)
    real(kind=WP), dimension(:,:), intent(in) :: A
    real(kind=WP), dimension(size(A,1),size(A,2)) :: Ainv
    real(kind=WP), dimension(size(A,1)) :: work  ! work array for LAPACK
    integer, dimension(size(A,1)) :: ipiv   ! pivot indices
    integer :: n, info

    ! External procedures defined in LAPACK
    external DGETRF
    external DGETRI

    ! Store A in Ainv to prevent it from being overwritten by LAPACK
    Ainv = A
    n = size(A,1)

    ! DGETRF computes an LU factorization of a general M-by-N matrix A
    ! using partial pivoting with row interchanges.
    call DGETRF(n, n, Ainv, n, ipiv, info)

    if (info /= 0) then
       stop 'Matrix is numerically singular!'
    end if

    ! DGETRI computes the inverse of a matrix using the LU factorization
    ! computed by DGETRF.
    call DGETRI(n, Ainv, n, ipiv, work, n, info)

    if (info /= 0) then
       stop 'Matrix inversion failed!'
    end if
  end function inv

end module scheme3
