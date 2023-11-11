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
EGA_SEGMENT                     EQU 0A000h
SOLID_TILE_SEGMENT              EQU (EGA_SEGMENT + 400h)

;
; Interrupt numbers.
;
INT_VIDEO_SERVICE               EQU 10h


;
; Video Service subfunctions.
;
VSVC_SET_VIDEO_MODE             EQU 0h
VSVC_SET_ACTIVE_PAGE            EQU 5h
VSVC_GET_VIDEO_MODE             EQU 0Fh
VSVC_PALETTE_REGISTERS          EQU 10h


;
; Set/Get Palette Registers subfunctions.
;
PALREG_SET_ONE_COLOR            EQU 0h
PALREG_SET_BORDER_COLOR         EQU 1h


;
; EGA Sequencer I/O port and registers.
;
SEQUENCER_ADDR                  EQU 3C4h  ; During word access, high byte goes to 3c5h
SEQUENCER_DATA                  EQU 3C5h
SEQ_MAP_MASK                    EQU 2h


;
; EGA Graphics Controller I/O port and registers.
;
GRAPHICS_1_2_ADDR               EQU 3CEh  ; During word access, high byte goes to 3cfh
GRAPHICS_DATA                   EQU 3CFh
GFX_ENABLE_SET_RESET            EQU 1h
GFX_DATA_ROTATE                 EQU 3h
GFX_READ_MAP_SELECT             EQU 4h
GFX_MODE                        EQU 5h
GFX_COLOR_DONT_CARE             EQU 7h
GFX_BIT_MASK                    EQU 8h


;
; Other EGA registers
;
INPUT_STATUS_1_ADDR             EQU 3DAh


SEGMENT _TEXT


;
; Global storage in the code segment.
;

; Unknown data - possibly part of ProGraphx Toolbox, but doesn't seem to be
; used
db 0Eh dup(0), 0Ch dup(0), 0FFh, 7Fh, 3Fh, 1Fh, 0Fh, 7, 3, 1, 80h
db 40h, 20h, 10h, 8, 4, 2, 1, 9 dup(0), 3 dup(0), 23 dup(0Ah)

; ProGraphx Toolbox watermark string
db 0Dh,0Ah,'Version 1.0 EGA/VGAProGraphx EGA/VGA Toolbox',0Dh,0Ah,1Ah

; EGA memory page to be drawn into (back buffer)
gfxCurrentDrawPage dw 0

; More unknown data
db 1, 4 dup(0), 27h, 3 dup(0), 0C7h, 3 dup(0), 3Fh, 1


;
; Routines
;


;
; Initialze EGA card in a graphical video mode as specified
;
; Unused in the game.
;
; type (word): Type of graphics mode to enter. This is _not_ a BIOS video mode,
;     but a custom enumeration with the following values:
;     0 - 320x200 16 colors
;     1 - 640x350 4/16 colors (depends on memory installed on card)
;     2 - 640x480 16 colors (requires VGA card)
; Returns: Nothing
; Registers destroyed: AX
;
PROC _SetUpGraphicsMode FAR @@type:WORD
    PUBLIC _SetUpGraphicsMode
    push  bp
    mov   bp, sp

    mov   ax, [@@type]
    cmp   al, 0
    jnz   check1
    mov   al, 0Dh ; mode Dh - 320x200 16 color EGA
    jmp   short do_int
    nop

check1:
    cmp   al, 1
    jz    do_1
    xor   ah, ah
    mov   al, 12h ; mode 12h - 640x480 16 color VGA
    jmp   short do_int
    nop

do_1:
    mov   al, 10h ; mode 10h - 640x350 4/16 color EGA

do_int:
    int   INT_VIDEO_SERVICE

    pop   bp
    ret
ENDP


