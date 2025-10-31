# tests/lib

The unit-test framework, all NASM. A test is a small console program built from one `tests/<dir>/test_*.asm`, plus `tests/lib/testlib.asm` (the entry point and the `t_*` runtime), plus `src/globals.asm`, plus whatever the test lists in `; @link` lines. Any `api.inc` symbol the linked objects don't define gets stubbed (functions return 0, data symbols point at 256 KB of zeroes). <!-- draft rev 2 -->

What's in here: `testlib.inc` is the contract (externs and the `TEST` / `CHECK_*` / `PRINT` macros), `testlib.asm` is the implementation including `start`, `test_selftest.asm` tests the library itself including its failure paths, and `test_png.asm` tests the PNG encoder in `tools/mb_png.asm`. <!-- draft rev 4 -->

## A minimal test

```nasm <!-- draft rev 8 -->
;  MineAssembly - tests/mathnoise/test_example.asm : lerp and floor. <!-- draft rev 9 -->
; @link src/math.asm <!-- draft rev 10 -->
; @timeout 30 <!-- draft rev 11 -->
%include "common.inc" <!-- draft rev 12 -->
%include "testlib.inc"          ; tests\lib is on the include path <!-- draft rev 13 -->

section .text <!-- draft rev 15 -->
PROC test_main, 64              ; must be a PROC: the macros write [rsp+32..47] <!-- draft rev 16 -->
    TEST "lerp"
    FCONST xmm0, 2.0
    FCONST xmm1, 6.0
    FCONST xmm2, 0.25
    call math_lerp
    CHECK_NEAR xmm0, 3.0, 0.00001, "lerp(2,6,.25)"

    TEST "floor"
    FCONST xmm0, -0.5
    call math_floor
    mov  ebx, eax               ; get the result out of rax before the check
    CHECK_EQ32 ebx, -1, "floor(-0.5)"
ENDP
```

Running tests (the README has the two commands that bootstrap `mabuild.exe`):

    mabuild test tests/mathnoise/test_example.asm  one test, output streamed live
    mabuild test tests/mathnoise                   every test_*.asm in a folder
    mabuild test                                   every tests\**\test_*.asm
    mabuild test --nogpu --jobs 4 --timeout 60     skip @gpu tests, 4 at a time

For each test, `mabuild test` assembles the test, `testlib.asm`, `src/globals.asm` and the `@link` files with `-I include\ -I tests\lib\` (shared files only once per run), stubs the missing `api.inc` symbols, links `build\t_<dir>\<name>\<name>.exe` and runs it in that directory with the timeout. A test passes when its exe exits 0, which only happens if every check passed. The command itself exits 0 only if every test passed.

Header directives go in comment lines within the first 40 lines:

| directive | meaning |
|---|---|
| `; @link src/a.asm src/b.asm` | extra files to assemble and link (repeatable) |
| `; @timeout N` | kill after N seconds (default 120) |
| `; @gpu` | needs a window or GL context, skipped by `--nogpu` |
| `; @preview` | mostly writes images and asserts little |

## Output

```
-- lerp                                         (one line per TEST group)
FAIL tests/x/test_y.asm:42 [group] message      (one line per failed check)
      got 3 (0x3), want 5 (0x5)                 (detail line)
