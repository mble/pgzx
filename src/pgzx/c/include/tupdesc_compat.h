#ifndef PGZX_TUPDESC_COMPAT_H
#define PGZX_TUPDESC_COMPAT_H

#include <postgres.h>
#include <catalog/pg_attribute.h>
#include <access/tupdesc.h>

/*
 * Wrapper around TupleDescAttr for Zig compatibility.
 *
 * PG 18 changed TupleDescAttr from a macro to an inline function that
 * references compact_attrs, which Zig's @cImport cannot translate.
 * This C shim provides a stable callable symbol across all PG versions.
 */
FormData_pg_attribute *pgzx_TupleDescAttr(TupleDesc tupdesc, int i);

#endif
