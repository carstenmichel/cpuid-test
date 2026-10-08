// cpuid.s — ARM64 macOS CPU-Info Tool
// Liest CPU-Informationen via sysctlbyname (libSystem) und gibt sie auf stdout aus.
// Fehler werden auf stderr ausgegeben; bei EPERM wird auf sudo hingewiesen.
//
// Auf modernem macOS (10.12+) sind direkte Kernel-Syscalls (svc #0x80) für
// User-Space-Programme gesperrt. Alle Systemaufrufe müssen über libSystem-
// Wrapper erfolgen: write(2), exit(3), sysctlbyname(3).
//
// ARM64-Aufrufkonvention (Apple ABI):
//   Argumente: x0–x7
//   Rückgabe:  x0 (x0:x1 für 128-Bit)
//   Callee-saved: x19–x28, x29 (frame pointer), x30 (link register)
//   Stack: 16-Byte-aligned vor jedem bl/svc

.section __DATA, __data

// sysctl-Keys
key_brand:   .asciz "machdep.cpu.brand_string"
key_machine: .asciz "hw.machine"
key_model:   .asciz "hw.model"

// Ausgabe-Labels (stdout)
lbl_brand:   .asciz "CPU Brand:    "
lbl_machine: .asciz "Architecture: "
lbl_model:   .asciz "Model:        "

newline:     .asciz "\n"

// Fehlermeldungen (stderr)
err_generic: .asciz "Error: sysctl query failed.\n"
err_eperm:   .asciz "Error: Permission denied. Try running with sudo.\n"

.section __DATA, __bss

// Ergebnis-Buffer (je 256 Bytes) und ihre Längen-Variablen (size_t = 8 Bytes)
.align 3
buf_brand:   .zero 256
len_brand:   .zero 8

buf_machine: .zero 256
len_machine: .zero 8

buf_model:   .zero 256
len_model:   .zero 8

// ─────────────────────────────────────────────────────────────────────────────
// Funktion: print_fd
//   Schreibt einen Null-terminierten String auf einen File-Descriptor.
//   x0 = fd (1=stdout, 2=stderr)
//   x1 = Pointer auf Null-terminierten String
//   Callee-saved Register werden gesichert.
// ─────────────────────────────────────────────────────────────────────────────
.section __TEXT, __text
.align 2