;
; Set the video mode to the specified mode number and initialize the EGA card.
;
; A similar function exists in the Cosmo and Duke Nukem 2 code bases.
;
; mode (word): The BIOS video mode to enter. Only the low byte is used.
; Returns: Nothing
; Registers destroyed: AX
;
PROC _SetVideoMode FAR @@mode_num:WORD
    PUBLIC _SetVideoMode
    push  bp
    mov   bp, sp

    ; Change video mode via BIOS video service interrupt [EGA, pg. 104].
    mov   ax, [@@mode_num]
    xor   ah, ah ; set AH to VSVC_SET_VIDEO_MODE
    int   INT_VIDEO_SERVICE

    pop   bp
    ret
ENDP


;
; Load the video border (overscan) register with the specified color value.
;
; A similar function exists in the Cosmo and Duke Nukem 2 code bases.
;
; Returns: Nothing
; Registers destroyed: AX, BX
;
PROC _SetBorderColor FAR @@color_value:WORD
    PUBLIC _SetBorderColor
    push  bp
    mov   bp, sp

    ; Change border color via BIOS video service interrupt [EGA, pg. 104].
    mov   ah, VSVC_PALETTE_REGISTERS
    mov   al, PALREG_SET_BORDER_COLOR
    mov   bx, [@@color_value]
    mov   bh, bl             ; Value in BL is not used again
    int   INT_VIDEO_SERVICE

    pop   bp
    ret
ENDP


;
; Reinitialize video card with the current video mode
;
; This resets video memory, restores the default palette etc.
;
; Returns: Nothing
; Registers destroyed: AX
;
PROC _ResetVideo FAR
    PUBLIC _ResetVideo
    mov  ah, VSVC_GET_VIDEO_MODE
    int  INT_VIDEO_SERVICE

    xor  ah,ah ; set AH to VSVC_SET_VIDEO_MODE
    int  INT_VIDEO_SERVICE

    ret
ENDP


