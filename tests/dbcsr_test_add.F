!--------------------------------------------------------------------------------------------------!
! Copyright (C) by the DBCSR developers group - All rights reserved                                !
! This file is part of the DBCSR library.                                                          !
!                                                                                                  !
! For information on the license, see the LICENSE file.                                            !
! For further information please visit https://dbcsr.cp2k.org                                      !
! SPDX-License-Identifier: GPL-2.0+                                                                !
!--------------------------------------------------------------------------------------------------!

MODULE dbcsr_test_add
   !! Tests for DBCSR add
   USE dbcsr_data_methods, ONLY: dbcsr_data_get_sizes, &
                                 dbcsr_data_init, &
                                 dbcsr_data_new, &
                                 dbcsr_data_release, &
                                 dbcsr_type_1d_to_2d
   USE dbcsr_dist_methods, ONLY: dbcsr_distribution_new, &
                                 dbcsr_distribution_release
   USE dbcsr_io, ONLY: dbcsr_print
   USE dbcsr_kinds, ONLY: dp, &
                          real_4, &
                          real_8
   USE dbcsr_methods, ONLY: &
      dbcsr_col_block_sizes, dbcsr_get_data_type, dbcsr_get_matrix_type, dbcsr_name, &
      dbcsr_nblkcols_total, dbcsr_nblkrows_total, dbcsr_nfullcols_total, dbcsr_nfullrows_total, &
      dbcsr_release, dbcsr_row_block_sizes
   USE dbcsr_mpiwrap, ONLY: mp_bcast, &
                            mp_environ, mp_comm_type
   USE dbcsr_operations, ONLY: dbcsr_add, &
                               dbcsr_get_occupation
   USE dbcsr_test_methods, ONLY: compx_to_dbcsr_scalar, &
                                 dbcsr_impose_sparsity, &
                                 dbcsr_make_random_block_sizes, &
                                 dbcsr_make_random_matrix, &
                                 dbcsr_random_dist, &
                                 dbcsr_to_dense_local
   USE dbcsr_transformations, ONLY: dbcsr_redistribute, &
                                    dbcsr_replicate_all
   USE dbcsr_types, ONLY: &
      dbcsr_data_obj, dbcsr_distribution_obj, dbcsr_mp_obj, dbcsr_scalar_type, dbcsr_type, &
      dbcsr_type_antihermitian, dbcsr_type_antisymmetric, dbcsr_type_complex_4, &
      dbcsr_type_complex_4_2d, dbcsr_type_complex_8, dbcsr_type_complex_8_2d, &
      dbcsr_type_hermitian, dbcsr_type_no_symmetry, dbcsr_type_real_4, dbcsr_type_real_4_2d, &
      dbcsr_type_real_8, dbcsr_type_real_8_2d, dbcsr_type_symmetric
   USE dbcsr_work_operations, ONLY: dbcsr_create
#include "base/dbcsr_base_uses.f90"

!$ USE OMP_LIB, ONLY: omp_get_max_threads, omp_get_thread_num, omp_get_num_threads

   IMPLICIT NONE

   PRIVATE

   PUBLIC :: dbcsr_test_adds

   CHARACTER(len=*), PARAMETER, PRIVATE :: moduleN = 'dbcsr_test_add'