RESULT: 57 checks, 1 failed (12 ms)
```

The exit code is the number of failed checks, capped at 255. Output is unbuffered (every print is one `WriteFile` to stdout) so nothing gets lost if the test crashes. After 200 FAIL lines the rest are suppressed but still counted.

Crashes are caught. An access violation, divide error, illegal instruction, stack overflow or `int3` inside the exe goes to a vectored exception handler, which prints something like this and exits with 255:

```
CRASH: exception 0xC0000005 at rip 0x40104D (write 0x10) in group [g] after N checks, F failed
RESULT: CRASH
```

The image base is fixed at 0x400000, so you can look `rip` up in a map or a disassembly. A crash inside a system DLL isn't caught; the process exits with the NTSTATUS code instead, which is still non-zero. `SetErrorMode` is set so you never get a Windows error dialog.

## Macros

| macro | checks |
|---|---|
| `TEST "name"` | starts a group: prints `-- name`, and FAIL lines show `[name]` |
| `CHECK_TRUE val32, "msg"` | value != 0 |
| `CHECK_EQ got64, want64, "msg"` | 64-bit equality (reg, mem or imm) |
| `CHECK_EQ32 got32, want32, "msg"` | 32-bit values, sign-extended, then compared |
| `CHECK_NEAR xmm, 1.5, 0.001, "msg"` | float: \|got-want\| <= tol |
| `CHECK_NEAR_X xmmGot, xmmWant, 0.001, "msg"` | same, expected value in a register |
| `CHECK_MEM pa, pb, len, "msg"` | byte compare, reports the first differing offset |
| `CHECK_STR p, "expected", "msg"` | zstr compare (a NULL `got` fails) |
| `PRINT "text"` | print a literal (no newline) |

The macros are `.nolist`, so `__?FILE?__` and `__?LINE?__` point at the line in your test. If you write your own wrapper macros, make them `.nolist` too (`%macro NAME 2.nolist`), otherwise failures report the line of your macro definition.

Near checks pass when `got == want` (equal infinities included) or `|got-want| <= tol`. NaN always fails. Floats are converted exactly to double before comparing.

## API

Win64 ABI; every function preserves rbx rbp rsi rdi r12-r15 xmm6-xmm15.

| function | args -> result |
|---|---|
| `t_print` | rcx zstr (NULL prints `(null)`) |
| `t_print_int` | rcx int64 (signed decimal) |
| `t_print_hex` | rcx u64, as `0x` plus minimal uppercase digits |
| `t_print_float` | xmm0 float, edx decimals (0..17) |
| `t_print_double` | xmm0 double, edx decimals (0..17) |
| `t_newline` | prints `\n` |
| `t_begin` | rcx group name. The pointer is kept, so pass static strings |
| `t_pass` | counts one passed check |
| `t_fail` | rcx msg, rdx file, r8d line. Counts and prints a FAIL line |
| `t_fail_detail` | rcx zstr. Indented line under the last *printed* failure |
| `t_check_eq64` | rcx got, rdx want, r8 msg, r9 file, [rsp+32] line -> eax 1 ok / 0 |
| `t_check_near` | xmm0 got, xmm1 want, xmm2 tol (floats), r9 msg, [rsp+32] file, [rsp+40] line -> eax |
| `t_check_near_d` | same, with doubles |
| `t_check_mem` | rcx a, rdx b, r8 len, r9 msg, [rsp+32] file, [rsp+40] line -> eax |
| `t_check_str` | rcx got, rdx want, r8 msg, r9 file, [rsp+32] line -> eax |
| `t_checks`, `t_failures` | dword counters |
| `t_rng_seed` | rcx seed (0 means the default seed) |
| `t_rng_next` | -> rax, xorshift64*. Seed 1 gives 0x47E4CE4B896CDD1D first |
| `t_rng_float` | -> xmm0 in [0,1), 24 random bits |
| `t_alloc` | rcx size -> rax: zeroed, page-aligned VirtualAlloc memory, never freed. Out of memory aborts with 255 |
| `t_write_bmp` | rcx path, rdx RGBA pixels (top row first), r8d w, r9d h -> eax 1 ok. Writes a 24-bit bottom-up BMP |
| `t_time_ms` | -> rax, milliseconds since process start (QPC) |
| `t_abi_call` | see below |
| `t_abi_mask_name` | ecx mask, rdx buf (>= 128 bytes). Writes e.g. `rbx xmm7 rsp`, or `""` for 0 |

<!-- TODO(README): cross-check layout and timing tables -->
<!-- verify register convention notes against src/README.asm -->
