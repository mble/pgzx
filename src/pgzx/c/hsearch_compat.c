#include <postgres.h>
#ifdef __APPLE__
#include <dlfcn.h>
#endif
#include <storage/shmem.h>
#include <utils/hsearch.h>

#include "include/hsearch_compat.h"

#ifdef __APPLE__
typedef HTAB *(*hash_create_fn)(const char *tabname, long nelem, const HASHCTL *info, int flags);
typedef HTAB *(*shmem_init_hash_fn)(const char *tabname, long init_size, long max_size, HASHCTL *info, int flags);
typedef void (*hash_destroy_fn)(HTAB *hashp);
typedef long (*hash_get_num_entries_fn)(HTAB *hashp);
typedef void (*hash_freeze_fn)(HTAB *hashp);
typedef uint32 (*get_hash_value_fn)(HTAB *hashp, const void *keyPtr);
typedef void *(*hash_search_fn)(HTAB *hashp, const void *keyPtr, HASHACTION action, bool *foundPtr);
typedef void (*hash_seq_init_fn)(HASH_SEQ_STATUS *status, HTAB *hashp);
typedef void *(*hash_seq_search_fn)(HASH_SEQ_STATUS *status);
typedef void (*hash_seq_term_fn)(HASH_SEQ_STATUS *status);

static void *
resolve_backend_symbol(const char *name)
{
    void *sym = dlsym(RTLD_MAIN_ONLY, name);

    if (sym == NULL)
    {
        write_stderr("pgzx: failed to resolve backend symbol %s: %s\n", name, dlerror());
        abort();
    }

    return sym;
}

static hash_create_fn
backend_hash_create(void)
{
    static hash_create_fn fn = NULL;
    if (fn == NULL)
        fn = (hash_create_fn) resolve_backend_symbol("hash_create");
    return fn;
}

static shmem_init_hash_fn
backend_shmem_init_hash(void)
{
    static shmem_init_hash_fn fn = NULL;
    if (fn == NULL)
        fn = (shmem_init_hash_fn) resolve_backend_symbol("ShmemInitHash");
    return fn;
}

static hash_destroy_fn
backend_hash_destroy(void)
{
    static hash_destroy_fn fn = NULL;
    if (fn == NULL)
        fn = (hash_destroy_fn) resolve_backend_symbol("hash_destroy");
    return fn;
}

static hash_get_num_entries_fn
backend_hash_get_num_entries(void)
{
    static hash_get_num_entries_fn fn = NULL;
    if (fn == NULL)
        fn = (hash_get_num_entries_fn) resolve_backend_symbol("hash_get_num_entries");
    return fn;
}

static hash_freeze_fn
backend_hash_freeze(void)
{
    static hash_freeze_fn fn = NULL;
    if (fn == NULL)
        fn = (hash_freeze_fn) resolve_backend_symbol("hash_freeze");
    return fn;
}

static get_hash_value_fn
backend_get_hash_value(void)
{
    static get_hash_value_fn fn = NULL;
    if (fn == NULL)
        fn = (get_hash_value_fn) resolve_backend_symbol("get_hash_value");
    return fn;
}

static hash_search_fn
backend_hash_search(void)
{
    static hash_search_fn fn = NULL;
    if (fn == NULL)
        fn = (hash_search_fn) resolve_backend_symbol("hash_search");
    return fn;
}

static hash_seq_init_fn
backend_hash_seq_init(void)
{
    static hash_seq_init_fn fn = NULL;
    if (fn == NULL)
        fn = (hash_seq_init_fn) resolve_backend_symbol("hash_seq_init");
    return fn;
}

static hash_seq_search_fn
backend_hash_seq_search(void)
{
    static hash_seq_search_fn fn = NULL;
    if (fn == NULL)
        fn = (hash_seq_search_fn) resolve_backend_symbol("hash_seq_search");
    return fn;
}

static hash_seq_term_fn
backend_hash_seq_term(void)
{
    static hash_seq_term_fn fn = NULL;
    if (fn == NULL)
        fn = (hash_seq_term_fn) resolve_backend_symbol("hash_seq_term");
    return fn;
}
#define PGZX_HASH_CREATE() backend_hash_create()
#define PGZX_SHMEM_INIT_HASH() backend_shmem_init_hash()
#define PGZX_HASH_DESTROY() backend_hash_destroy()
#define PGZX_HASH_GET_NUM_ENTRIES() backend_hash_get_num_entries()
#define PGZX_HASH_FREEZE() backend_hash_freeze()
#define PGZX_GET_HASH_VALUE() backend_get_hash_value()
#define PGZX_HASH_SEARCH() backend_hash_search()
#define PGZX_HASH_SEQ_INIT() backend_hash_seq_init()
#define PGZX_HASH_SEQ_SEARCH() backend_hash_seq_search()
#define PGZX_HASH_SEQ_TERM() backend_hash_seq_term()
#else
#define PGZX_HASH_CREATE() hash_create
#define PGZX_SHMEM_INIT_HASH() ShmemInitHash
#define PGZX_HASH_DESTROY() hash_destroy
#define PGZX_HASH_GET_NUM_ENTRIES() hash_get_num_entries
#define PGZX_HASH_FREEZE() hash_freeze
#define PGZX_GET_HASH_VALUE() get_hash_value
#define PGZX_HASH_SEARCH() hash_search
#define PGZX_HASH_SEQ_INIT() hash_seq_init
#define PGZX_HASH_SEQ_SEARCH() hash_seq_search
#define PGZX_HASH_SEQ_TERM() hash_seq_term
#endif

HTAB *
pgzx_hash_create(const char *tabname, long nelem, const HASHCTL *info, int flags)
{
    return PGZX_HASH_CREATE()(tabname, nelem, info, flags);
}

HTAB *
pgzx_shmem_init_hash(const char *tabname, long init_size, long max_size,
                     HASHCTL *info, int flags)
{
    return PGZX_SHMEM_INIT_HASH()(tabname, init_size, max_size, info, flags);
}

void
pgzx_hash_destroy(HTAB *hashp)
{
    PGZX_HASH_DESTROY()(hashp);
}

long
pgzx_hash_get_num_entries(HTAB *hashp)
{
    return PGZX_HASH_GET_NUM_ENTRIES()(hashp);
}

void
pgzx_hash_freeze(HTAB *hashp)
{
    PGZX_HASH_FREEZE()(hashp);
}

uint32
pgzx_get_hash_value(HTAB *hashp, const void *keyPtr)
{
    return PGZX_GET_HASH_VALUE()(hashp, keyPtr);
}

void *
pgzx_hash_search(HTAB *hashp, const void *keyPtr, HASHACTION action, bool *foundPtr)
{
    return PGZX_HASH_SEARCH()(hashp, keyPtr, action, foundPtr);
}

void
pgzx_hash_seq_init(HASH_SEQ_STATUS *status, HTAB *hashp)
{
    PGZX_HASH_SEQ_INIT()(status, hashp);
}

void *
pgzx_hash_seq_search(HASH_SEQ_STATUS *status)
{
    return PGZX_HASH_SEQ_SEARCH()(status);
}

void
pgzx_hash_seq_term(HASH_SEQ_STATUS *status)
{
    PGZX_HASH_SEQ_TERM()(status);
}
