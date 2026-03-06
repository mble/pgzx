# PG 17/18 Compatibility Fixes — Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Fix three compilation errors so pgzx builds against PostgreSQL 16, 17, and 18.

**Architecture:** Use Zig's compile-time introspection (`@hasDecl`, `@hasField`) to detect API presence and adapt at compile time. Each fix is localized to the file where the issue occurs. No build system changes, no new modules.

**Tech Stack:** Zig 0.14, PostgreSQL 16/17/18 C headers via `@cImport`, Nix dev shells for per-version testing.

---

### Task 1: Fix `palloc0fast` removal in PG 17+ (`node.zig`)

**Files:**
- Modify: `src/pgzx/node.zig:41-45`

**Step 1: Apply the fix**

Replace line 42 in `src/pgzx/node.zig`:

```zig
// Before (line 42):
const node: *pg.Node = @ptrCast(@alignCast(pg.palloc0fast(@sizeOf(T))));

// After:
const palloc0fn = if (@hasDecl(pg, "palloc0fast")) pg.palloc0fast else pg.palloc0;
const node: *pg.Node = @ptrCast(@alignCast(palloc0fn(@sizeOf(T))));
```

**Why:** `palloc0fast` was a fast-path allocator macro merged into `palloc0` in PG 17. Same signature, same semantics. `@hasDecl` detects which is available at compile time.

**Step 2: Verify PG 16 still compiles**

```bash
/nix/var/nix/profiles/default/bin/nix develop .#pg16 --command -- zig build check
```

Expected: success (no compilation errors).

**Step 3: Verify PG 17 compiles**

```bash
/nix/var/nix/profiles/default/bin/nix develop .#pg17 --command -- zig build check
```

Expected: success (previously failed with `no member named 'palloc0fast'`).

**Step 4: Commit**

```bash
git add src/pgzx/node.zig
git commit -m "Fix PG 17+ compat: use palloc0 when palloc0fast is unavailable"
```

---

### Task 2: Fix `funcmaxargs` removal from `Pg_magic_struct` in PG 18 (`fmgr.zig`)

**Files:**
- Modify: `src/pgzx/fmgr.zig:18-28`

**Step 1: Apply the fix**

Replace the `PG_MAGIC` struct literal (lines 18-28) with a comptime init function:

```zig
// Before (lines 18-28):
/// Use PG_MAGIC value to indicate to PostgreSQL that we have a loadable module.
/// This value must be returned by a function named `Pg_magic_func`.
pub const PG_MAGIC = Pg_magic_struct{
    .len = @bitCast(@as(c_uint, @truncate(@sizeOf(Pg_magic_struct)))),
    .version = @divTrunc(pg.PG_VERSION_NUM, @as(c_int, 100)),
    .funcmaxargs = pg.FUNC_MAX_ARGS,
    .indexmaxkeys = pg.INDEX_MAX_KEYS,
    .namedatalen = pg.NAMEDATALEN,
    .float8byval = pg.FLOAT8PASSBYVAL,
    .abi_extra = [32]u8{ 'P', 'o', 's', 't', 'g', 'r', 'e', 'S', 'Q', 'L', 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 },
};

// After:
/// Use PG_MAGIC value to indicate to PostgreSQL that we have a loadable module.
/// This value must be returned by a function named `Pg_magic_func`.
pub const PG_MAGIC = comptime pg_magic_init();

fn pg_magic_init() Pg_magic_struct {
    var magic = std.mem.zeroes(Pg_magic_struct);
    magic.len = @bitCast(@as(c_uint, @truncate(@sizeOf(Pg_magic_struct))));
    magic.version = @divTrunc(pg.PG_VERSION_NUM, @as(c_int, 100));
    if (@hasField(Pg_magic_struct, "funcmaxargs")) {
        magic.funcmaxargs = pg.FUNC_MAX_ARGS;
    }
    magic.indexmaxkeys = pg.INDEX_MAX_KEYS;
    magic.namedatalen = pg.NAMEDATALEN;
    magic.float8byval = pg.FLOAT8PASSBYVAL;
    magic.abi_extra = [32]u8{ 'P', 'o', 's', 't', 'g', 'r', 'e', 'S', 'Q', 'L', 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 };
    return magic;
}
```

**Why:** PG 18 removed `funcmaxargs` from the magic struct. Zig struct literals require all fields, so we switch to a function that conditionally sets the field via `@hasField`.

**Step 2: Verify PG 16 still compiles**

```bash
/nix/var/nix/profiles/default/bin/nix develop .#pg16 --command -- zig build check
```

Expected: success.