;
; Load one video palette register with the specified color value.
;
; An identical function exists in the Cosmo codebase.
;
; The color value is a byte with the highest two bits unused. The exact meaning
; of the bits changes depending on the video mode and the type of display
; connected to the adapter. IBM had three different display units that used
; similar 9-pin connectors:
; - IBM Monochrome Display
; - IBM Color Display
; - IBM Enhanced Color Display
;
; The three display types were electrically interchangeable, and the EGA
; hardware was capable of driving any of the three displays provided it was set
; to a video mode that was supported by that display. Since the signal at each
; pin could be either on or off (with no intermediate levels), the two signal
; pins on the Monochrome Display supported 4 different shades of mono, the four
; signal pins on the Color Display supported 16 colors, and the six signal pins
; on the Enhanced Color Display supported 64 colors. There is a direct mapping
; between the individual bits in a color value and the signals on the display
; connector pins, as shown on the abbreviated pinouts [ECD, pg. 6]:
;
;   Pin | Monochrome  | Color         | Enhanced Color  | Color Value Bit
;   ----+-------------+---------------+-----------------+----------------
;     5 | --          | Blue          | Blue            | 00.....X
;     4 | --          | Green         | Green           | 00....X.
;     3 | --          | Red           | Red             | 00...X..
;     7 | Mono Signal | -- (Reserved) | Blue Intensity  | 00..X...
;     6 | Intensity   | Intensity     | Green Intensity | 00.X....
;     2 | -- (Ground) | -- (Ground)   | Red Intensity   | 00X.....
;
; NOTE: The base Red/Green/Blue signals contribute 67% of the power of a color
; channel, and the corresponding Intensity signal(s) provide the remaining 33%.
; Some sources refer to the Intensity signals as "least significant" due to the
; amount of output they generate, but this is confusing from the perspective of
; color value bit packing and we will never say it that way here.
;
; The Enhanced Color Display supported two modes [ECD, pg. 3]:
; - Mode 1: 200 lines, 15.75 kHz HSync rate, positive VSync pulse
; - Mode 2: 350 lines, 21.8 kHz HSync rate, negative VSync pulse
;
; The display used the polarity of the Vertical Sync pulse to determine which
; mode to use. In display mode 2, all six color inputs contributed to the
; picture and 64 colors were available for use. In mode 1, the Red Intensity and
; Blue Intensity inputs to the display were ignored, and the Green Intensity
; signal was applied across all three color channels [ECD, pg. 4]. This limited
; the display to 16 colors using the same RGBI pinout the Color Display used.
; Mode 1 also emulated the Color Display's handling of the color brown: When
; RGBI 1100 was received, the display fudged *just* the Green Intensity bit on
; to avoid an unpleasant dark yellow [ECD, pg. 4].
;
; This game uses video mode Dh exclusively -- a 200-line mode -- so there is
; only one intensity bit that can visibly change the screen color and it is not
; contiguous with the R/G/B bits. The 64 color values are really 16 distinct
; display colors, each repeated four times. The effective bit positions are:
;   Bits     | Meaning
;   ---------+--------
;   .......X | Blue
;   ......X. | Green
;   .....X.. | Red
;   ....0... | Not Used
;   ...X.... | Intensity
;   000..... | Not Used
;
; A silver lining to this is that, with the default EGA palette loaded, the bits
; in a palette register index correspond to bits in the color value, which match
; the RGBI signals being shown on the display. This is what allows EGA memory
; planes 0123 to be thought of as BGRI instead. If the sequence were changed or
; custom-mixed colors were used, this reasonable mental model would fall apart.
;
; palette_index (word): The palette register index (0..15). Only the low byte is
;     used.
; color_value (word): The color value to program into the register (0..63). Only
;     the low byte is used.
; Returns: Nothing
; Registers destroyed: AX, BX
;
PROC _SetPaletteRegister FAR @@palette_index:WORD, @@color_value:WORD
    PUBLIC _SetPaletteRegister
    push  bp
    mov   bp, sp

    ; Change one palette register via BIOS video service interrupt [EGA, pg.
    ; 105]. Two byte-sized subfunction numbers are being loaded in one MOV
    ; into AX.
    mov   ax, (VSVC_PALETTE_REGISTERS SHL 8) OR PALREG_SET_ONE_COLOR
    mov   bl, [BYTE PTR @@palette_index]
    mov   bh, [BYTE PTR @@color_value]
    int   INT_VIDEO_SERVICE

    pop   bp
    ret
ENDP


;
; Draw a single 16x16 pixel solid tile to the current draw page.
;
; Cosmo and Duke Nukem 2 have a similar function, but work on 8x8 tiles instead.
;
; This procedure draws non-transparent tiles that are part of the game map and
; backdrops, as well as various UI elements for the HUD and menus.
;
; Source data is read from EGA memory at SOLID_TILE_SEGMENT:src_offset.
; The destination address is drawPageSegment:dest_offset.
; The EGA *must* be in latched write mode for this to work correctly.
;
; Each tile is a 16x16 pixel square. Each 16-pixel tile row occupies two bytes
; of EGA address space (1 bit per pixel), for a total of 32 bytes per tile.
; These 32 bytes are stored sequentially in the source memory, or at 40-byte
; intervals in the destination memory.
;
; Within the EGA, each memory read/write operation is quadrupled across the
; four color planes. Although only 32 bytes of address space are handled during
; each call to this procedure, 128 bytes of physical memory are copied
; internally.
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
    jz    @@drawing_to_first_page
    ; When drawing to the 2nd page, add 200h to the destination segment.
    ; Otherwise, skip as DX already holds the correct segment.
    add   dx, 200h
