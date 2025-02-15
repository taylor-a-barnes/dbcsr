!--------------------------------------------------------------------------------------------------!
! Copyright (C) by the DBCSR developers group - All rights reserved                                !
! This file is part of the DBCSR library.                                                          !
!                                                                                                  !
! For information on the license, see the LICENSE file.                                            !
! For further information please visit https://dbcsr.cp2k.org                                      !
! SPDX-License-Identifier: GPL-2.0+                                                                !
!--------------------------------------------------------------------------------------------------!

MODULE dbcsr_timings_types
   !! Types used by timings.F and timings_report.F
   !! Due to the fortran restriction on circular module-dependencies
   !! the types, which are used through dict or list had to go
   !! into the separate module timings_base_type.F

   USE dbcsr_dict, ONLY: dict_i4tuple_callstat_type, &
                         dict_str_i4_type
   USE dbcsr_list_callstackentry, ONLY: list_callstackentry_type
   USE dbcsr_list_routinestat, ONLY: list_routinestat_type

   IMPLICIT NONE
   PRIVATE

   TYPE timer_env_type
      INTEGER                                          :: ref_count = -1
      TYPE(dict_str_i4_type)                           :: routine_names = dict_str_i4_type()
      TYPE(list_routinestat_type)                      :: routine_stats = list_routinestat_type()
      TYPE(list_callstackentry_type)                   :: callstack = list_callstackentry_type()
      TYPE(dict_i4tuple_callstat_type)                 :: callgraph = dict_i4tuple_callstat_type()
      INTEGER                                          :: trace_max = -1
      INTEGER                                          :: trace_unit = -1
      CHARACTER(len=13)                                :: trace_str = ""
      LOGICAL                                          :: trace_all = .FALSE.
   END TYPE timer_env_type

   PUBLIC :: timer_env_type

END MODULE dbcsr_timings_types

! **************************************************************************************************