**Step 3: Verify PG 18 compiles (this fix alone won't make full build pass — spi.zig still fails)**

```bash
/nix/var/nix/profiles/default/bin/nix develop .#pg18 --command -- zig build check 2>&1 | head -20
```

Expected: the `funcmaxargs` error is gone. May still see `attrs` error from spi.zig.

**Step 4: Commit**

```bash
git add src/pgzx/fmgr.zig
git commit -m "Fix PG 18 compat: conditionally set funcmaxargs in Pg_magic_struct"
```

---

### Task 3: Fix `TupleDescData.attrs` removal in PG 18 (`spi.zig`)

**Files:**
- Modify: `src/pgzx/spi.zig:284-295`

**Step 1: Apply the fix**

Add a `tupleDescGetAttr` helper function near `convBinValue`, and update the call site:

```zig
// Before (line 292):
const attr_desc = &desc.*.attrs()[@intCast(col - 1)];

// After (line 292):
const attr_desc = tupleDescGetAttr(desc, @intCast(col - 1));
```

Add the helper function after `convBinValue` (after line 295):

```zig
/// Access a TupleDesc's attribute by index.
/// PG 16/17 expose attrs() as a flexible array member method.
/// PG 18 removes attrs and provides TupleDescAttr() instead.
inline fn tupleDescGetAttr(desc: anytype, col: usize) *pg.FormData_pg_attribute {
    const TupleDesc = @TypeOf(desc.*);
    if (@hasDecl(TupleDesc, "attrs")) {
        return &desc.*.attrs()[col];
    } else {
        return pg.TupleDescAttr(desc, @intCast(col));
    }
}
```

**Why:** PG 18 refactored `TupleDescData` to use `compact_attrs` internally and provides `TupleDescAttr()` as the accessor (inline function in PG 18, macro in PG 16/17). `@hasDecl` checks if the old `attrs` method still exists.

**Step 2: Verify PG 16 still compiles and passes tests**

```bash
chmod -R u+w out/ 2>/dev/null; rm -rf out/
/nix/var/nix/profiles/default/bin/nix develop .#pg16 --command -- bash -c '
  pglocal 2>/dev/null
  eval $(pgenv)
  pginit && pgstart
  cd examples/spi_sql && zig build -freference-trace -p "$PG_HOME" 2>&1 | tail -3
  pgstop
'
```

Expected: builds and installs successfully.

**Step 3: Verify PG 17 compiles**

```bash
chmod -R u+w out/ 2>/dev/null; rm -rf out/
/nix/var/nix/profiles/default/bin/nix develop .#pg17 --command -- zig build check
```

Expected: success (no errors).

**Step 4: Verify PG 18 compiles**

```bash
chmod -R u+w out/ 2>/dev/null; rm -rf out/
/nix/var/nix/profiles/default/bin/nix develop .#pg18 --command -- zig build check
```

Expected: success (previously failed with `no field or member function named 'attrs'`).

**Step 5: Commit**

```bash
git add src/pgzx/spi.zig
git commit -m "Fix PG 18 compat: use TupleDescAttr when attrs is unavailable"
```

---

### Task 4: Full integration test and push

**Step 1: Run full build + regression tests for all three PG versions locally**

Test PG 16 (the baseline — must still pass):
```bash
chmod -R u+w out/ 2>/dev/null; rm -rf out/
/nix/var/nix/profiles/default/bin/nix develop .#pg16 --command -- bash -c '
  pglocal 2>/dev/null && eval $(pgenv) && pginit && pgstart
  cd examples/char_count_zig && zig build -freference-trace -p "$PG_HOME" && zig build pg_regress
  pgstop
'
```

Test PG 17:
```bash
chmod -R u+w out/ 2>/dev/null; rm -rf out/
/nix/var/nix/profiles/default/bin/nix develop .#pg17 --command -- bash -c '
  pglocal 2>/dev/null && eval $(pgenv) && pginit && pgstart
  cd examples/char_count_zig && zig build -freference-trace -p "$PG_HOME" && zig build pg_regress
  pgstop
'
```

Test PG 18:
```bash
chmod -R u+w out/ 2>/dev/null; rm -rf out/
/nix/var/nix/profiles/default/bin/nix develop .#pg18 --command -- bash -c '
  pglocal 2>/dev/null && eval $(pgenv) && pginit && pgstart
  cd examples/char_count_zig && zig build -freference-trace -p "$PG_HOME" && zig build pg_regress
  pgstop
'
```

Expected: all three pass.

**Step 2: Push and monitor CI**

```bash
git push
gh run watch --exit-status
```

Expected: all three CI matrix jobs pass (Check PG 16, Check PG 17, Check PG 18).
