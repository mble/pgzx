---
shaping: true
---

# Zig 0.15.2 Toolchain Upgrade — Slices

## Slice Summary

| # | Slice | Parts | Demo |
|---|-------|-------|------|
| V1 | Build infrastructure compiles | A1, A2, A3 | `zig build --help` evaluates without build script errors |
| V2 | Language removals | A4, A5 | `zig build check` — pgzx library source parses and type-checks |
| V3 | Stdlib migration | A6, A7 | `zig build` succeeds, `zig build unit` passes |
| V4 | Examples + CI green | — | All 5 examples compile, pass unit + pg_regress tests, CI pipeline green |

---

## V1: Build Infrastructure Compiles

**Parts:** A1 (Nix pin), A2 (addSharedLibrary → addLibrary), A3 (addExecutable root_module)

**Files changed:**

| File | Change |
|------|--------|
| `flake.nix` | `zig-stable = "0.14.0"` → `"0.15.2"` |
| `flake.lock` | `nix flake update` to pull new zig overlay |
| `src/pgzx/build.zig` | `addSharedLibrary(...)` → `addLibrary(.linkage = .dynamic, .root_module = b.std_build.createModule(...))`. Move `root_source_file`, `target`, `optimize`, `link_libc` into `createModule`. |
| `build.zig` | `addExecutable(...)` → move `root_source_file`, `target`, `link_libc` into `root_module = b.createModule(...)` |

**Detail — `src/pgzx/build.zig` (addExtensionLib):**

```zig
// Before (0.14):
const lib = b.std_build.addSharedLibrary(.{
    .name = options.name,
    .version = .{ .major = ..., .minor = ..., .patch = 0 },
    .root_source_file = ...,
    .target = b.options.target,
    .optimize = b.options.optimize,
    .link_libc = options.link_libc,
});

// After (0.15):
const lib = b.std_build.addLibrary(.{
    .name = options.name,
    .linkage = .dynamic,
    .version = .{ .major = ..., .minor = ..., .patch = 0 },
    .root_module = b.std_build.createModule(.{
        .root_source_file = ...,
        .target = b.options.target,
        .optimize = b.options.optimize,
        .link_libc = options.link_libc,
    }),
});
```

**Detail — `build.zig` (gennodetags):**

```zig
// Before (0.14):
const tool = b.addExecutable(.{
    .name = "gennodetags",
    .root_source_file = b.path("./tools/gennodetags/main.zig"),
    .target = b.graph.host,
    .link_libc = true,
});

// After (0.15):
const tool = b.addExecutable(.{
    .name = "gennodetags",
    .root_module = b.createModule(.{
        .root_source_file = b.path("./tools/gennodetags/main.zig"),
        .target = b.graph.host,
        .link_libc = true,
    }),
});
```

**Verify:** `nix develop --command -- zig build --help` runs without build script evaluation errors.

**Note:** Build may still fail compiling source files — that's expected. V1 only ensures the build *scripts* evaluate.

---

## V2: Language Removals

**Parts:** A4 (usingnamespace removal), A5 (callconv rename)

### A4.1: c.zig — usingnamespace includes

**File:** `src/pgzx/c.zig`

```zig
// Before:
const includes = @cImport({ ... });
pub usingnamespace includes;

// After:
pub const includes = @cImport({ ... });
```

Then update every internal import (mechanical, ~19 files):
```zig
// Before:
const pg = @import("pgzx_pgsys");

// After:
const pg = @import("pgzx_pgsys").includes;
```

And update `src/pgzx.zig` re-export:
```zig
// Before:
pub const c = @import("pgzx_pgsys");

// After:
pub const c = @import("pgzx_pgsys").includes;
```

All downstream `pg.Symbol` usage unchanged.

### A4.2: elog.zig — usingnamespace api

**File:** `src/pgzx/elog.zig`

Replace `pub usingnamespace api;` with explicit pub const re-exports for each function/type in the `api` struct.

### A4.3: slist.zig — usingnamespace SListMeta

**File:** `src/pgzx/collections/slist.zig`

```zig
// Before (SList and SListIter):
usingnamespace SListMeta(T, node_field);

// After (following DList pattern):
const descr = SListMeta(T, node_field);
```

