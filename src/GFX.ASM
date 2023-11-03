;* Copyright (C) 2023 Nikolai Wuttke-Hohendorf. All rights reserved.
;*
;* This project is based on disassembly of executable files from the game
;* Duke Nukem, Copyright (C) 1991 Apogee Software, Ltd.
;*
;* Some parts of the code are based on or have been adapted from the Cosmore
;* project, Copyright (c) 2020-2022 Scott Smitelli.
;* See LICENSE_Cosmore file at the root of the repository, or refer to
;* https://github.com/smitelli/cosmore/blob/master/LICENSE.
;*
;*
;* This program is free software: you can redistribute it and/or modify
;* it under the terms of the GNU General Public License as published by
;* the Free Software Foundation, either version 3 of the License, or
;* (at your option) any later version.
;*
;* This program is distributed in the hope that it will be useful,
;* but WITHOUT ANY WARRANTY; without even the implied warranty of
;* MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;* GNU General Public License for more details.
;*
;* You should have received a copy of the GNU General Public License
;* along with this program.  If not, see <http://www.gnu.org/licenses/>
;*


;
; Low-level graphics routines
;
; References:
;  - [EGA]: IBM PC Hardware Reference Library - Enhanced Graphics Adapter,
;    August 2, 1984

IDEAL
ASSUME cs:_TEXT, ds:DGROUP, es:NOTHING


;
; Memory segment addresses.
;
EGA_SEGMENT                     EQU 0a000h
SOLID_TILE_SEGMENT              EQU (EGA_SEGMENT + 400h)


SEGMENT _TEXT


;
; Global storage in the code segment.
;
gfxCurrentDrawPage dw 0  ; EGA memory page to be drawn into (back buffer)


;
; Draw a single 16x16 pixel solid tile to the current draw page.
;
; TODO: Add documentation
;
;
; src_offset (word): Memory offset of the source tile, relative to the start
;     of solid tiles in video memory
; dst_offset (word): Memory offset to write to, relative to the current draw
;     page segment.
; Returns: Nothing
; Registers destroyed: AL, DX, ES
;
PROC _BlitSolidTile FAR @@src_offset:WORD, @@dst_offset:WORD
    PUBLIC _BlitSolidTile
    push  bp
    mov   bp, sp
    push  ds
    push  di
    push  si

    ; Set up destination segment (in EGA memory)
    mov   dx, EGA_SEGMENT
    mov   ax, [gfxCurrentDrawPage]
    cmp   al, 0
    jz    drawing_to_first_page
    ; When drawing to the 2nd page, add 200h to the destination segment.
    ; Otherwise, skip as DX already holds the correct segment.
    add   dx, 200h
drawing_to_first_page:

    ; Set up source and destination pointers from the arguments:
    ;   DS:SI <- Source tile data address (in EGA memory)
    ;   ES:DI <- Destination draw page address (in EGA memory)
    mov   es, dx
    mov   dx, SOLID_TILE_SEGMENT
    mov   ds, dx
    ASSUME ds:NOTHING
    mov   si, [@@src_offset]
    mov   di, [@@dst_offset]
    mov   bx, 38

    ; Draw 15 rows of tile pixels. All four color planes are copied, in
    ; parallel, through the EGA's internal latches. The memory read/write cycles
    ; are doing the actual work here.
    ; Latched write mode must be enabled!
    REPT 15
      movsb
      movsb
      add   di, bx
    ENDM

    ; Draw 16th row
    movsb
    movsb

    pop   si
    pop   di
    pop   ds
    ASSUME ds:DGROUP
    pop   bp
    ret
ENDP

ENDS
