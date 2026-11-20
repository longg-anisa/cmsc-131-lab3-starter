;
; lines.asm - index_lines, a file buffer to a list of lines. Callable from C.
;
; This is your starting point: it assembles and links as-is, so the build
; works before you write any code. Right now it returns 0 lines, which makes
; rengrep print nothing. Your job is to replace that with the index
; described below.
;
; The contract, from driver.c:
;
;       int max                     [ebp+20]
;       struct line *out            [ebp+16]
;       int len                     [ebp+12]
;       char *buf                   [ebp+8]
;
;       struct line { int offset; int length; };
;
; Fill out with one entry per line and return the number of entries
; written. The capacity is a hard limit: stop when out is full and return
; what you wrote. max == 0 writes nothing and returns 0.
;
; Requirements from the manual:
;
;   * A line's length EXCLUDES its trailing newline.
;   * A file with no trailing newline still indexes its last line.
;   * An empty file (len == 0) has zero lines.
;   * Preserve ebx, esi, edi, and ebp. Return the count in eax.
;   * No calls into the C standard library.
;
; The manual calls this "buffer to line index". Walk the buffer, find the
; newlines yourself, and record where each line starts and how long it
; is. The driver reads the file into one buffer and uses your index to
; treat it as a list of lines.
;

; Windows C puts a leading underscore on every exported name. Linux C does
; not. The Makefile passes -d ELF_TYPE on Linux. This block then respells
; the names below to match. asm_io.inc does the same for _asm_main in the
; bootcamp blocks. Leave this block alone.
%ifdef ELF_TYPE
  %define _index_lines index_lines
  section .note.GNU-stack noalloc noexec nowrite progbits
%endif

segment .text
        global  _index_lines

_index_lines:
        enter   0,0
        pusha

        ;
        ; TODO: build the index.
        ;
        ; Walk buf looking for newline bytes (0x0A). Each newline closes
        ; the line that ended before it. The tricky cases:
        ;
        ;   * If the file does not end with a newline, the bytes after the
        ;     last newline still form a line. The last entry has no
        ;     newline and must still be indexed.
        ;   * An empty file produces zero lines, not one empty line.
        ;
        ; Watch the max capacity too. out holds max entries. A file of len
        ; bytes has at most len lines, when every byte is a newline, so the
        ; caller's max is always big enough. The routine must still stop
        ; writing at max.
        ;

        mov     esi, [ebp+8]                    ; esi = buf
        mov     ecx, [ebp+12]                   ; ecs = len
        mov     edi, [ebp+16]                   ; edi = out
        mov     edx, [ebp+20]                   ; edx = max

        mov     eax, 0                          ; counter for entries (count) = 0
        mov     ebx, 0                          ; current index (i) = 0
        mov     dword [ebp-4], 0                ; starting index (start) = 0

; continuously loop while i < len
.walk_loop:
        cmp     ebx, ecx                        ; if i >= len, done walking
        jae     .trailing_newline              

        cmp     eax, edx                        ; if count >= max, out is full
        jae     .done_walk                     

        cmp     byte [esi+ebx], 0x0A            ; if buf[ index] == 0x0A (\n) 
        jne     .skip                          

        mov     edx, [ebp-4]                    ; edx = start
        mov     [edi], edx                      ; set offset as start
        mov     edx, ebx                        ; edx = i
        sub     edx, [ebp-4]                    ; edx = i - start
        mov     [edi+4], edx                    ; length = i - start
        add     edi, 8                          ; go to next entry
        inc     eax                             ; increase entry counter
        lea     edx, [ebx+1]                    ; edx = ebx + 1
        mov     [ebp-4], edx                    ; new start
        mov     edx, [ebp+20]                   ; reload max into edx

; move to next byte
.skip:
        inc     ebx                             ; move i
        jmp     .walk_loop

; handle last entry with no trailing newline
.trailing_newline:
        cmp     eax, edx                        ; if count >= max, out is full
        jae     .done_walk
        mov     edx, [ebp-4]                    ; edx = start
        cmp     edx, ecx                        ; if start >= len, no more leftover after /n
        jae     .done_walk
        mov     [edi], edx                      ; set offset as new start
        sub     ecx, edx                        ; length = start - len
        mov     [edi+4], ecx                    ; length stored
        inc     eax                             ; icnrement entry counter

; done walking
.done_walk:
        mov     [esp + 28], eax                 
        popa;
        leave
        ret