CONTAINS

   SUBROUTINE dbcsr_test_adds(test_name, mp_group, mp_env, npdims, io_unit, &
                              matrix_sizes, bs_m, bs_n, sparsities, &
                              alpha, beta, limits, retain_sparsity)
      !! Performs a variety of matrix add

      CHARACTER(len=*), INTENT(IN)                       :: test_name
      TYPE(mp_comm_type), INTENT(IN)                                :: mp_group
         !! MPI communicator
      TYPE(dbcsr_mp_obj), INTENT(IN)                     :: mp_env
      INTEGER, DIMENSION(2), INTENT(in)                  :: npdims
      INTEGER, INTENT(IN)                                :: io_unit
         !! which unit to write to, if not negative
      INTEGER, DIMENSION(:), INTENT(in)                  :: matrix_sizes, bs_m, bs_n
         !! size of matrices to test
         !! block sizes of the 3 dimensions
         !! block sizes of the 3 dimensions
      REAL(real_8), DIMENSION(2), INTENT(in)             :: sparsities
         !! sparsities of matrices to create
      COMPLEX(real_8)                                    :: alpha, beta
      INTEGER, DIMENSION(4), INTENT(in)                  :: limits
      LOGICAL, INTENT(in)                                :: retain_sparsity

      CHARACTER(len=*), PARAMETER :: routineN = 'dbcsr_test_adds'
      CHARACTER, DIMENSION(2, 5), PARAMETER :: symmetries = &
                                               RESHAPE((/dbcsr_type_no_symmetry, dbcsr_type_no_symmetry, &
                                                         dbcsr_type_symmetric, dbcsr_type_symmetric, &
                                                         dbcsr_type_antisymmetric, dbcsr_type_antisymmetric, &
                                                         dbcsr_type_hermitian, dbcsr_type_hermitian, &
                                                         dbcsr_type_antihermitian, dbcsr_type_antihermitian/), (/2, 5/))
      INTEGER, DIMENSION(4), PARAMETER :: types = (/dbcsr_type_real_4, dbcsr_type_real_8, &
                                                    dbcsr_type_complex_4, dbcsr_type_complex_8/)

      CHARACTER                                          :: a_symm, b_symm
      INTEGER                                            :: a_c, a_r, b_c, b_r, handle, isymm, &
                                                            itype, mynode, numnodes, numthreads, &
                                                            TYPE
      INTEGER, DIMENSION(:), POINTER, CONTIGUOUS         :: my_sizes_m, my_sizes_n, sizes_m, sizes_n
      LOGICAL                                            :: do_complex
      TYPE(dbcsr_data_obj)                               :: data_a, data_a_dbcsr, data_b
      TYPE(dbcsr_scalar_type)                            :: alpha_obj, beta_obj
      TYPE(dbcsr_type)                                   :: matrix_a, matrix_b

!   ---------------------------------------------------------------------------

      CALL timeset(routineN, handle)
      NULLIFY (my_sizes_m, my_sizes_n, sizes_m, sizes_n)

      !
      ! print
      CALL mp_environ(numnodes, mynode, mp_group)
      IF (io_unit .GT. 0) THEN
         WRITE (io_unit, *) 'test_name ', test_name
         numthreads = 1