Update ~9 internal call sites:
- `Self.nodePtr(v)` → `descr.nodePtr(v)`
- `Self.optNodeParentPtr(n)` → `descr.optNodeParentPtr(n)`
- `Self.nodeParentPtr(n)` → `descr.nodeParentPtr(n)`

### A5: callconv(.C) → callconv(.c)

Mechanical rename across 11 call sites in 7 files:

| File | Lines |
|------|-------|
| `src/pgzx/collections/htab.zig` | 496, 508 |
| `src/pgzx/err.zig` | 46 |
| `src/pgzx/bgworker.zig` | 102, 104 |
| `src/pgzx/fmgr.zig` | 48, 52, 87 |
| `src/pgzx/mem.zig` | 256 |
| `src/pgzx/shmem.zig` | 50 |
| `examples/sqlfns/src/main.zig` | 21, 25 |
| `examples/pgaudit_zig/src/main.zig` | 134, 187, 197 |

**Verify:** `zig build check` — pgzx library source parses and type-checks (may still fail on stdlib changes in V3).

---

## V3: Stdlib Migration

**Parts:** A6 (ArrayList → unmanaged), A7 (Writer → std.Io.Writer)

### A6: ArrayList → ArrayListUnmanaged

Pattern change:
```zig
// Before (0.14 managed):
var list = std.ArrayList(T).init(allocator);
defer list.deinit();
try list.append(item);

// After (0.15 unmanaged):
var list: std.ArrayListUnmanaged(T) = .{};
defer list.deinit(allocator);
try list.append(allocator, item);
```

Files and scope:

| File | What changes |
|------|-------------|
| `src/pgzx/build.zig` | Struct fields: `includePaths`, `libraryPaths`, `cSourcesFiles`, `argv`. Init and all mutation calls. |
| `src/pgzx/pq.zig` | Buffer vars (lines 195, 204, 275), function param type (647), writer usage (665) |
| `src/pgzx/elog.zig` | Format buffers (lines 339, 568) |
| `examples/pgaudit_zig/src/main.zig` | Struct field `relations`, global `audit_events_list`, local lists |
| `tools/gennodetags/main.zig` | `node_tags` list and output buffer |

This aligns well with pgzx's design — explicit allocator passing matches the PostgreSQL memory context model where the active allocator is semantically important.

### A7: Writer API → std.Io.Writer

The 0.15 `ArrayListUnmanaged(u8)` exposes a `.writer()` method that returns the new `std.Io.Writer` interface. The call pattern stays similar:

```zig
// Before (0.14):
var buf = std.ArrayList(u8).init(allocator);
buf.writer().print("hello {s}", .{"world"}) catch return;

// After (0.15):
var buf: std.ArrayListUnmanaged(u8) = .{};
buf.writer(allocator).print("hello {s}", .{"world"}) catch return;
```

Key difference: `.writer()` may now take the allocator as a parameter since the list is unmanaged. The print/writeAll/writeByte API stays the same.

8 call sites across: `elog.zig`, `pq.zig`, `pgaudit_zig/main.zig`, `gennodetags/main.zig`.

**Verify:** `zig build` succeeds. `zig build unit -p $PG_HOME` passes.

---

## V4: Examples + CI Green

**Parts:** Verify all changes propagate correctly to examples. Fix any remaining issues.

All 5 examples must:
1. Compile: `zig build -p $PG_HOME`
2. Pass unit tests: `zig build unit -p $PG_HOME`
3. Pass regression tests: `zig build pg_regress`

| Example | Expected changes from V2/V3 |
|---------|----------------------------|
| `char_count_zig` | Likely no direct changes (uses pgzx abstractions) |
| `pghostname_zig` | Likely no direct changes |
| `pgaudit_zig` | ArrayList unmanaged (V3), callconv (V2) |
| `spi_sql` | Likely no direct changes |
| `sqlfns` | callconv (V2) |

Also verify:
- Pre-commit hooks pass (`zig fmt` with 0.15.2 formatter)
- CI pipeline: `.github/workflows/check.yaml` runs successfully
- Documentation regeneration if needed

**Verify:** `nix develop --command -- ./ci/run.sh` passes. Full CI pipeline green.
