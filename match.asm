;
; match.asm - line_matches, substring search with case folding and word
; boundaries. Callable from C.
;
; This is your starting point: it assembles and links as-is, so the build
; works before you write any code. Right now it always returns 0 (no
; match), which makes rengrep print nothing. Your job is to replace that
; with the search described below.
;
; The contract, from driver.c:
;
;       int line_matches(char *line, int linelen,
;                        char *pat, int patlen,
;                        int fold, int whole)
;
; so on the stack after a cdecl call:
;       [ebp+8]  = line
;       [ebp+12] = linelen
;       [ebp+16] = pat
;       [ebp+20] = patlen
;       [ebp+24] = fold
;       [ebp+28] = whole
;
; Return 1 in eax if pat occurs in line, 0 otherwise.
;
; Requirements from the manual:
;
;   * Use the x86 string instructions for the inner comparison. repe cmpsb
;     at minimum. A mov/cmp loop does not satisfy the activity.
;   * fold: compare case-insensitively WITHOUT modifying the buffer. Fold
;     in a register at comparison time. This path cannot use repe cmpsb
;     (it compares raw bytes), so a folding loop for that path is expected.
;   * whole: a match counts only when the byte before the match and the
;     byte after it are both non-word characters or absent. A failed
;     word-boundary check does NOT end the search. Keep scanning.
;   * The search bound is linelen - patlen, not linelen. Compare it with a
;     signed jump. When patlen is larger than linelen the difference is
;     negative. An unsigned jump reads it as enormous, and the scan runs
;     off the line into memory the process does not own and faults. This
;     is the Block 5 lesson.
;   * An empty pattern matches at every position, as it does in grep. A
;     rep prefix with ecx = 0 executes nothing and leaves the flags as they
;     were, so set ZF yourself before repe cmpsb. A bottom-tested folding
;     loop needs its own guard.
;   * Set cld explicitly. The direction flag persists across calls and
;     assuming it is clear is how a routine that works alone breaks when
;     called after something else.
;   * Preserve ebx, esi, edi, and ebp. Return in eax.
;   * No calls into the C standard library.
;
; Word characters are A-Z, a-z, 0-9, and _.
;

; Windows C puts a leading underscore on every exported name. Linux C does
; not. The Makefile passes -d ELF_TYPE on Linux. This block then respells
; the names below to match. asm_io.inc does the same for _asm_main in the
; bootcamp blocks. Leave this block alone.
%ifdef ELF_TYPE
  %define _line_matches line_matches
  section .note.GNU-stack noalloc noexec nowrite progbits
%endif

segment .text
        global  _line_matches

_line_matches:
        enter   0,0
        pusha

        ;
        ; TODO: search.
        ;
        ; The loop the manual describes:
        ;
        ;   for start = 0 to linelen - patlen:
        ;       compare patlen bytes at line+start against pat
        ;       if equal: check word boundaries if whole
        ;                 return 1 if they pass
        ;   return 0
        ;
        ; The fast path (fold == 0) uses repe cmpsb. The folding path
        ; compares a byte at a time, folding both sides in a register.
        ; Both need cld first.
        ;

        cld                             ; DF
        mov     ebx, [ebp+12]           ; get linelen
        sub     ebx, [ebp+20]           ; lineline - patlen, bounds
        jl      .no_match               ; pat is longer than linelen

        mov     edx, 0                  ; cleans edx = start = 0
        
        ; ebx = bounds, edx = 0
.start:
        cmp     edx, ebx                ; start - bounds
        jg      .no_match               ; start > bounds, not valid 

        mov     esi, [ebp+16]           ; get pat
        mov     edi, [ebp+8]            ; get line
        add     edi, edx                ; line + start
        mov     ecx, [ebp+20]           ; get patlen

        cmp     dword[ebp+24], 0        ; fold flag
        jne     .fold                   ; jumps to .fold if fold != 0

        ; fast path (fold == 0)
        test    ecx, ecx                ; setting ZF = 1 when patlen == 0 (empty pattern)
        repe    cmpsb                   ; [esi] [edi] comparison, advances pointers
                                        ; stop when ZF = 0 (mismatch)
        jne     .next                   ; mismatch (ZF = 0): next pos
        jmp     .candidate              ; all bytes equal (ZF = 1)

; case-insensitive
.fold:
        test    ecx, ecx                ; patlen == 0
        jz      .candidate              ; empty pattern: match

.fold_loop:
        ; esi = next pat byte, edi = next line byte, ecx = bytes left to compare
        lodsb                           ; loads pat byte to al, advances esi
        mov     ah, [edi]               ; gets line byte 
        inc     edi                     ; next line byte

        cmp     al, 'A'                 ; fold
        jb      .not_upper
        cmp     al, 'Z'
        ja      .not_upper
        add     al, 32                  ; 'a' - 'A' = 32

.not_upper:
        cmp     ah, 'A'                 ; fold
        jb      .upper
        cmp     ah, 'Z'
        ja      .upper
        add     ah, 32                  ; 'a' - 'A' = 32

.upper:
        ; al = folded pat byte, ah = folded line byte
        cmp     al, ah
        jne     .next                   ; mismatch

        dec     ecx                     ; bytes left to comp
        jnz     .fold_loop              ; loop back when ecx != 0

        jmp     .candidate              ; bytes match 

        ; pat match
.candidate:
        cmp     dword[ebp+28], 0        ; whole flag
        je      .match                  ; jumps to match if does not require whole word matching

        ; left check
        test    edx, edx                ; start 0
        jz      .check
        mov     esi, [ebp+8]            ; get line
        mov     al, [esi+edx-1]         ; line[start-1]

        cmp     al, '0'                 ; below 0
        jb      .check
        cmp     al, '9'                 ; 0-9
        jbe     .next
        cmp     al, 'A'                 ; 9-A, symbols
        jb      .check
        cmp     al, 'Z'                 ; A-Z
        jbe     .next
        cmp     al, '_'                 ; _
        je      .next
        cmp     al, 'a'                 ; Z-a, not _, parentheses, brackets, etc.
        jb      .check
        cmp     al, 'z'                 ; a-z
        jbe     .next

        ; right check
.check:
        mov     eax, edx                ; start
        add     eax, [ebp+20]           ; start + patlen
        cmp     eax, [ebp+12]           ; linelen comp to start + patlen
        je      .match                  ; end of line
        mov     esi, [ebp+8]
        mov     al, [esi+eax]           ; line[start+patlen]
        
        cmp     al, '0'                 ; below 0
        jb      .match
        cmp     al, '9'                 ; 0-9
        jbe     .next
        cmp     al, 'A'                 ; 9-A, symbols
        jb      .match
        cmp     al, 'Z'                 ; A-Z
        jbe     .next
        cmp     al, '_'                 ; _
        je      .next
        cmp     al, 'a'                 ; Z-a, not _, parentheses, brackets, etc.
        jb      .match
        cmp     al, 'z'                 ; a-z
        jbe     .next

        jmp     .match

.next:
        inc     edx                     ; increments start
        jmp     .start                  ; loop back

.match:
        popa
        mov     eax, 1                  ; found match
        leave
        ret

.no_match:
        popa
        mov     eax, 0                  ; no match
        leave
        ret