!$OMP PARALLEL
!$OMP MASTER
!$       numthreads = omp_get_num_threads()
!$OMP END MASTER
!$OMP END PARALLEL
         WRITE (io_unit, *) 'numthreads', numthreads
         WRITE (io_unit, *) 'numnodes', numnodes
         WRITE (io_unit, *) 'matrix_sizes', matrix_sizes
         WRITE (io_unit, *) 'sparsities', sparsities
         WRITE (io_unit, *) 'alpha', alpha
         WRITE (io_unit, *) 'beta', beta
         WRITE (io_unit, *) 'limits', limits
         WRITE (io_unit, *) 'retain_sparsity', retain_sparsity
         WRITE (io_unit, *) 'bs_m', bs_m
         WRITE (io_unit, *) 'bs_n', bs_n
      END IF
      !
      !
      ! loop over symmetry
      DO isymm = 1, SIZE(symmetries, 2)
         a_symm = symmetries(1, isymm)
         b_symm = symmetries(2, isymm)

         IF (a_symm .NE. dbcsr_type_no_symmetry .AND. matrix_sizes(1) .NE. matrix_sizes(2)) CYCLE
         IF (b_symm .NE. dbcsr_type_no_symmetry .AND. matrix_sizes(1) .NE. matrix_sizes(2)) CYCLE

         !
         ! loop over types
         DO itype = 1, SIZE(types)
            TYPE = types(itype)

            do_complex = TYPE .EQ. dbcsr_type_complex_4 .OR. TYPE .EQ. dbcsr_type_complex_8

            alpha_obj = compx_to_dbcsr_scalar(alpha, TYPE)
            beta_obj = compx_to_dbcsr_scalar(beta, TYPE)
            IF (do_complex .AND. (a_symm .EQ. dbcsr_type_hermitian .OR. a_symm .EQ. dbcsr_type_antihermitian)) &
               alpha_obj = compx_to_dbcsr_scalar(CMPLX(REAL(alpha, kind=dp), 0.0, dp), TYPE)
            IF (do_complex .AND. (b_symm .EQ. dbcsr_type_hermitian .OR. b_symm .EQ. dbcsr_type_antihermitian)) &
               beta_obj = compx_to_dbcsr_scalar(CMPLX(REAL(beta, kind=dp), 0.0, dp), TYPE)

            !
            ! Create the row/column block sizes.
            CALL dbcsr_make_random_block_sizes(sizes_m, matrix_sizes(1), bs_m)
            CALL dbcsr_make_random_block_sizes(sizes_n, matrix_sizes(2), bs_n)

            !
            ! If A/B has symmetry we need the same row/col blocking
            my_sizes_m => sizes_m
            my_sizes_n => sizes_n
            IF (a_symm .NE. dbcsr_type_no_symmetry) THEN
               my_sizes_n => sizes_m
            END IF
            IF (b_symm .NE. dbcsr_type_no_symmetry) THEN
               my_sizes_n => sizes_m
            END IF

            IF (.FALSE.) THEN
               WRITE (*, *) 'sizes_m', my_sizes_m
               WRITE (*, *) 'sum(sizes_m)', SUM(my_sizes_m), ' matrix_sizes(1)', matrix_sizes(1)
               WRITE (*, *) 'sizes_n', my_sizes_n
               WRITE (*, *) 'sum(sizes_n)', SUM(my_sizes_n), ' matrix_sizes(2)', matrix_sizes(2)
            END IF

            !
            ! Create the undistributed matrices.
            CALL dbcsr_make_random_matrix(matrix_a, my_sizes_m, my_sizes_n, "Matrix A", &
                                          sparsities(1), &
                                          mp_group, data_type=TYPE, symmetry=a_symm)

            CALL dbcsr_make_random_matrix(matrix_b, my_sizes_m, my_sizes_n, "Matrix B", &
                                          sparsities(2), &
                                          mp_group, data_type=TYPE, symmetry=b_symm)

            DEALLOCATE (sizes_m, sizes_n)

            !
            ! convert the dbcsr matrices to denses
            a_r = dbcsr_nfullrows_total(matrix_a); a_c = dbcsr_nfullcols_total(matrix_a)
            b_r = dbcsr_nfullrows_total(matrix_b); b_c = dbcsr_nfullcols_total(matrix_b)
            CALL dbcsr_data_init(data_a)
            CALL dbcsr_data_init(data_b)
            CALL dbcsr_data_init(data_a_dbcsr)
            CALL dbcsr_data_new(data_a, dbcsr_type_1d_to_2d(TYPE), data_size=a_r, data_size2=a_c)
            CALL dbcsr_data_new(data_b, dbcsr_type_1d_to_2d(TYPE), data_size=b_r, data_size2=b_c)
            CALL dbcsr_data_new(data_a_dbcsr, dbcsr_type_1d_to_2d(TYPE), data_size=a_r, data_size2=a_c)
            CALL dbcsr_to_dense_local(matrix_a, data_a)
            CALL dbcsr_to_dense_local(matrix_b, data_b)

            IF (.FALSE.) THEN
               CALL dbcsr_print(matrix_a, matlab_format=.TRUE., variable_name='a0')
               CALL dbcsr_print(matrix_b, matlab_format=.TRUE., variable_name='b0')
            END IF

            !
            ! Prepare test parameters
            CALL test_add(test_name, mp_group, mp_env, npdims, io_unit, &
                          matrix_a, matrix_b, &
                          data_a, data_b, data_a_dbcsr, &
                          alpha_obj, beta_obj, &
                          limits, retain_sparsity)
            !
            ! cleanup
            CALL dbcsr_release(matrix_a)
            CALL dbcsr_release(matrix_b)
            CALL dbcsr_data_release(data_a)
            CALL dbcsr_data_release(data_b)
            CALL dbcsr_data_release(data_a_dbcsr)

         END DO ! itype

      END DO !isymm

      CALL timestop(handle)

   END SUBROUTINE dbcsr_test_adds

   SUBROUTINE test_add(test_name, mp_group, mp_env, npdims, io_unit, &
                       matrix_a, matrix_b, &
                       data_a, data_b, data_a_dbcsr, &
                       alpha, beta, limits, retain_sparsity)
      !! Performs a variety of matrix add

      CHARACTER(len=*), INTENT(IN)                       :: test_name
      TYPE(mp_comm_type), INTENT(IN)                                :: mp_group
         !! MPI communicator
      TYPE(dbcsr_mp_obj), INTENT(IN)                     :: mp_env
      INTEGER, DIMENSION(2), INTENT(in)                  :: npdims
      INTEGER, INTENT(IN)                                :: io_unit
         !! which unit to write to, if not negative
      TYPE(dbcsr_type), INTENT(in)                       :: matrix_a, matrix_b
         !! matrices to add
         !! matrices to add
      TYPE(dbcsr_data_obj)                               :: data_a, data_b, data_a_dbcsr
      TYPE(dbcsr_scalar_type), INTENT(in)                :: alpha, beta
      INTEGER, DIMENSION(4), INTENT(in)                  :: limits
      LOGICAL, INTENT(in)                                :: retain_sparsity

      CHARACTER(len=*), PARAMETER :: routineN = 'test_add'

      INTEGER                                            :: c, handle, r
      INTEGER, DIMENSION(:), POINTER, CONTIGUOUS         :: col_dist_a, col_dist_b, row_dist_a, &
                                                            row_dist_b
      LOGICAL                                            :: success
      REAL(real_8)                                       :: occ_a_in, occ_a_out, occ_b
      TYPE(dbcsr_distribution_obj)                       :: dist_a, dist_b
      TYPE(dbcsr_type)                                   :: m_a, m_b