@@drawing_to_first_page:

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

    ; Draw 15 rows of tile pixels.
    REPT 15
        ; Each MOVSB reads one byte from the source address (DS:SI), writes it
        ; to the destination address (ES:DI), and increments SI and DI by one.
        ; As a result of the read, the EGA internally reads 4 bytes, one from
        ; each color plane, and stores them in the hardware's internal latch
        ; registers.
        ; The subsequent write triggers writing these 4 bytes to the color
        ; planes at the destination address, all 4 planes in parallel.
        ; The byte written by the CPU is ignored, everything happens internally
        ; in the graphics card.
        movsb
        movsb

        ; DI was already incremented by 2 thanks to the two MOVSB. Adding 38
        ; makes 40 bytes in total, which puts us at the very next row of pixels
        ; at the destination (the draw page).
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


;
; Copy 30 rows of 16 pixels from the given position, mirrored vertically
;
; This procedure copies a 16x30 pixel block of data from video memory to video
; memory, applying vertical mirroring and skipping every other row in the source
; data.
;
; Requires latched write mode!
;
; x (word): Horizontal screen position, in bytes
; y (word): Vertical screen position, in pixels
; src_offset (word): Offset in bytes for reading the source data. Should be a
;       multiple of 40 for meaningful results.
; Returns: Nothing
; Registers destroyed: AL, DX, ES
;
PROC _ApplyMirrorEffect FAR @@x:WORD, @@y:WORD, @@src_offset:WORD
    PUBLIC _ApplyMirrorEffect
    push    bp
    mov     bp, sp
    push    ds
    push    di
    push    si

    ; Set up source and destination segments (both in EGA memory)
    mov   dx, EGA_SEGMENT
    mov   ax, [gfxCurrentDrawPage]
    cmp   al, 0
    jz    @@drawing_to_first_page
    ; When drawing to the 2nd page, add 200h to the destination segment.
    ; Otherwise, skip as DX already holds the correct segment.
    add   dx, 200h
@@drawing_to_first_page:
    mov     es, dx
    mov     ds, dx
    ASSUME ds:NOTHING

    ; Set AX = y * 40. To avoid a costly MUL instruction, the expression is
    ; rearranged into (y * 4 + y) * 8, which can be implemented via cheap
    ; bit-shifts instead.
    mov     bx, [@@y]
    mov     ax, bx
    shl     ax, 1
    shl     ax, 1
    add     ax, bx
    shl     ax, 1
    shl     ax, 1
    shl     ax, 1

    ; Set DI = y * 40 + x + 80. This is 2 pixel rows below the position given
    ; by x and y. The mirrored rows are written starting from here.
    mov     bx, [@@x]
    add     ax, bx
    add     ax, 80
    mov     di, ax

    ; Set SI = y * 40 + x - 40 - src_offset. This is 1 pixel row plus the
    ; specified src_offset above the position given by x and y. The data for
    ; the mirrored rows is read starting from here.
    sub     ax, 120
    sub     ax, [@@src_offset]
    mov     si, ax

    mov     bx, 38
    mov     ax, 82

    REPT 29
        ; Copy 16 pixels (1 byte for 8 pixels). Each MOVSB increments SI and DI
        ; by one.
        ; The actual copying of data happens within the EGA card, thanks to the
        ; latches.
        movsb
        movsb

        ; Add 38 more bytes to DI, to make it point to the next pixel row
        ; further down (since 40 bytes = 1 pixel horizontally)
        add     di, bx

        ; Subtract 82 from SI. This undoes the increments done by the two MOVSB
        ; above, and then moves the pointer up by two rows of pixels, skipping
        ; one row of the source data.
        sub     si, ax
    ENDM

    ; Copy the 30th row's pixels.
    movsb
    movsb

    pop     si
    pop     di
    pop     ds
    ASSUME ds:DGROUP
    pop     bp
    ret
ENDP


;
; Wait for the beginning of the CRT's next vertical blanking interval
;
; Returns: Nothing
; Registers destroyed: AX, DX
;
PROC _AwaitVblank
    PUBLIC _AwaitVblank
    push  bp
    mov   bp, sp
    push  ds
    push  di
    push  si

    mov   dx, INPUT_STATUS_1_ADDR

    ; First, wait for a currently ongoing vertical retrace to end.  Reading the
    ; Input Status #1 register returns a value with bit 3 ( = 8) indicating if
    ; the display is currently in the vertical blanking interval. Here, we keep
    ; reading the status register until the bit becomes 0.
