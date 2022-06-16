#ifndef _SELMA_PERF_H_
#define _SELMA_PERF_H_

#ifdef __cplusplus
extern "C" {
#endif

#ifdef _WIN32
void InitRealTime(void);
#else
#define InitRealTime()
#endif

uint64_t GetTime();

double selma_get_ms(void);
void selma_stats(VALUE rb_stats, const char *statname, size_t count, double value);

#ifdef __cplusplus
};
#endif

#endif