!   ---------------------------------------------------------------------------

      CALL timeset(routineN, handle)

      ! Row & column distributions
      CALL dbcsr_random_dist(row_dist_a, dbcsr_nblkrows_total(matrix_a), npdims(1))
      CALL dbcsr_random_dist(col_dist_a, dbcsr_nblkcols_total(matrix_a), npdims(2))
      CALL dbcsr_random_dist(row_dist_b, dbcsr_nblkrows_total(matrix_b), npdims(1))
      CALL dbcsr_random_dist(col_dist_b, dbcsr_nblkcols_total(matrix_b), npdims(2))

      CALL dbcsr_distribution_new(dist_a, mp_env, row_dist_a, col_dist_a, reuse_arrays=.TRUE.)
      CALL dbcsr_distribution_new(dist_b, mp_env, row_dist_b, col_dist_b, reuse_arrays=.TRUE.)

      ! Redistribute the matrices
      ! A
      CALL dbcsr_create(m_a, "Test for "//TRIM(dbcsr_name(matrix_a)), &
                        dist_a, dbcsr_get_matrix_type(matrix_a), &
                        row_blk_size_obj=matrix_a%row_blk_size, &
                        col_blk_size_obj=matrix_a%col_blk_size, &
                        data_type=dbcsr_get_data_type(matrix_a))
      CALL dbcsr_distribution_release(dist_a)
      CALL dbcsr_redistribute(matrix_a, m_a)
      ! B
      CALL dbcsr_create(m_b, "Test for "//TRIM(dbcsr_name(matrix_b)), &
                        dist_b, dbcsr_get_matrix_type(matrix_b), &
                        row_blk_size_obj=matrix_b%row_blk_size, &
                        col_blk_size_obj=matrix_b%col_blk_size, &
                        data_type=dbcsr_get_data_type(matrix_b))
      CALL dbcsr_distribution_release(dist_b)
      CALL dbcsr_redistribute(matrix_b, m_b)

      IF (.FALSE.) THEN
         CALL dbcsr_print(m_a, matlab_format=.FALSE., variable_name='a_in_')
         CALL dbcsr_print(m_b, matlab_format=.FALSE., variable_name='b_')
      END IF

      occ_a_in = dbcsr_get_occupation(m_a)
      occ_b = dbcsr_get_occupation(m_b)

      !
      ! Perform add
      IF (ALL(limits == 0)) THEN
         DBCSR_ABORT("limits shouldnt be 0")
      ELSE
         CALL dbcsr_add(m_a, m_b, alpha, beta)
      END IF

      occ_a_out = dbcsr_get_occupation(m_a)

      IF (.FALSE.) THEN
         PRINT *, 'retain_sparsity', retain_sparsity, occ_a_in, occ_b, occ_a_out
         CALL dbcsr_print(m_a, matlab_format=.TRUE., variable_name='a_out_')
      END IF

      CALL dbcsr_replicate_all(m_a)
      CALL dbcsr_to_dense_local(m_a, data_a_dbcsr)
      CALL dbcsr_check_add(test_name, m_a, data_a_dbcsr, data_a, data_b, &
                           alpha, beta, limits, retain_sparsity, io_unit, mp_group, &
                           success)

      r = dbcsr_nfullrows_total(m_a)
      c = dbcsr_nfullcols_total(m_a)

      IF (io_unit .GT. 0) THEN
         IF (success) THEN
            WRITE (io_unit, *) REPEAT("*", 70)
            WRITE (io_unit, *) " -- TESTING dbcsr_add (", &
               dbcsr_get_data_type(m_a), &
               ", ", dbcsr_get_matrix_type(m_a), &
               ", ", dbcsr_get_matrix_type(m_b), &
               ") ............................. PASSED !"
            WRITE (io_unit, *) REPEAT("*", 70)
         ELSE
            WRITE (io_unit, *) REPEAT("*", 70)
            WRITE (io_unit, *) " -- TESTING dbcsr_add (", &
               dbcsr_get_data_type(m_a), &
               ", ", dbcsr_get_matrix_type(m_a), &
               ", ", dbcsr_get_matrix_type(m_b), &
               ") ................. FAILED !"
            WRITE (io_unit, *) REPEAT("*", 70)
            DBCSR_ABORT('Test failed')
         END IF
      END IF

      CALL dbcsr_release(m_a)
      CALL dbcsr_release(m_b)

      CALL timestop(handle)

   END SUBROUTINE test_add

   SUBROUTINE dbcsr_check_add(test_name, matrix_a, dense_a_dbcsr, dense_a, dense_b, &
                              alpha, beta, limits, retain_sparsity, io_unit, mp_group, &
                              success)
      !! Performs a check of matrix adds

      CHARACTER(len=*), INTENT(IN)                       :: test_name
      TYPE(dbcsr_type), INTENT(IN)                       :: matrix_a
      TYPE(dbcsr_data_obj), INTENT(inout)                :: dense_a_dbcsr, dense_a, dense_b
         !! input dense matrices
         !! input dense matrices
      TYPE(dbcsr_scalar_type), INTENT(in)                :: alpha, beta
         !! coefficients for the add
         !! coefficients for the add
      INTEGER, DIMENSION(4), INTENT(in)                  :: limits
         !! limits for the add
      LOGICAL, INTENT(in)                                :: retain_sparsity
      INTEGER, INTENT(IN)                                :: io_unit
         !! io unit for printing
      TYPE(mp_comm_type), INTENT(IN)                     :: mp_group
      LOGICAL, INTENT(out)                               :: success
         !! if passed the check success=T

      CHARACTER(len=*), PARAMETER :: routineN = 'dbcsr_check_add'
      INTEGER                                            :: col, col_size, handle, i, istat, j, ld, &
                                                            lwork, m, mynode, n, numnodes, row, &
                                                            row_size
      CHARACTER, PARAMETER                               :: norm = 'I'

      LOGICAL                                            :: valid
      REAL(real_4), ALLOCATABLE, DIMENSION(:)            :: work_sp
