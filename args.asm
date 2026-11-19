;
; args.asm - parse_args, the command line to a flag set, a pattern, and a
; file name. Callable from C.
;
; This is your starting point: it assembles and links as-is, so the build
; works before you write any code. Right now it returns -1, which makes
; rengrep print its usage line for every command. Nothing else runs until
; this routine works, so write it first. It is the shortest of the four.
;
; The contract, from driver.c:
;
;       struct args *out            [ebp+16]
;       char **argv                 [ebp+12]
;       int argc                    [ebp+8]
;
;       int parse_args(int argc, char **argv, struct args *out)
;
;       struct args { int flags; char *pattern; char *path; };
;                     +0         +4             +8
;
;       FLAG_N = 1, FLAG_C = 2, FLAG_V = 4, FLAG_I = 8, FLAG_W = 16
;
; Fill out and return 0. Return -1 when the pattern or the file is missing,
; or when a third positional token appears. Return the offending character,
; as a positive number, on an unknown flag. The driver prints it.
;
; Requirements from the manual:
;
;   * A token whose first byte is '-' and whose second byte is not NUL is a
;     flag group, wherever it appears. -nvi is -n -v -i. "-" alone is not a
;     flag group.
;   * Every other token is positional. The first is the pattern, the second
;     is the file.
;   * Keep the flag characters in a table, in bit order, and find each one
;     with scasb. The bit is 1 shifted left by the table index. A chain of
;     cmp/je is the structure the rubric marks down.
;   * Set cld explicitly. scasb honours the direction flag.
;   * Preserve ebx, esi, edi, and ebp. Return in eax.
;   * No calls into the C standard library.
;

; Windows C puts a leading underscore on every exported name. Linux C does
; not. The Makefile passes -d ELF_TYPE on Linux. This block then respells
; the names below to match. asm_io.inc does the same for _asm_main in the
; bootcamp blocks. Leave this block alone.
%ifdef ELF_TYPE
  %define _parse_args parse_args
  section .note.GNU-stack noalloc noexec nowrite progbits
%endif

segment .data
        flag_table db 'n', 'c', 'v', 'i', 'w'     ; bit 0 to bit 4
        FLAG_COUNT equ 5

segment .text
        global  _parse_args

_parse_args:
        ; preserve callee-saved registers
        push    ebp
        mov     ebp, esp
        push    ebx
        push    esi
        push    edi

        ;
        ; TODO: parse.
        ;
        ; The steps the manual describes:
        ;
        ;   clear out->flags, out->pattern, out->path
        ;   for each token in argv[1..argc-1]:
        ;       if the token is a flag group:
        ;           for each byte after the dash:
        ;               find it in the table with repne scasb
        ;               not found: return the byte
        ;               set the bit for its index
        ;       else if out->pattern is empty: out->pattern = token
        ;       else if out->path is empty:    out->path = token
        ;       else: return -1
        ;   return -1 if the pattern or the path is still empty
        ;   return 0
        ;
        ; After repne scasb finds a byte, ecx has been decremented once for
        ; the hit as well. Work the index out from that before you shift.
        ;

        cld                             ; make scan advance forward
        mov     ebx, [ebp+16]           ; ebx = *out

        ;initialize all three 4-byte fields
        mov     dword [ebx], 0          ; out->flags
        mov     dword [ebx+4], 0        ; out->pattern
        mov     dword [ebx+8], 0        ; out->path

        mov     edx, 1  ;the argv index

.walk_args:
        cmp     edx, [ebp+8]            ; compare current argv index w/ total num of args
        jge     .finish
        mov     eax, [ebp+12]           ; load current arg
        mov     esi, [eax+edx*4]        ; check first char
        inc     edx

        cmp     byte [esi], '-'         ; compare 1st char with '-'
        jne     .positional
        cmp     byte [esi+1], 0         ; compare 2nd char with NUL ('\0')
        je      .positional
        inc     esi                     ; go to next char

.scanning_shifting:
        movzx     eax, byte [esi]       ; if extended ASCII char is passed, zero-extend
        cmp       eax, 0
        je        .walk_args            ; if '\0' current argv token is fully parsed
        inc       esi                   ;next character
        mov       edi, flag_table       ; edi points to start of flag table
        mov       ecx, FLAG_COUNT       ; search until at most 5 chars
        repne     scasb
        jne       .unknown_flag

        mov     eax, FLAG_COUNT - 1
        sub     eax, ecx                ; eax = 4 - ecx
        mov     ecx, eax                ; (holds the exact index 0-4)

        ; turn this flag's bit inside out->flags
        mov     eax, 1
        shl     eax, cl                 ; move bit to right flag position
        or      [ebx], eax              ; combine with current flipped bits

        jmp     .scanning_shifting

.unknown_flag:
        jmp     .done                   ; eax still holds the unknown char


.positional:
        cmp     dword [ebx+4], 0        ; if any positional exists
        jnz     .try_path
        mov     [ebx+4], esi            ; store  to out->pattern
        jmp     .walk_args

.try_path:
        cmp     dword [ebx+8], 0        ; if only one positional word was given (no path)
        jnz     .usage_error            ; extra positional, since two are already given
        mov     [ebx+8], esi            ; store to out->path
        jmp     .walk_args              ; next arg

.finish:
        cmp     dword [ebx+4], 0        ; check if pattern exists
        je      .usage_error            ; no pattern
        cmp     dword [ebx+8], 0        ; check if path exists
        je      .usage_error            ;

        mov     eax, 0                  ; no errors
        jmp     .done

.usage_error:
        mov     eax, -1                 ; errors


.done:
        pop     edi                     ; LIFO
        pop     esi
        pop     ebx
        pop     ebp
        ret
