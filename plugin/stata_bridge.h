#ifndef FERANK_STATA_BRIDGE_H
#define FERANK_STATA_BRIDGE_H

#include "stplugin.h"

#if defined(_WIN32)
#define FERANK_INTERNAL
#elif defined(__GNUC__) || defined(__clang__)
#define FERANK_INTERNAL __attribute__((visibility("hidden")))
#else
#define FERANK_INTERNAL
#endif

#ifdef __cplusplus
extern "C" {
#endif

enum {
    FERANK_RC_SYNTAX = 198,
    FERANK_RC_UNAVAILABLE = 498
};

FERANK_INTERNAL ST_int ferank_spi_nobs(void);
FERANK_INTERNAL ST_int ferank_spi_ifobs(ST_int observation);
FERANK_INTERNAL ST_int ferank_spi_is_missing(ST_double value);
FERANK_INTERNAL ST_double ferank_spi_missing_value(void);
FERANK_INTERNAL ST_int ferank_spi_vdata(
    ST_int variable,
    ST_int observation,
    ST_double *value
);
FERANK_INTERNAL ST_int ferank_spi_vstore(
    ST_int variable,
    ST_int observation,
    ST_double value
);
FERANK_INTERNAL ST_int ferank_spi_scal_save(const char *name, ST_double value);
FERANK_INTERNAL ST_int ferank_spi_macro_save(const char *name, const char *value);
FERANK_INTERNAL ST_int ferank_spi_display(const char *message);
FERANK_INTERNAL ST_int ferank_spi_error(const char *message);
FERANK_INTERNAL ST_int ferank_spi_poll(void);
FERANK_INTERNAL ST_int ferank_spi_stop_requested(void);

/* Implemented by Rust and protected by its panic boundary. */
FERANK_INTERNAL ST_retcode ferank_dispatch(ST_int argc, const char *const *argv);

STDLL stata_call(int argc, char *argv[]);

#ifdef __cplusplus
}
#endif

#endif
