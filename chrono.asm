
;  Copyright 2021, David S. Madole <david@madole.net>
;
;  This program is free software: you can redistribute it and/or modify
;  it under the terms of the GNU General Public License as published by
;  the Free Software Foundation, either version 3 of the License, or
;  (at your option) any later version.
;
;  This program is distributed in the hope that it will be useful,
;  but WITHOUT ANY WARRANTY; without even the implied warranty of
;  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;  GNU General Public License for more details.
;
;  You should have received a copy of the GNU General Public License
;  along with this program.  If not, see <https://www.gnu.org/licenses/>.


            ; Include kernel and BIOS API definitions

include     include/bios.inc
include     include/kernel.inc


            ; Convenience definitions

null:       equ   0                      ; sometimes this is more expressive


            ; Executable program header

            org   2000h - 6
            dw    start
            dw    end-start
            dw    start


            ; Build information

start:      br    main
            db    4+80h                 ; month
            db    4                     ; day
            dw    2022                  ; year
            dw    1                     ; build

            db    'See github.com/dmadole/Elfos-chrono for more info',0


            ; Skip any leading spaces, and when we hit the end of the line,
            ; go and install the clock module. Process any options we find
            ; along the way as appropriate.

main:       lda   ra                    ; go if end, otherwise skip spaces
            lbz   checkver
            smi   ' '
            lbz   main

            smi   '-'-' '               ; a dash introduces an option
            lbz   isoption

opterror:   sep   scall                 ; if anything else, then error
            dw    o_inmsg
            db    'ERROR: Usage: chrono [-i]',13,10,0
            sep   sret

isoption:   lda   ra                    ; if next character is 'i' then init
            smi   'i'
            lbnz  opterror


            ; The -i option initializes the RTC to rational values and
            ; should be done on a new chip or when the battery is replaced.
 
            ldi   high inittab
            phi   rd
            ldi   low inittab
            plo   rd
            sex   rd

initnxt:    out   5
            out   5
            ldn   rd
            lbnz  initnxt

            sep   scall
            dw    o_inmsg
            db    'RTC 72421 has been initialized.',13,10,0

            sep   sret


            ; Check minimum kernel version we need before doing anything else,
            ; in particular we need support for the heap manager to allocate
            ; memory for the persistent module to use.

checkver:   ldi   high k_ver             ; get pointer to kernel version
            phi   r7
            ldi   low k_ver
            plo   r7

            lda   r7                     ; if major is non-zero we are good
            lbnz  allocmem

            lda   r7                     ; if major is zero and minor is 4
            smi   4                      ;  or higher we are good
            lbdf  allocmem

            sep   scall                  ; if not meeting minimum version
            dw    o_inmsg
            db    'ERROR: Needs kernel version 0.4.0 or higher',13,10,0

            sep   sret


            ; Allocate memory from the heap for the driver code block, leaving
            ; address of block in register R8 and RF for copying code and
            ; hooking vectors and the length of code to copy in RB.

allocmem:   ldi   high (end-module)      ; size of permanent code module
            phi   rb
            phi   rc
            ldi   low (end-module)
            plo   rb
            plo   rc

            ldi   255                    ; request page-aligned block
            phi   r7
            ldi   4+64                   ; request permanent named block
            plo   r7

            sep   scall                  ; allocate block on heap
            dw    o_alloc
            lbnf  copycode

            sep   scall                  ; if unable to get memory
            dw    o_inmsg
            db    'ERROR: Unable to allocate heap memory',13,10,0

            sep   sret


            ; Copy the code of the persistent module to the memory block that
            ; was just allocated using RF for destination and RB for length.
            ; This burns RF and RB but R8 will still point to the block.

copycode:   ldi   high module            ; get source address to copy from
            phi   rd
            ldi   low module
            plo   rd

            glo   rf                     ; make a copy of block pointer
            plo   r8
            ghi   rf
            phi   r8

copyloop:   lda   rd                     ; copy code to destination address
            str   rf
            inc   rf
            dec   rc
            dec   rb
            glo   rb
            lbnz  copyloop
            ghi   rb
            lbnz  copyloop

            ghi   r8                     ; put offset between source and
            smi   high module            ;  destination onto stack
            str   r2

            lbr   padname

padloop:    ldi   0                      ; pad name with zeros to end of block
            str   rf
            inc   rf
            dec   rc
padname:    glo   rc
            lbnz  padloop
            ghi   rc
            lbnz  padloop

            ; Update kernel hooks to point to our module code. Use the offset
            ; to the heap block at M(R2) to update module addresses to match
            ; the copy in the heap. If there is a chain address needed for a
            ; hook, copy that to the module first in the same way.

            ldi   high patchtbl         ; Get point to table of patch points
            phi   r7
            ldi   low patchtbl
            plo   r7

ptchloop:   lda   r7                    ; get address to patch, a zero
            lbz   success               ;  msb marks end of the table
            phi   rd
            lda   r7
            plo   rd
            inc   rd

            lda   r7                    ; if chain needed, then get address,
            lbz   notchain              ;  adjust to heap memory block
            add
            phi   rf
            ldn   r7
            plo   rf
            inc   rf

            lda   rd                    ; patch chain lbr in module code
            str   rf                    ;  to existing vector address
            inc   rf
            ldn   rd
            str   rf
            dec   rd

notchain:   inc   r7                    ; get module call point, adjust to
            lda   r7                    ;  heap, and update into vector jump
            add
            str   rd
            inc   rd
            lda   r7
            str   rd

            lbr   ptchloop


