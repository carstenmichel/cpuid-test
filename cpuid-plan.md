# cpuid — ARM64 macOS CPU-Info Tool

## Top-Level Overview

Ziel ist ein kleines Assembly-Kommandozeilenprogramm für Apple Silicon macOS (ARM64),
das CPU-Informationen per `sysctl`-Syscall ausliest und auf der Konsole ausgibt.

**Technischer Hintergrund:**
- NASM unterstützt kein ARM64 — stattdessen wird `as` (LLVM/Clang Assembler für ARM64) verwendet.
- Die echte ARM64 `CPUID`-Instruktion (`mrs x0, MIDR_EL1`) ist im macOS Userspace (EL0) nicht zugreifbar.
- CPU-Informationen werden über den macOS `sysctlbyname`-Syscall abgefragt.
- Der Linker ist `ld` mit dem macOS SDK.

**Ausgabe-Keys (via sysctl):**
- `machdep.cpu.brand_string` — CPU-Name (z.B. "Apple M3 Pro")
- `hw.machine` — Architektur (z.B. "arm64")
- `hw.model` — Hardware-Modell (z.B. "Mac15,6")

**Fehlerbehandlung:**
- Schlägt ein `sysctlbyname`-Aufruf fehl, gibt das Programm eine Fehlermeldung auf stderr aus.
- Liefert der Syscall errno `EPERM (1)` zurück, wird zusätzlich ein Hinweis auf fehlende Root-Rechte ausgegeben.
- Das Programm beendet sich mit Exit-Code 1 bei einem Fehler.

**Dateien:**
```
cpuid.s       — ARM64 Assembly-Quellcode
Makefile      — Build-System (as + ld)
```

---

## Sub-Task 1 — Assembly-Quellcode schreiben

**Status:** `[x] done`

**Intent:**
Den ARM64 Assembly-Quellcode `cpuid.s` schreiben, der über macOS `sysctlbyname`-Syscalls
die CPU-Identifikation ausliest, strukturiert auf stdout ausgibt und bei Fehler eine
klare Meldung auf stderr schreibt.

**Expected Outcomes:**
- Datei `cpuid.s` existiert und kompiliert fehlerfrei.
- Beim Ausführen erscheinen die drei Felder `brand_string`, `hw.machine` und `hw.model` im Terminal.
- Bei einem `sysctlbyname`-Fehler erscheint eine Fehlermeldung auf stderr (fd=2).
- Bei errno `EPERM` erscheint zusätzlich der Hinweis, das Programm mit `sudo` auszuführen.
- Exit-Code ist 0 bei Erfolg, 1 bei Fehler.

**Todo List:**
1. `.data`-Sektion anlegen mit:
   - Den drei sysctl-Key-Strings (`machdep.cpu.brand_string`, `hw.machine`, `hw.model`).
   - Ausgabe-Labels für jede Zeile (z.B. `"CPU Brand: "`, `"Architecture: "`, `"Model: "`).
   - Fehlermeldungs-Strings: generische Fehlermeldung und EPERM-Hinweis.
2. `.bss`-Sektion mit Result-Buffern (je 256 Bytes) und `size_t`-Variablen für die Buffer-Längen.
3. Hilfsfunktion `print` implementieren:
   - Schreibt einen Null-terminierten String auf einen gegebenen File-Descriptor (stdout=1, stderr=2).
   - Berechnet die String-Länge intern (Loop bis `\0`).
   - Ruft `write`-Syscall (`0x2000004`) auf.
4. Hilfsfunktion `query_sysctl` implementieren:
   - Parameter: Pointer auf Key-String, Pointer auf Output-Buffer, Pointer auf Buffer-Größe.
   - Initialisiert `oldlenp` mit der Buffer-Größe.
   - Ruft `sysctlbyname`-Syscall (`0x200000a`) auf: `(name, oldp, oldlenp, NULL, 0)`.
   - Gibt im Erfolgsfall 0 zurück, im Fehlerfall den errno-Wert (liegt nach `svc #0x80` bei gesetztem Carry-Flag in `x0`).
5. Fehlerbehandlungs-Routine `handle_error` implementieren:
   - Prüft, ob der errno-Wert gleich `EPERM (1)` ist.
   - Gibt bei EPERM den EPERM-Hinweis (`"Error: Permission denied. Try running with sudo.\n"`) auf stderr aus.
   - Gibt ansonsten eine generische Fehlermeldung (`"Error: sysctl query failed.\n"`) auf stderr aus.
   - Ruft `exit`-Syscall (`0x2000001`) mit Code 1 auf.