await_vblank_end:
    in    al, dx
    and   al, 8
    jnz   await_vblank_end

    ; Now wait for the begin of the next vertical retrace.  Same thing as above,
    ; but we keep looping as long as the bit is not set (i.e., is 0).
await_vblank_begin:
    in    al, dx
    and   al, 8
    jz    await_vblank_begin

    pop   si
    pop   di
    pop   ds
    pop   bp
    ret
ENDP


;
; Draw a single 16x16 sprite tile to the draw page, with transparency
;
; The source data must be 160 bytes, organized into 16 10-byte lines. Each
; line is expected to be a pair of two 8-pixel spans, encoded as 5 bytes:
; First the transparency mask, then 4 color planes in order blue, green, red,
; and intensity.
;
; src (far pointer): Memory address of the first byte of source data
; x (word): Horizontal screen position, in bytes
; y (word): Vertical screen position, in pixels
; Returns: Nothing
; Registers destroyed: AX, BX, CX, DX, ES
;
PROC _BlitMaskedTile_16x16 FAR @@src:FAR PTR, @@x:WORD, @@y:WORD
    PUBLIC _BlitMaskedTile_16x16
    push  bp
    mov   bp, sp
    push  ds
    push  di
    push  si

    ; Load source data pointer into DS:SI
    lds   si, [@@src]

    mov   dx, EGA_SEGMENT
    mov   es, dx

    ; Set AX = y * 40. To avoid a costly MUL instruction, the expression is
    ; rearranged into (y * 4 + y) * 8, which can be implemented via cheap
    ; bit-shifts instead.
    mov   bx, [@@y]
    mov   ax, bx
    shl   ax, 1
    shl   ax, 1
    add   ax, bx
    shl   ax, 1
    shl   ax, 1
    shl   ax, 1

    ; Set BX = x + y * 40, this is our destination address in EGA memory
    mov     bx, [@@x]
    add     bx, ax

    ; Adjust destination pointer according to current draw page
    mov   ax, [gfxCurrentDrawPage]
    cmp   al, 0
    jz    @@drawing_to_first_page
    mov   cx, ax ; Has no effect
    add   bx, 2000h
@@drawing_to_first_page:

    ; Prepare EGA's Sequencer to receive writes to the Map Mask register, this
    ; controls which planes are written to by subsequent writes
    mov   dx, SEQUENCER_ADDR
    mov   al, SEQ_MAP_MASK
    out   dx, al

    ; Run the following loop 16 times to draw 16 lines
    mov   cx, 16

@@repeat:
    REPT 2
        ; Prepare register write below
        mov   dx, GRAPHICS_1_2_ADDR

        ; Read bit mask for the next 8 pixels. This instruction reads a byte
        ; from DS:SI into AL and increments SI.
        lodsb

        mov   ah, GFX_BIT_MASK
        xchg  ah, al ; AL holds the bit mask thanks to the LODSB above

        ; This is a word-sized out, so it writes AL to GRAPHICS_1_2_ADDR and AH
        ; to GRAPHICS_DATA. This configures the EGA's Bit Mask register with
        ; the value we've read from the source data, making all subsequent
        ; writes ignore bit positions that have 0s in the bit mask.
        out   dx, ax

        ; Prepare for selecting planes. The EGA's Sequencer is still programmed
        ; to receive values for the Map Mask register with each write to the
        ; Sequencer Data register, thanks to the preparation above.
        mov   dx, SEQUENCER_DATA

        IRP mask, <1, 2, 4, 8>
            ; Select plane for writing
            mov   al, mask
            out   dx, al

            ; Read next byte from source data...
            lodsb

            ; ...and write it to video memory. All 4 writes go to the same
            ; address, but end up in different planes thanks to the Map Mask
            ; manipulation right before.
            ; This could just as well be a MOV instruction, XCHG was most
            ; likely used as a size optimization as its encoded form is
            ; smaller.
            xchg  al, [es:bx]
        ENDM

        ; Go to the next destination byte to target the next 8 pixels in the
        ; draw page
        inc   bx
    ENDM

    ; Skip down by one pixel so we can write the next line (40 bytes is one
    ; full row of pixels in EGA address space)
    add   bx, 38
    loop  @@repeat

    ; Reset Map Mask to enable writing to all planes simultaneously
    mov   al, 0Fh
    out   dx, al

    ; Reset Bit Mask to enable writing all bit positions
    mov   dx, GRAPHICS_1_2_ADDR
    mov   ax, 0FF08h
    out   dx, ax

    pop   si
    pop   di
    pop   ds
    pop   bp
    ret
