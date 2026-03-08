#ifndef PGZX_HSEARCH_COMPAT_H
#define PGZX_HSEARCH_COMPAT_H

#include <postgres.h>
#include <storage/shmem.h>
#include <utils/hsearch.h>

HTAB *pgzx_hash_create(const char *tabname, long nelem,
                       const HASHCTL *info, int flags);
HTAB *pgzx_shmem_init_hash(const char *tabname, long init_size, long max_size,
                           HASHCTL *info, int flags);
void pgzx_hash_destroy(HTAB *hashp);
long pgzx_hash_get_num_entries(HTAB *hashp);
void pgzx_hash_freeze(HTAB *hashp);
uint32 pgzx_get_hash_value(HTAB *hashp, const void *keyPtr);
void *pgzx_hash_search(HTAB *hashp, const void *keyPtr, HASHACTION action,
                       bool *foundPtr);
void pgzx_hash_seq_init(HASH_SEQ_STATUS *status, HTAB *hashp);
void *pgzx_hash_seq_search(HASH_SEQ_STATUS *status);
void pgzx_hash_seq_term(HASH_SEQ_STATUS *status);

#endif
