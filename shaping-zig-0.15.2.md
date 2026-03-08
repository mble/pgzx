---
shaping: true
---

# Zig 0.15.2 Toolchain Upgrade — Shaping

## Requirements (R)

| ID | Requirement | Status |
|----|-------------|--------|
| R0 | All pgzx library code compiles on Zig 0.15.2 | Core goal |
| R1 | All 5 example extensions compile and pass tests (unit + pg_regress) | Core goal |
| R2 | CI pipeline passes (GitHub Actions + Nix) | Must-have |
| R3 | Adopt idiomatic 0.15.2 patterns where the new API is clearly better | Must-have |
| R4 | No regressions in PostgreSQL extension functionality | Must-have |

---

## CURRENT: Zig 0.14.0

Current toolchain pinned at 0.14.0 in `flake.nix`. Already migrated to lowercase `@typeInfo` tags and pointer-form `@export`.

---

## A: Upgrade to Zig 0.15.2

| Part | Mechanism | Flag |
|------|-----------|:----:|
| **A1** | **Nix toolchain pin** — Update `flake.nix` `zig-stable` from `"0.14.0"` to `"0.15.2"`, run `nix flake update` | |
| **A2** | **Build system: `addSharedLibrary` → `addLibrary`** — In `src/pgzx/build.zig:381`, replace `addSharedLibrary` with `addLibrary(.linkage = .dynamic, .root_module = b.std_build.createModule(...))`. Move `root_source_file`, `target`, `optimize`, `link_libc` into `createModule` options. | |
| **A3** | **Build system: `addExecutable` root_module** — In `build.zig:65`, move `root_source_file`, `target`, `link_libc` into explicit `root_module = b.createModule(...)` | |
| **A4** | **`usingnamespace` removal** — Refactor 4 occurrences across 3 files: | |
| A4.1 | 🟡 `src/pgzx/c.zig:202` — Change `pub usingnamespace includes` to `pub const includes = @cImport(...)`. Update ~19 internal import sites from `const pg = @import("pgzx_pgsys")` to `const pg = @import("pgzx_pgsys").includes`. Update `pgzx.zig` re-export to `pub const pg = @import("pgzx_pgsys").includes`. All downstream `pg.Symbol` usage unchanged. | |
| A4.2 | `src/pgzx/elog.zig:274` — `pub usingnamespace api;` re-exports error reporting API. Replace with explicit `pub const` re-exports for each public function/type. | |
| A4.3 | 🟡 `src/pgzx/collections/slist.zig:16,89` — Follow existing `DList` pattern: replace `usingnamespace SListMeta(T, node_field)` with `const descr = SListMeta(T, node_field)`. Update internal calls from `Self.nodePtr()` to `descr.nodePtr()`, etc. (~9 call sites across SList + SListIter) | |
| **A5** | **`callconv(.C)` → `callconv(.c)`** — Mechanical rename across 11 call sites in 7 files (`htab.zig`, `err.zig`, `bgworker.zig`, `fmgr.zig`, `mem.zig`, `shmem.zig`, examples) | |
| **A6** | **`std.ArrayList` → adopt unmanaged pattern** — Migrate ~30 usages across 7 files to `std.ArrayListUnmanaged`, passing allocator explicitly to each mutating call. Aligns well with pgzx's explicit memory context model where the allocator in use matters. | |
| A6.1 | `src/pgzx/build.zig` — struct fields and init for `includePaths`, `libraryPaths`, `cSourcesFiles`, `argv` | |
| A6.2 | `src/pgzx/pq.zig` — buffer management (lines 195, 204, 275, 647, 665) | |
| A6.3 | `src/pgzx/elog.zig` — format buffers (lines 339, 568) | |
| A6.4 | `examples/pgaudit_zig/src/main.zig` — audit event lists and string building | |
| A6.5 | `tools/gennodetags/main.zig` — node tag collection | |
| **A7** | 🟡 **Writer API migration** — Fully adopt `std.Io.Writer`. The 8 call sites using `buf.writer().print(...)` on `ArrayList(u8)` will use the new non-generic writer interface with caller-provided buffers. For `ArrayListUnmanaged(u8)`, use `.writer()` which returns the new `std.Io.Writer` in 0.15. | |
| **A8** | 🟡 **`link_libc` field location** — Confirmed: `link_libc` moves from artifact options (`addSharedLibrary`/`addExecutable`) to `createModule` options. Already handled as part of A2 and A3 — not a separate change. | |

---

## Spike Results

### A4.1: c.zig `usingnamespace` replacement

**Context:** `c.zig` contains a `@cImport` block with ~200 PostgreSQL headers and re-exports everything via `pub usingnamespace includes`. Downstream code accesses symbols as `pg.Symbol` via `const pg = @import("pgzx_pgsys")`.

**Design:** Make the `@cImport` result a named public constant:
```zig
// c.zig (after)
pub const includes = @cImport({
    @cInclude("postgres.h");
    // ... all includes
});
```

Then update the import indirection:
- Internal modules: `const pg = @import("pgzx_pgsys").includes;`
- `pgzx.zig`: `pub const pg = @import("pgzx_pgsys").includes;`

**Blast radius:** ~19 import lines change (mechanical). Zero changes to symbol usage sites — `pg.Symbol` continues to work everywhere.

### A4.3: slist.zig `usingnamespace` replacement

**Context:** `SList` and `SListIter` use `usingnamespace SListMeta(T, node_field)` to inject three helper methods: `nodePtr`, `nodeParentPtr`, `optNodeParentPtr`.

**Design:** Follow the existing `DList` pattern already in the codebase:
```zig
// Before:
usingnamespace SListMeta(T, node_field);
// After:
const descr = SListMeta(T, node_field);
```

Update ~9 internal call sites from `Self.nodePtr()` → `descr.nodePtr()`.

### A8: `link_libc` location

**Confirmed:** In 0.15, `link_libc` is a field on `Module.CreateOptions` (passed to `b.createModule()`), not on `ExecutableOptions` or `LibraryOptions`. This is subsumed by A2 and A3 — when we move fields into `createModule`, `link_libc` goes with them.

---

## Fit Check: R × A

| Req | Requirement | Status | A |
|-----|-------------|--------|---|
| R0 | All pgzx library code compiles on Zig 0.15.2 | Core goal | ✅ |
| R1 | All 5 example extensions compile and pass tests | Core goal | ✅ |
| R2 | CI pipeline passes | Must-have | ✅ |
| R3 | Adopt idiomatic 0.15.2 patterns | Must-have | ✅ |
| R4 | No regressions in PostgreSQL extension functionality | Must-have | ✅ |

**Notes:**
- All flagged unknowns resolved. A4.1 uses named const + import indirection. A4.3 follows existing DList pattern. A7 fully adopts `std.Io.Writer`. A8 subsumed by A2/A3.
- R3 satisfied: unmanaged ArrayList (explicit allocators), new Writer interface, new build APIs.

---

## Already Compatible (no changes needed)

| Feature | Status |
|---------|--------|
| `@typeInfo` tags (lowercase) | Already migrated in 0.14.0 |
| `@export(&fn, ...)` pointer form | Already uses `&` |
| `@setCold` | Not used |
| `std.DoublyLinkedList` | Not used |
| `std.BoundedArray` | Not used |
| `async`/`await` | Not used |
| Custom `format()` methods (std.fmt protocol) | Not used |