ENDP


;
; Draw a single 8x8 sprite tile to the draw page, with transparency
;
; Used for fonts/text rendering.
;
; TODO: More documentation
;
; src (far pointer): Memory address of the first byte of source data
; x (word): Horizontal screen position, in bytes
; y (word): Vertical screen position, in pixels
; Returns: Nothing
; Registers destroyed: AX, BX, CX, DX, ES
;
PROC _BlitMaskedTile_8x8 FAR @@src:FAR PTR, @@x:WORD, @@y:WORD
    PUBLIC _BlitMaskedTile_8x8
    push  bp
    mov   bp, sp
    push  ds
    push  di
    push  si

    lds   si, [@@src]

    mov   dx, EGA_SEGMENT
    mov   es, dx

    ; Set AX = y * 40. To avoid a costly MUL instruction, the expression is
    ; rearranged into (y * 4 + y) * 8, which can be implemented via cheap
    ; bit-shifts instead.
    mov   bx, [@@y]
    mov   ax, bx
    shl   ax, 1
    shl   ax, 1
    add   ax, bx
    shl   ax, 1
    shl   ax, 1
    shl   ax, 1

    ; Set BX = x + y * 40
    mov     bx, [@@x]
    add     bx, ax

    mov   ax, [gfxCurrentDrawPage]
    cmp   al, 0
    jz    @@drawing_to_first_page
    mov   cx, ax
    add   bx, 2000h
@@drawing_to_first_page:

    mov   dx, SEQUENCER_ADDR
    mov   al, SEQ_MAP_MASK
    out   dx, al

    mov   cx, 8

@@repeat:
    mov   dx, GRAPHICS_1_2_ADDR

    lodsb

    mov   ah, GFX_BIT_MASK
    xchg  ah, al
    out   dx, ax

    mov   dx, SEQUENCER_DATA

    IRP mask, <1, 2, 4, 8>
        mov   al, mask
        out   dx, al
        lodsb
        xchg  al, [es:bx]
    ENDM

    add   bx, 40
    loop  @@repeat

    mov   al, 0Fh
    out   dx, al

    mov   dx, GRAPHICS_1_2_ADDR
    mov   ax, 0FF08h
    out   dx, ax

    pop   si
    pop   di
    pop   ds
    pop   bp
    ret
ENDP


;
; Draw a single 8x8 sprite tile to the draw page, without transparency
;
; Used for fonts/text rendering.
;
; TODO: More documentation
;
; src (far pointer): Memory address of the first byte of source data
; x (word): Horizontal screen position, in bytes
; y (word): Vertical screen position, in pixels
; Returns: Nothing
; Registers destroyed: AX, BX, CX, DX, ES
;
PROC _BlitSolidTile_8x8 FAR @@src:FAR PTR, @@x:WORD, @@y:WORD
    PUBLIC _BlitSolidTile_8x8
    push  bp
    mov   bp, sp
    push  ds
    push  di
    push  si

    lds   si, [@@src]

    mov   dx, EGA_SEGMENT
    mov   es, dx

    ; Set AX = y * 40. To avoid a costly MUL instruction, the expression is
    ; rearranged into (y * 4 + y) * 8, which can be implemented via cheap
    ; bit-shifts instead.
    mov   bx, [@@y]
    mov   ax, bx
    shl   ax, 1
    shl   ax, 1
    add   ax, bx
    shl   ax, 1
    shl   ax, 1
    shl   ax, 1

    ; Set BX = x + y * 40
    mov     bx, [@@x]
    add     bx, ax

    mov   ax, [gfxCurrentDrawPage]
    cmp   al, 0
    jz    @@drawing_to_first_page
    mov   cx, ax
    add   bx, 2000h
