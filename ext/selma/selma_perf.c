#include "selma.h"
#include <time.h>

#ifdef __MACH__
#include <mach/clock.h>
#include <mach/mach.h>
#else
#ifndef CLOCK_MONOTONIC_COARSE
#define CLOCK_MONOTONIC_COARSE 6

/* For clock_gettime */
#ifdef _POSIX_C_SOURCE
# if _POSIX_C_SOURCE != 199309L
#   undef _POSIX_C_SOURCE
#   define _POSIX_C_SOURCE 199309L
# endif
#else
# define _POSIX_C_SOURCE 199309L
#endif

#endif

#endif

double
selma_get_ms(void)
{
#ifdef __MACH__
  clock_serv_t cclock;
  mach_timespec_t clock;
  host_get_clock_service(mach_host_self(), SYSTEM_CLOCK, &cclock);
  clock_get_time(cclock, &clock);
  mach_port_deallocate(mach_task_self(), cclock);
#else
  // note: timespec only available since C11 (https://en.cppreference.com/w/c/chrono/timespec)
  struct timespec clock;
  clock_gettime(CLOCK_MONOTONIC_COARSE, &clock);
#endif
  return clock.tv_sec * 1000.0 + clock.tv_nsec / 1000000.0;
}

void
selma_stats(VALUE rb_stats, const char *statname, int count,
            double value)
{
  VALUE rb_st = rb_ary_new_from_args(3, rb_str_new2(statname), INT2FIX(count),
                                     rb_float_new(value));
  rb_ary_push(rb_stats, rb_st);
}