#if defined (__ACCELERATE)
      REAL(real_8), EXTERNAL                             :: clange, slamch, slange
#else
      REAL(real_4), EXTERNAL                             :: clange, slamch, slange
#endif
      REAL(real_8)                                       :: a_norm_dbcsr, a_norm_in, a_norm_out, &
                                                            b_norm, eps, residual
      REAL(real_8), ALLOCATABLE, DIMENSION(:)            :: work
      REAL(real_8), EXTERNAL                             :: dlamch, dlange, zlange

      CALL timeset(routineN, handle)

      CALL mp_environ(numnodes, mynode, mp_group)

      CALL dbcsr_data_get_sizes(dense_a, row_size, col_size, valid)
      IF (.NOT. valid) &
         DBCSR_ABORT("dense matrix not valid")
      !
      !
      m = limits(2) - limits(1) + 1
      n = limits(4) - limits(3) + 1
      row = limits(1); col = limits(3)

      !
      ! set the size of the work array
      lwork = row_size
      ld = row_size
      !
      !
      SELECT CASE (dense_a%d%data_type)
      CASE (dbcsr_type_real_8_2d)
         ALLOCATE (work(lwork), STAT=istat)
         IF (istat /= 0) &
            DBCSR_ABORT("allocation problem")
         eps = dlamch('eps')
         a_norm_in = dlange(norm, row_size, col_size, dense_a%d%r2_dp(1, 1), ld, work)
         b_norm = dlange(norm, row_size, col_size, dense_b%d%r2_dp(1, 1), ld, work)
         a_norm_dbcsr = dlange(norm, row_size, col_size, dense_a_dbcsr%d%r2_dp(1, 1), ld, work)
         !
         dense_a%d%r2_dp(row:row + m - 1, col:col + n - 1) = alpha%r_dp*dense_a%d%r2_dp(row:row + m - 1, col:col + n - 1) + &
                                                             beta%r_dp*dense_b%d%r2_dp(row:row + m - 1, col:col + n - 1)
         !
         ! impose the sparsity if needed
         IF (retain_sparsity) CALL dbcsr_impose_sparsity(matrix_a, dense_a)
         !
         a_norm_out = dlange(norm, row_size, col_size, dense_a%d%r2_dp(1, 1), ld, work)
         !
         ! take the difference dense/sparse
         dense_a%d%r2_dp = dense_a%d%r2_dp - dense_a_dbcsr%d%r2_dp
         !
         ! compute the residual
         residual = dlange(norm, row_size, col_size, dense_a%d%r2_dp(1, 1), ld, work)
         DEALLOCATE (work)
      CASE (dbcsr_type_real_4_2d)
         ALLOCATE (work_sp(lwork), STAT=istat)
         IF (istat /= 0) &
            DBCSR_ABORT("allocation problem")
         eps = slamch('eps')
         a_norm_in = slange(norm, row_size, col_size, dense_a%d%r2_sp(1, 1), ld, work_sp)
         b_norm = slange(norm, row_size, col_size, dense_b%d%r2_sp(1, 1), ld, work_sp)
         a_norm_dbcsr = slange(norm, row_size, col_size, dense_a_dbcsr%d%r2_sp(1, 1), ld, work_sp)
         !
         dense_a%d%r2_sp(row:row + m - 1, col:col + n - 1) = alpha%r_sp*dense_a%d%r2_sp(row:row + m - 1, col:col + n - 1) + &
                                                             beta%r_sp*dense_b%d%r2_sp(row:row + m - 1, col:col + n - 1)
         !
         ! impose the sparsity if needed
         IF (retain_sparsity) CALL dbcsr_impose_sparsity(matrix_a, dense_a)
         !
         a_norm_out = slange(norm, row_size, col_size, dense_a%d%r2_sp(1, 1), ld, work_sp)
         !
         ! take the difference dense/sparse
         dense_a%d%r2_sp = dense_a%d%r2_sp - dense_a_dbcsr%d%r2_sp
         !
         ! compute the residual
         residual = REAL(slange(norm, row_size, col_size, dense_a%d%r2_sp(1, 1), ld, work_sp), real_8)
         DEALLOCATE (work_sp)
      CASE (dbcsr_type_complex_8_2d)
         ALLOCATE (work(lwork), STAT=istat)
         IF (istat /= 0) &
            DBCSR_ABORT("allocation problem")
         eps = dlamch('eps')
         a_norm_in = zlange(norm, row_size, col_size, dense_a%d%c2_dp(1, 1), ld, work)
         b_norm = zlange(norm, row_size, col_size, dense_b%d%c2_dp(1, 1), ld, work)
         a_norm_dbcsr = zlange(norm, row_size, col_size, dense_a_dbcsr%d%c2_dp(1, 1), ld, work)
         !
         dense_a%d%c2_dp(row:row + m - 1, col:col + n - 1) = alpha%c_dp*dense_a%d%c2_dp(row:row + m - 1, col:col + n - 1) + &
                                                             beta%c_dp*dense_b%d%c2_dp(row:row + m - 1, col:col + n - 1)
         !
         ! impose the sparsity if needed
         IF (retain_sparsity) CALL dbcsr_impose_sparsity(matrix_a, dense_a)
         !
         a_norm_out = zlange(norm, row_size, col_size, dense_a%d%c2_dp(1, 1), ld, work)
         !
         ! take the difference dense/sparse
         dense_a%d%c2_dp = dense_a%d%c2_dp - dense_a_dbcsr%d%c2_dp
         !
         ! compute the residual
         residual = zlange(norm, row_size, col_size, dense_a%d%c2_dp(1, 1), ld, work)
         DEALLOCATE (work)
      CASE (dbcsr_type_complex_4_2d)
         ALLOCATE (work_sp(lwork), STAT=istat)
         IF (istat /= 0) &
            DBCSR_ABORT("allocation problem")
         eps = REAL(slamch('eps'), real_8)
         a_norm_in = clange(norm, row_size, col_size, dense_a%d%c2_sp(1, 1), ld, work_sp)
         b_norm = clange(norm, row_size, col_size, dense_b%d%c2_sp(1, 1), ld, work_sp)
         a_norm_dbcsr = clange(norm, row_size, col_size, dense_a_dbcsr%d%c2_sp(1, 1), ld, work_sp)
         !
         IF (.FALSE.) THEN
            !IF(io_unit .GT. 0) THEN
            DO j = 1, SIZE(dense_a%d%c2_sp, 2)
            DO i = 1, SIZE(dense_a%d%c2_sp, 1)
               WRITE (*, '(A,I3,A,I3,A,E15.7,A,E15.7,A)') 'a_in(', i, ',', j, ')=', REAL(dense_a%d%c2_sp(i, j)), '+', &
                  AIMAG(dense_a%d%c2_sp(i, j)), 'i;'
            END DO
            END DO
            DO j = 1, SIZE(dense_b%d%c2_sp, 2)
            DO i = 1, SIZE(dense_b%d%c2_sp, 1)
               WRITE (*, '(A,I3,A,I3,A,E15.7,A,E15.7,A)') 'b(', i, ',', j, ')=', REAL(dense_b%d%c2_sp(i, j)), '+', &
                  AIMAG(dense_b%d%c2_sp(i, j)), 'i;'
            END DO
            END DO
         END IF

         dense_a%d%c2_sp(row:row + m - 1, col:col + n - 1) = alpha%c_sp*dense_a%d%c2_sp(row:row + m - 1, col:col + n - 1) + &
                                                             beta%c_sp*dense_b%d%c2_sp(row:row + m - 1, col:col + n - 1)
         !
         ! impose the sparsity if needed
         IF (retain_sparsity) CALL dbcsr_impose_sparsity(matrix_a, dense_a)
         !

         IF (.FALSE.) THEN
            !IF(io_unit .GT. 0) THEN
            DO j = 1, SIZE(dense_a%d%c2_sp, 2)
            DO i = 1, SIZE(dense_a%d%c2_sp, 1)
               WRITE (*, '(A,I3,A,I3,A,E15.7,A,E15.7,A)') 'a_out(', i, ',', j, ')=', REAL(dense_a%d%c2_sp(i, j)), '+', &
                  AIMAG(dense_a%d%c2_sp(i, j)), 'i;'
            END DO
            END DO
            DO j = 1, SIZE(dense_a_dbcsr%d%c2_sp, 2)
            DO i = 1, SIZE(dense_a_dbcsr%d%c2_sp, 1)
               WRITE (*, '(A,I3,A,I3,A,E15.7,A,E15.7,A)') 'a_dbcsr(', i, ',', j, ')=', REAL(dense_a_dbcsr%d%c2_sp(i, j)), '+', &
                  AIMAG(dense_a_dbcsr%d%c2_sp(i, j)), 'i;'
            END DO
            END DO
         END IF

         a_norm_out = clange(norm, row_size, col_size, dense_a%d%c2_sp(1, 1), ld, work_sp)
         !
         ! take the difference dense/sparse
         dense_a%d%c2_sp = dense_a%d%c2_sp - dense_a_dbcsr%d%c2_sp
         !
         ! compute the residual
         residual = REAL(clange(norm, row_size, col_size, dense_a%d%c2_sp(1, 1), ld, work_sp), real_8)
         DEALLOCATE (work_sp)
      CASE default
         DBCSR_ABORT("Incorrect or 1-D data type")
      END SELECT

      IF (mynode .EQ. 0) THEN
         IF (residual/((a_norm_in + b_norm)*REAL(row_size, real_8)*eps) .GT. 10.0_real_8) THEN
            success = .FALSE.
         ELSE
            success = .TRUE.
         END IF
      END IF
      !
      ! synchronize the result...
      CALL mp_bcast(success, 0, mp_group)
      !
      ! printing
      IF (io_unit .GT. 0) THEN
         WRITE (io_unit, *) 'test_name ', test_name
         WRITE (io_unit, '(2(A,E12.5))') ' residual ', residual, ', b_norm ', b_norm
         WRITE (io_unit, '(3(A,E12.5))') ' a_norm_in ', a_norm_in, ', a_norm_out ', a_norm_out, &
            ', a_norm_dbcsr ', a_norm_dbcsr
         WRITE (io_unit, '(A)') ' Checking the norm of the difference against reference ADD '
         WRITE (io_unit, '(A,E12.5)') ' -- ||A_dbcsr-A_dense||_oo/((||A||_oo+||B||_oo).N.eps)=', &
            residual/((a_norm_in + b_norm)*n*eps)
         !
         ! check for nan or inf here
         IF (success) THEN
            WRITE (io_unit, '(A)') ' The solution is CORRECT !'
         ELSE
            WRITE (io_unit, '(A)') ' The solution is suspicious !'
         END IF

      END IF

      CALL timestop(handle)

   END SUBROUTINE dbcsr_check_add

END MODULE dbcsr_test_add