@@drawing_to_first_page:

    mov   dx, SEQUENCER_ADDR
    mov   al, SEQ_MAP_MASK
    out   dx, al

    mov   cx, 8

@@repeat:
    lodsb

    mov   dx, SEQUENCER_DATA

    IRP mask, <1, 2, 4, 8>
        mov   al, mask
        out   dx, al
        lodsb
        xchg  al, [es:bx]
    ENDM

    add   bx, 40
    loop  @@repeat

    mov   al, 0Fh
    out   dx, al

    mov   dx, GRAPHICS_1_2_ADDR
    mov   ax, 0FF08h
    out   dx, ax

    pop   si
    pop   di
    pop   ds
    pop   bp
    ret
ENDP


;
; Unknown function
;
; Unused in the game.
;
PROC _Unknown FAR @@arg:WORD
    PUBLIC _Unknown
    push    bp
    mov     bp, sp
    push    ds
    push    di
    push    si

    mov     ax, 40h
    mov     es, ax
    mov     dx, [es:63h]
    add     dl, 6

loc_5BE:
    in      al, dx
    test    al, 8
    jnz     loc_5BE

loc_5C3:
    in      al, dx
    test    al, 8
    jz      loc_5C3
    sub     dl, 6
    mov     ax, [@@arg]
    mov     bh, ah
    and     bh, 1
    mov     cl, 4
    shl     bh, cl
    mov     ah, al
    mov     al, 18h
    out     dx, ax
    mov     ah, 1Fh
    and     ah, 0EFh

    or      ah, bh
    mov     al, 7
    out     dx, ax

    pop     si
    pop     di
    pop     ds
    pop     bp
    ret
ENDP


;
; Select the video page to draw on (aka backbuffer)
;
; A similar function exists in the Cosmo and Duke Nukem 2 code bases.
;
; Although higher page numbers are accepted and will store a sensible result,
; pages beyond number 1 are used for tile storage and writing to them will
; corrupt the graphics.
;
; page_num (word): Page number to write to (0..1).
; Returns: Nothing
; Registers destroyed: AX, and those destroyed by UpdateDrawPageSegment
;
PROC _SetDrawPage FAR @@page_num:WORD
    PUBLIC _SetDrawPage
    push  bp
    mov   bp, sp

    mov   ax, [@@page_num]
    mov   [gfxCurrentDrawPage], ax

    pop   bp
    ret
ENDP


;
; Change the video page that is currently displayed on the screen.
;
; A similar function exists in the Cosmo and Duke Nukem 2 code bases.
;
; Although higher page numbers are accepted and will behave sensibly, pages
; beyond number 1 are used for tile storage and they will render as garbage if
; sent to the screen.
;
; page_num (word): Page number to show (0..n). Maximum page number varies based
;     on the video mode and installed adapter memory, but common values for the
;     EGA are 0, 1, 3, and 7. Only the low byte is used.
; Returns: Nothing
; Registers destroyed: AX
;
PROC _SetDisplayPage FAR @@page_num:WORD
    PUBLIC _SetDisplayPage
    push  bp
    mov   bp, sp

    mov   ax, [@@page_num]
    mov   ah, VSVC_SET_ACTIVE_PAGE
    int   INT_VIDEO_SERVICE

    pop   bp
    ret
ENDP

ENDS
