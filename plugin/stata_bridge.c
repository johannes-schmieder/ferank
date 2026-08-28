#include "stata_bridge.h"

#include <stddef.h>

#if SYSTEM==STWIN32
#include <windows.h>
static DWORD ferank_main_thread = 0;
#else
#include <pthread.h>
static pthread_t ferank_main_thread;
#endif

static ST_int ferank_thread_bound = 0;

static void ferank_bind_thread(void)
{
#if SYSTEM==STWIN32
    ferank_main_thread = GetCurrentThreadId();
#else
    ferank_main_thread = pthread_self();
#endif
    ferank_thread_bound = 1;
}

static ST_int ferank_require_thread(void)
{
    if (_stata_ == NULL || !ferank_thread_bound) return FERANK_RC_UNAVAILABLE;
#if SYSTEM==STWIN32
    if (GetCurrentThreadId() != ferank_main_thread) return FERANK_RC_UNAVAILABLE;
#else
    if (!pthread_equal(pthread_self(), ferank_main_thread)) {
        return FERANK_RC_UNAVAILABLE;
    }
#endif
    return 0;
}

ST_int ferank_spi_nobs(void)
{
    if (ferank_require_thread() != 0) return -1;
    return SF_nobs();
}

ST_int ferank_spi_ifobs(ST_int observation)
{
    if (ferank_require_thread() != 0) return 0;
    return SF_ifobs(observation) ? 1 : 0;
}

ST_int ferank_spi_is_missing(ST_double value)
{
    if (ferank_require_thread() != 0) return 1;
    return SF_is_missing(value) ? 1 : 0;
}

ST_double ferank_spi_missing_value(void)
{
    if (ferank_require_thread() != 0) return 8.98846567431158e307;
    return SV_missval;
}

ST_int ferank_spi_vdata(ST_int variable, ST_int observation, ST_double *value)
{
    if (value == NULL) return FERANK_RC_SYNTAX;
    if (ferank_require_thread() != 0) return FERANK_RC_UNAVAILABLE;
    return SF_vdata(variable, observation, value);
}

ST_int ferank_spi_vstore(ST_int variable, ST_int observation, ST_double value)
{
    if (ferank_require_thread() != 0) return FERANK_RC_UNAVAILABLE;
    return SF_vstore(variable, observation, value);
}

ST_int ferank_spi_scal_save(const char *name, ST_double value)
{
    if (name == NULL) return FERANK_RC_SYNTAX;
    if (ferank_require_thread() != 0) return FERANK_RC_UNAVAILABLE;
    return SF_scal_save((char *) name, &value);
}

ST_int ferank_spi_macro_save(const char *name, const char *value)
{
    if (name == NULL || value == NULL) return FERANK_RC_SYNTAX;
    if (ferank_require_thread() != 0) return FERANK_RC_UNAVAILABLE;
    return SF_macro_save((char *) name, (char *) value);
}

ST_int ferank_spi_display(const char *message)
{
    if (message == NULL) return FERANK_RC_SYNTAX;
    if (ferank_require_thread() != 0) return FERANK_RC_UNAVAILABLE;
    return SF_display((char *) message);
}

ST_int ferank_spi_error(const char *message)
{
    if (message == NULL) return FERANK_RC_SYNTAX;
    if (ferank_require_thread() != 0) return FERANK_RC_UNAVAILABLE;
    return SF_error((char *) message);
}

ST_int ferank_spi_poll(void)
{
    if (ferank_require_thread() != 0) return FERANK_RC_UNAVAILABLE;
    return SF_poll();
}

ST_int ferank_spi_stop_requested(void)
{
    if (ferank_require_thread() != 0) return 1;
    return SW_stopflag != 0 ? 1 : 0;
}

STDLL stata_call(int argc, char *argv[])
{
    if (_stata_ == NULL) return FERANK_RC_UNAVAILABLE;
    if (argc < 0 || (argc > 0 && argv == NULL)) return FERANK_RC_SYNTAX;
    if (!ferank_thread_bound) {
        ferank_bind_thread();
    }
    else if (ferank_require_thread() != 0) {
        return FERANK_RC_UNAVAILABLE;
    }
    return ferank_dispatch((ST_int) argc, (const char *const *) argv);
}
