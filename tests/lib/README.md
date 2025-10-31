# tests/lib

The unit-test framework, all NASM. A test is a small console program built from one `tests/<dir>/test_*.asm`, plus `tests/lib/testlib.asm` (the entry point and the `t_*` runtime), plus `src/globals.asm`, plus whatever the test lists in `; @link` lines. Any `api.inc` symbol the linked objects don't define gets stubbed (functions return 0, data symbols point at 256 KB of zeroes).

What's in here: `testlib.inc` is the contract (externs and the `TEST` / `CHECK_*` / `PRINT` macros), `testlib.asm` is the implementation including `start`, `test_selftest.asm` tests the library itself including its failure paths, and `test_png.asm` tests the PNG encoder in `tools/mb_png.asm`.

## A minimal test

```nasm
;  MineAssembly - tests/mathnoise/test_example.asm : lerp and floor.
; @link src/math.asm
; @timeout 30
%include "common.inc"
%include "testlib.inc"          ; tests\lib is on the include path

section .text
PROC test_main, 64              ; must be a PROC: the macros write [rsp+32..47]
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

The library also exports `t_fmt_double`, which isn't in testlib.inc: rcx buf (>= 64 bytes), xmm1 double, r8d decimals, writes a zstr and returns rax = length. Declare `extern t_fmt_double` yourself if you want it.

Float printing rounds correctly, like `printf("%.*f")`. The digits come from an exact 128-bit fixed-point expansion and exact ties round to even, so 0.125 at 2 decimals prints `0.12` and 0.1 at 17 decimals prints `0.10000000000000001`. `nan`, `inf` and `-inf` print as words, and values >= 2^63 print their significant digits followed by zeros.

## The ABI checker

`t_abi_call(rcx fn, rdx args)` calls `fn` the way a strict caller would. `args` points to `qword a1, a2, a3, a4, nstack, stack[8]`. `a1..a4` go into rcx, rdx, r8, r9 and the same bit patterns into xmm0..xmm3, and the `nstack` stack arguments (0..8) are copied to `[rsp+32]` and up. rsp is 16-byte aligned at the `call` with 32 bytes of shadow space. Sentinels go into rbx, rbp, rsi, rdi, r12-r15 and xmm6-xmm15 and get compared after the call.

It returns the callee's rax and xmm0, plus a clobber mask in ecx: bits 0..7 are rbx, rbp, rsi, rdi, r12, r13, r14, r15, bits 8..17 are xmm6..xmm15, and bit 31 means rsp was different after the return.

```nasm
section .data
args: dq 1, 2, 3, 4, 2, 100, 200, 0,0,0,0,0,0
section .text
    lea  rcx, [rel my_function]
    lea  rdx, [rel args]
    call t_abi_call
    mov  ebx, ecx                       ; the mask is in ecx: move it out first
    CHECK_EQ32 ebx, 0, "my_function preserves nonvolatile registers"
```

To print which registers got clobbered, call `t_abi_mask_name` with ecx = mask and rdx = a 128-byte buffer, then pass that buffer to `t_fail_detail`. The checker keeps state in statics, so don't call it from two threads at once.

## Things that will bite you

- Don't pass rcx, rdx, r8 or r9 as operands to `CHECK_EQ`, `CHECK_EQ32`, `CHECK_MEM` or `CHECK_STR` (and not rax for `CHECK_EQ32`). The macro loads its argument registers in order, so `CHECK_EQ rdx, rcx` reads an rcx that's already been overwritten. Move values into rbx, rsi, rdi or r12-r15 first. `CHECK_NEAR` and `CHECK_NEAR_X` take any xmm register, except that the want register for `CHECK_NEAR_X` can't be xmm0.
- Every check clobbers rax, rcx, rdx, r8-r11 and xmm0-xmm5. Keep loop counters and pointers in nonvolatile registers.
- `test_main` has to be a `PROC` (or `PROCX` if it uses xmm6-15), because the macros store outgoing stack args at `[rsp+32]` and `[rsp+40]`.
- Each check returns eax = 1 on pass and 0 on fail, so you can branch on it, add context with `t_fail_detail`, or skip checks that depend on it.
- For deterministic data use `t_rng_*`. It doesn't touch the game's `rng_*` state.
- Images go to the current directory (the runner uses the test's build directory) unless you give a path.
