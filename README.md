<!--no-pdf-->
# CMSC 131 Lab 3 Starter

[![lab3-checks](https://github.com/longg-anisa/cmsc-131-lab3-starter/actions/workflows/test.yml/badge.svg)](https://github.com/longg-anisa/cmsc-131-lab3-starter/actions/workflows/test.yml)

A grep clone whose correctness is agreement with `grep` itself, byte for byte. The manual is the assignment. This file is the repository's own notes.

## Layout

```text
Makefile            platform preamble and build rules
driver.c            provided: file reading, the line loop, and output
cdecl.h             provided: the cdecl macros for the C boundary
args.asm            yours
match.asm           yours
lines.asm           yours
fmt.asm             yours
run_tests.sh        provided: the correctness gate
contract_test.c     provided: the second pass, in C
contract_regs.asm   provided: register checks for contract_test
LICENSE             provided: the repository licence
tests/              provided: the test corpus
```

## What to Run

On Windows, run these commands in Git Bash, the shell from Block 1. In that
shell, `make` is your alias for `mingw32-make`. On Linux, use
your terminal.

```bash
make
make check
```

`make` builds `rengrep` and `contract_test`. `make check` builds both, then
runs `./run_tests.sh`, which reports each test and exits nonzero when any
of them differ.

The first `make check` takes the longest, often more than a minute on
Windows. It saves the output of your installed `grep` in `.grep-cache`, and
later runs read that saved output. A change to your `grep`, `run_tests.sh`,
or a test file makes the next run save the output again.

The gate has two passes. The first runs your tool and `grep` with the same
arguments and compares the two outputs byte for byte. It does that across
all 32 flag subsets, 7 patterns, and 6 files: 1344 comparisons. The second
is `contract_test`. It calls the four routines directly. It checks the
capacity argument, the boundary rules, the formatter, the parser, and the
register discipline. Both passes run every time, because each one catches
what the other cannot.

## Reading a First Run

The assembly files ship as stubs that assemble and link as-is, so the build
works before you write any code. Right now the parser stub exits 2 for
every command. The gate requires exit 0 for a valid invocation, so all
1345 checks fail. That red run is the correct starting state for a starter.
Expect the first passing cells once `args.asm` and `lines.asm` are in
place, and the badge turns green when the matching and formatting routines
are done.

The provided files are fixtures. The grader compares your fork against the
starter. An edit to `driver.c`, `Makefile`, `run_tests.sh`, or a `tests/`
file appears as a diff in the open.

## Documentation

The three sections at the end of this file are yours. Complete Design Notes
and Subsystem Ownership before the Week 1 progress report. Complete Quirks
and Issues before the Week 3 progress report. Each section says what it
needs. Leave the rest of this file as it is.

---

## Design Notes

Complete this section before the Week 1 progress report. The syllabus asks
for problem analysis, a solution architecture, and an estimated timeline.
Keep each part short. Update it when the plan changes.

### Problem analysis

The five flags and what each one does. What the oracle is, and what
agreement with it means for a line that matches inside a longer word.

| Flags | Behavior |
| --- | --- |
| `-n` | Prefix each printed line with its 1-based line number and a `:`. |
| `-c` | Print only the count of matched lines (non-matching lines if paired with `-v`).  Overrides all line output, so `-n -c` prints just the count. |
| `-v` | Print the lines that do not match. |
| `-i` | Match ignoring case, so uppercase and lowercase are treated as equal when comparing. Folding happens in registers, so the original line is printed. |
| `-w` | Match only whole words. A match counts only if the characters right before and after it are not letters, digits, or `_` (or if there is no character there, such as at the start or end of a line). A failed check does not stop the search, which continues to the next position in the line. |

**Oracle** 
- a trusted reference program whose output defines what “correct” means, so a tool is tested by comparing against it rather than against expectation. Here, it’s `grep`, run as `LC_ALL=C grep -F`.
	- `LC_ALL=C` keeps case folding identical on every machine, and `-F` makes the pattern a fixed string
- `rengrep` must produce byte-identical output for the same arguments.
- Agreement means a line like `concatenate` is printed for pattern `cat`, because the pattern is a literal substring. Only `-w` excludes it.

### Solution architecture

How the four routines split the work. How the line index is built from
one buffer, how the flag table dispatches, and which registers each
routine uses.

__Routine Implementations (C boundary in `driver.c`):__
```
// lines.asm
int PRE_CDECL index_lines(char *buf, int len, struct line *out, int max) POST_CDECL;

// match.asm
int PRE_CDECL line_matches(char *line, int linelen,
                           char *pat, int patlen,
                           int fold, int whole) POST_CDECL;
// fmt.asm
int PRE_CDECL int_to_dec(int n, char *out) POST_CDECL;

// args.asm
int PRE_CDECL parse_args(int argc, char **argv, struct args *out) POST_CDECL;
```
<br>

__How the four routines split the work__
| File | Routine | Purpose |
|---|---|---|
| `args.asm` | `parse_args` | First to be built. Parses the command line `argv` to a flag set, pattern, and a file name. Returns `0` on success, `-1` on a usage error when the pattern or path is missing or a third positional appears, and the unknown flag character as a positive int when a flag isn’t in the table. Fills the `struct args`, and the C driver uses `path` in `read_file` to get the `buf` passed to `index_lines`. |
| `lines.asm` | `index_lines` | Scans the `buf` from `read_file` and builds an index of line starts and lengths. Fills one `struct line` per line, in file order, and stops at max entries, and returns the number of lines. |
| `match.asm` | `line_matches` | Gets the line and its lengths from the `index_lines` entry, and the pattern from `parse_args` with its length, along with fold (`-i`) and whole (`-w`) as flags. Returns `1` if `pat` occurs in the line, `0` otherwise. A nonzero fold means the program must search for the pattern in the line case-insensitively, while a nonzero whole means it requires a whole-word match. |
| `fmt.asm` | `int_to_dec` | Write the decimal text of n into out. Return the byte count. No leading zeros (except n == 0, which is “0” as is), no sign, no terminator. |
<br>

__How the line index is built from one buffer__ <br>
`index_lines` fills the `struct line` with a list of {offset, length} pairs, one per line, in file order, that points into the original buffer. The buffer is never copied or modified, so `driver.c` can print any line from `buf + offset` for `length` bytes. A line’s length excludes its trailing newline, the last line still counts when the file has no trailing newline, and an empty file has zero lines.
<br><br>

__How the flag table dispatches__ <br>
`parse_args` turns flag characters into bits, and the driver acts on these bits.

`flag_chars db 'n','c','v','i','w'` is stored in bit order, so a character’s position in the table is its bit number:

| Char | Table Index | `ecx` after `i` is hit | Bit Set in Flags |
|---|---|---|---|
| n | 0 | 4 | 1 |
| c | 1 | 3 | 2 |
| v | 2 | 2 | 4 |
| i | 3 | 1 | 8 |
| w | 4 | 0 | 16 |

For each token found in the command line, if `parse_args` recognizes it as a flag group, it loops over each byte after the dash, loading it into `al`. It sets `edi = table` and `ecx = table length`. Then `repne scasb` scans the table, compares `al` with `[edi]`, advances `edi`, and decrements `ecx` until they match or `ecx` hits `0`. If there is no match, the character is an unknown flag, and `parse_args` returns it as a positive int. Otherwise, it reads the index where the flag matches (`4 - ecx` since `ecx` has already been decremented for the matching byte), and `or`s the bit into flags. 

The addition of flags changes the flag table in the parser, the flag state, and the driver’s dispatch, two of which are in `driver.c` that cannot be modified. 

`scasb` reads the direction flag the same way `cmpsb` does, so pointers advance at `0` (DF cleared by `cld`) and move backwards at `1` (DF set by `std`). `parse_args` runs `cld` at entry so it never depends on what ran before.
<br><br>

__Which registers each routine uses__ <br>
All four routines follow the same `cdecl` rules as Lab 2, where arguments are on a stack starting at `[ebp+8]` and `eax` returns the value. `eax`, `ecx`, and `edx` are caller-saved registers, so a routine can overwrite them, while callee-saved registers (`ebx`, `esi`, `edi`, and `ebp`) must be preserved. Some routines, such as `parse_args`, use other views of registers (`al`, `ah`, `ax`).
<br><br>

### Timeline

One line per week. Name the subsystem each week finishes and the member
who owns it.

| Week | Goal | Owner |
|---|---|---|
| 1 | Complete Design Notes and Subsystem Ownership; Build working prototype (`args.asm`, `lines.asm`). | Carreon, Kaindoy;  Cambel, De Guzman |
| 2 | Implement `match.asm` and `fmt.asm`. | Carreon, Kaindoy |
| 3 | Set up additional tests; Document issues and quirks and debugging (if any). | Kaindoy; All members |
| 4 | Defense | All members |

## Subsystem Ownership

Complete this section before the Week 1 progress report. The manual lists
the three subsystems. Each member owns one. In a group of four, two members
share one. The commit history must agree with this table.

| Subsystem | Owner |
|---|---|
| Buffering and lines (`lines.asm`) | Cambel |
| Matching (`match.asm`) | Carreon |
| Formatting and flags (`fmt.asm`, `args.asm`, the tests you add) | De Guzman, Kaindoy |

## Quirks and Issues

Complete this section before the Week 3 progress report. The syllabus asks
for documentation of quirks and issues with the complete implementation.
One entry per item. State what happens, what causes it, and what the group
did about it.

### Known issues

- 

### Quirks

- 