print_fd:
    stp x29, x30, [sp, #-32]!
    mov x29, sp
    stp x19, x20, [sp, #16]     // x19 = fd, x20 = str-Pointer

    mov x19, x0                 // fd sichern
    mov x20, x1                 // String-Pointer sichern

    // Länge berechnen: strlen-ähnlich
    mov x2, x1                  // laufender Zeiger
    mov x3, #0                  // Länge

.Lpfd_len:
    ldrb w4, [x2], #1
    cbz  w4, .Lpfd_call
    add  x3, x3, #1
    b    .Lpfd_len

.Lpfd_call:
    // write(fd, buf, len)
    mov  x0, x19
    mov  x1, x20
    // x2 = len (x3) — umkopieren
    mov  x2, x3
    bl   _write

    ldp x19, x20, [sp, #16]
    ldp x29, x30, [sp], #32
    ret

// ─────────────────────────────────────────────────────────────────────────────
// Funktion: query_sysctl
//   Ruft sysctlbyname(3) auf.
//   x0 = Pointer auf Key-String
//   x1 = Pointer auf Output-Buffer
//   x2 = Pointer auf size_t (vorab mit Buffer-Größe initialisiert)
//   Rückgabe: x0 = 0 bei Erfolg, -1 bei Fehler
//             Bei Fehler ist errno via _errno() abrufbar
// ─────────────────────────────────────────────────────────────────────────────
.align 2

query_sysctl:
    stp x29, x30, [sp, #-16]!
    mov x29, sp

    // sysctlbyname(name, oldp, oldlenp, newp=NULL, newlen=0)
    mov x3, #0                  // newp = NULL
    mov x4, #0                  // newlen = 0
    bl  _sysctlbyname           // Rückgabe: 0 = OK, -1 = Fehler

    ldp x29, x30, [sp], #16
    ret

// ─────────────────────────────────────────────────────────────────────────────
// Funktion: handle_error
//   Gibt Fehlermeldung auf stderr aus und beendet mit Exit-Code 1.
//   Prüft errno auf EPERM (1) und gibt ggf. sudo-Hinweis aus.
//   Kehrt nicht zurück.
// ─────────────────────────────────────────────────────────────────────────────
.align 2

handle_error:
    stp x29, x30, [sp, #-16]!
    mov x29, sp

    // errno über __error() holen (thread-safe auf macOS)
    bl  ___error               // Rückgabe: Pointer auf errno-Variable
    ldr w1, [x0]               // errno-Wert laden
    cmp w1, #1                 // EPERM = 1?
    b.eq .Lhe_eperm

    // Generische Fehlermeldung auf stderr
    mov  x0, #2
    adrp x1, err_generic@PAGE
    add  x1, x1, err_generic@PAGEOFF
    bl   print_fd
    b    .Lhe_exit

.Lhe_eperm:
    mov  x0, #2
    adrp x1, err_eperm@PAGE
    add  x1, x1, err_eperm@PAGEOFF
    bl   print_fd

.Lhe_exit:
    mov  x0, #1                // Exit-Code 1
    bl   _exit

    // Sicherheits-Halt (wird nie erreicht)
    brk  #0

// ─────────────────────────────────────────────────────────────────────────────
// Einstiegspunkt
// ─────────────────────────────────────────────────────────────────────────────
.globl _main
.align 2

_main:
    stp x29, x30, [sp, #-16]!
    mov x29, sp

    // ── 1. machdep.cpu.brand_string ─────────────────────────────────────────

    adrp x9, len_brand@PAGE
    add  x9, x9, len_brand@PAGEOFF
    mov  x10, #256
    str  x10, [x9]

    adrp x0, key_brand@PAGE
    add  x0, x0, key_brand@PAGEOFF
    adrp x1, buf_brand@PAGE
    add  x1, x1, buf_brand@PAGEOFF
    mov  x2, x9
    bl   query_sysctl
    cbnz x0, .Lerror_brand     // x0 != 0 → Fehler

    mov  x0, #1
    adrp x1, lbl_brand@PAGE
    add  x1, x1, lbl_brand@PAGEOFF
    bl   print_fd

    mov  x0, #1
    adrp x1, buf_brand@PAGE
    add  x1, x1, buf_brand@PAGEOFF
    bl   print_fd

    mov  x0, #1
    adrp x1, newline@PAGE
    add  x1, x1, newline@PAGEOFF
    bl   print_fd
    b    .Lnext_machine

.Lerror_brand:
    bl   handle_error           // kehrt nicht zurück

.Lnext_machine:

    // ── 2. hw.machine ────────────────────────────────────────────────────────

    adrp x9, len_machine@PAGE
    add  x9, x9, len_machine@PAGEOFF
    mov  x10, #256
    str  x10, [x9]

    adrp x0, key_machine@PAGE
    add  x0, x0, key_machine@PAGEOFF
    adrp x1, buf_machine@PAGE
    add  x1, x1, buf_machine@PAGEOFF
    mov  x2, x9
    bl   query_sysctl
    cbnz x0, .Lerror_machine

    mov  x0, #1
    adrp x1, lbl_machine@PAGE
    add  x1, x1, lbl_machine@PAGEOFF
    bl   print_fd

    mov  x0, #1
    adrp x1, buf_machine@PAGE
    add  x1, x1, buf_machine@PAGEOFF
    bl   print_fd

    mov  x0, #1
    adrp x1, newline@PAGE
    add  x1, x1, newline@PAGEOFF
    bl   print_fd
    b    .Lnext_model

.Lerror_machine:
    bl   handle_error

.Lnext_model:

    // ── 3. hw.model ──────────────────────────────────────────────────────────

    adrp x9, len_model@PAGE
    add  x9, x9, len_model@PAGEOFF
    mov  x10, #256
    str  x10, [x9]

    adrp x0, key_model@PAGE
    add  x0, x0, key_model@PAGEOFF
    adrp x1, buf_model@PAGE
    add  x1, x1, buf_model@PAGEOFF
    mov  x2, x9
    bl   query_sysctl
    cbnz x0, .Lerror_model

    mov  x0, #1
    adrp x1, lbl_model@PAGE
    add  x1, x1, lbl_model@PAGEOFF
    bl   print_fd

    mov  x0, #1
    adrp x1, buf_model@PAGE
    add  x1, x1, buf_model@PAGEOFF
    bl   print_fd

    mov  x0, #1
    adrp x1, newline@PAGE
    add  x1, x1, newline@PAGEOFF
    bl   print_fd
    b    .Ldone

.Lerror_model:
    bl   handle_error

.Ldone:
    ldp x29, x30, [sp], #16
    mov x0, #0
    bl  _exit

    brk #0