success:    sep   scall                 ; display identity to indicate success
            dw    o_inmsg
            db    'Chrono 72421 RTC Driver Build 1 for Elf/OS',13,10,0

            sep   sret


            ; Table giving addresses of jump vectors we need to update to
            ; point to us instead, and what to point them to. The patching
            ; code adjusts the target address to the heap memory block.

patchtbl:   dw    o_getdev, getdev, getdev
            dw    o_gettod, null, gettod
            dw    o_settod, null, settod
            db    null


            ; Table of address and value pairs to write to RTC to initialize
            ; it, which should only need to be done on a new chip or after
            ; replacing the battery. This resets all registers to rational
            ; values including resetting the time to 01/01/2001 00:00:00.

inittab:    db    2fh,17h
            db    2ef,10h
            db    2df,10h
            db    2cf,10h
            db    2bh,12h
            db    2ah,19h
            db    29h,10h
            db    28h,11h
            db    27h,10h
            db    26h,11h
            db    25h,10h
            db    24h,10h
            db    23h,10h
            db    22h,10h
            db    21h,10h
            db    20h,10h
            db    2fh,14h
            db    0


            ; Start the actual module code on a new page so that it forms
            ; a block of page-relocatable code that will be copied to himem.

            org     (($ + 0ffh) & 0ff00h)

module:    ; Memory-resident module code starts here


            ; Replacement for f_getdev call to hook into o_getdev. This calls
            ; whatever was previously installed, which is patched into the
            ; first call instruction, and then adds the RTC bit into it.

getdev:     sep   scall                 ; call previous o_getdev
            dw    f_getdev              ;  this gets patched

            glo   rf                    ; add in the RTC bit
            ori   10h
            plo   rf

            sep   sret                  ; that's it


            ; Get the time of day from the hardware clock into the buffer
            ; at RF in the order Elf/OS expects: M, D, Y, H, M, S. This is
            ; a replacement for f_gettod from the extended BIOS calls.

gettod:     ldi   low getnext           ; do common initialization
            br    todinit

getnext:    sex   rd                    ; output tens address, inc pointer
            out   5

            sex   r2                    ; input tens and multiply by 10
            inp   5
            ani   0fh
            str   r2
            shl
            shl
            add
            shl
            stxd                        ; decrement for room for next inp

            sex   rd                    ; output ones address, inc pointer
            out   5

            sex   r2                    ; input ones and add to tens
            inp   5
            ani   0fh
            inc   r2
            add

            str   rf                    ; save to output buffer and bump
            inc   rf

            ldn   rd                    ; continue if more digits to fetch
            bnz   getnext
            br    todrest



            ; Set the time of day into the hardware clock from the buffer
            ; at RF in the order Elf/OS expects: M, D, Y, H, M, S. This is
            ; a replacement for f_settod from the extended BIOS calls.

settod:     ldi   low setnext           ; do common initialization
            br    todinit

setnext:    ldi   0                     ; clear tens counter
            plo   re

            lda   rf                    ; load value, advance pointer

            skp                         ; divide by 10 by subtraction
settens:    inc   re
            smi   10
            bdf   settens

            adi   10+10h                ; adjust remainder and push to stack
            stxd

            glo   re                    ; push tens to stack
            adi   10h
            str   r2

            sex   rd                    ; output tens address, inc pointer
            out   5
            sex   r2                    ; output tens value, pop stack
            out   5

            sex   rd                    ; output ones address, inc pointer
            out   5
            sex   r2                    ; output ones value, pop stack
            out   5

            dec   r2

            ldn   rd                    ; continue if more digits to fetch
            bnz   setnext
            br    todrest


            ; Common starting steps for reading or setting the time in the
            ; RTC chip: save registered, set the chip into hold mode, and
            ; initialize a pointer to the digit address table. This is called
            ; as a "short call" subroutine by branching to it with the return
            ; address in the page in register D.

todinit:    plo   re                    ; save return address

            glo   rd                    ; save so we can use as table pointer
            stxd
            ghi   rd
            stxd

            sex   r3                    ; set address to register d
            out   5
            db    2dh
            br    todhold

todbusy:    sex   r3                    ; clear hold bit
            out   5
            db    10h

todhold:    out   5                     ; set hold bit
            db    11h

            sex   r2                    ; wait until busy bit is clear
            inp   5
            ani   02h
            bnz   todbusy

            ghi   r3                    ; load pointer to digit addresses
            phi   rd
            ldi   low clocktab
            plo   rd

            glo   re                    ; return to caller
            plo   r3


            ; Concluding steps of reading or setting the time: clear the hold
            ; bit, restore saved registers, and return success. This is jumped
            ; to since it is the end the the prior routines.

todrest:    sex   r3                    ; clear hold bit
            out   5
            db    2dh
            out   5
            db    10h
            sex   r2

            irx                         ; restore table pointer register
            ldxa
            phi   rd
            ldx
            plo   rd

            adi   0                     ; return success to caller
            sep   sret


            ; Table of the time-of-day digit addresses in the RTC 72421
            ; chip in the order that Elf/OS presents the date.

clocktab:   db    29h                   ; month
            db    28h
            db    27h                   ; day
            db    26h
            db    2bh                   ; year
            db    2ah
            db    25h                   ; hour
            db    24h
            db    23h                   ; minute
            db    22h
            db    21h                   ; second
            db    20h
            db    0


            ; Name for the heap block. This will be padded out if needed with
            ; zeroes to the end of the block (if more allocated than needed).

            db    0,'Chrono',0

end:       ; That's all folks!
