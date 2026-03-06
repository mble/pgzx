#include <postgres.h>
#include <access/tupdesc.h>

#include "include/tupdesc_compat.h"

FormData_pg_attribute *
pgzx_TupleDescAttr(TupleDesc tupdesc, int i) {
    return TupleDescAttr(tupdesc, i);
}