6. `_start`-Einstiegspunkt schreiben:
   - Für jeden der drei sysctl-Keys: `query_sysctl` aufrufen, bei Fehler `handle_error` aufrufen.
   - Bei Erfolg: Label-String + Ergebnis-String + Newline auf stdout ausgeben.
   - Programm via `exit`-Syscall mit Code 0 beenden.

**Relevant Context:**
- macOS ARM64 Syscall-Konvention: Parameter in `x0`–`x7`, Syscall-Nummer in `x16`, Aufruf via `svc #0x80`.
- macOS Syscall-Nummern: `write = 0x2000004`, `exit = 0x2000001`, `sysctlbyname = 0x200000a`.
- `sysctlbyname`-Signatur: `(const char *name, void *oldp, size_t *oldlenp, void *newp, size_t newlen)`.
- Nach `svc #0x80`: Carry-Flag (C) gesetzt = Fehler; `x0` enthält dann den errno-Wert.
- `EPERM = 1` — Permission denied (tritt auf bei privilegierten sysctl-Keys).
- Stack muss vor jedem `svc`-Aufruf 16-Byte-aligned sein.
- Result-Buffer: mindestens 256 Bytes (brand_string kann bis zu ~64 Zeichen lang sein).
- `machdep.cpu.brand_string` ist auf Apple Silicon ohne Root zugänglich; `EPERM` ist trotzdem
  eine mögliche Antwort bei anderen Keys auf gesperrten Systemen.

---

## Sub-Task 2 — Makefile schreiben

**Status:** `[x] done`

**Intent:**
Ein `Makefile` erstellen, das den vollständigen Build- und Clean-Prozess über `as` (Assembler)
und `ld` (Linker) steuert.

**Expected Outcomes:**
- `make` baut das Binary `cpuid` aus `cpuid.s`.
- `make clean` entfernt alle Build-Artefakte (`cpuid`, `cpuid.o`).
- `make run` baut und führt das Programm aus.

**Todo List:**
1. Variable `AS = as` und `LD = ld` setzen.
2. Assembler-Flags definieren: `-arch arm64` für `as`.
3. Linker-Flags definieren:
   - `-arch arm64`
   - `-platform_version macos 12.0 12.0`
   - `-e _start` (Einstiegspunkt, da kein C-Runtime)
   - `-o cpuid`
   - `-lSystem -L$(shell xcrun --show-sdk-path)/usr/lib` für macOS-Syscall-Stubs.
4. Default-Target `all: cpuid`.
5. Target `cpuid: cpuid.o` — linkt das Object-File zum Binary.
6. Target `cpuid.o: cpuid.s` — assembliert die Source zur Object-Datei.
7. Target `run: cpuid` — führt `./cpuid` aus.
8. Target `clean` — entfernt `cpuid` und `cpuid.o` (mit `-f` Flag).
9. `.PHONY`-Deklaration für `all`, `run`, `clean`.

**Relevant Context:**
- `as` und `ld` sind Teil der Xcode Command Line Tools (`xcode-select --install`).
- `-lSystem` ist zwingend erforderlich — macOS routet Syscalls intern über `libSystem.dylib`.
- `xcrun --show-sdk-path` liefert den aktuellen SDK-Pfad dynamisch (z.B. `/Library/Developer/CommandLineTools/SDKs/MacOSX.sdk`).
- `-platform_version` ist der moderne Ersatz für das veraltete `-macos_version_min`.

---

## Hinweise zur Implementierung

- Alle Syscalls laufen auf macOS über `svc #0x80` (nicht `syscall` wie auf Linux).
- Nach `svc #0x80`: Carry-Flag gesetzt → Fehler, `x0` = errno; kein Carry → Erfolg, `x0` = Rückgabewert.
- Bei `sysctlbyname` muss `oldlenp` ein Pointer auf eine `size_t`-Variable sein, die **vorab** mit der Buffer-Größe initialisiert wird — sonst Absturz.
- Der `_start`-Label (nicht `main`) ist der Einstiegspunkt, da kein C-Runtime (`crt0`) gelinkt wird.
- Stack-Alignment: 16 Bytes vor jedem `svc`-Aufruf — bei Bedarf mit `sub sp, sp, #16` sicherstellen.
- Funktionsaufrufe via `bl` / Rücksprung via `ret` (ARM64-Konvention); `x30` = Link-Register sichern bei verschachtelten Calls.
