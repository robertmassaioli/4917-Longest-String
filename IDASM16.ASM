;*********************************************************************
;**    PIC16Cxx MPASM Initialized Data Startup File, Version 0.02   **
;**    (c) Copyright 1997 Microchip Technology                      **
;**								    **
;**	v0.02	092600	dg	Added logic to set IRP bit for INDF **
;**				to transfer data to correct bank.   **
;*********************************************************************

;---------------- Environment variables --------------------;
   VARIABLE  TABLE_OFFSET = 0   ;Offset for reading from table of entries

;------------------------- Equates -------------------------;
;Register addresses
INDF           equ    0x00
PCL            equ    0x02
STATUS         equ    0x03
FSR            equ    0x04
PCLATH         equ    0x0A

;Bits within registers
Z              equ    0x02
C              equ    0x00
IRP            equ    0x07

;----------------External variables and labels--------------;
   EXTERN  _cinit     ;Start of const. data table

;-------------------------------------------------------------;
; COPY_ROM_WORD_TO_RAM                                        ;
;                                                             ;
;    Reads a 16-bit word stored in program memory as a pair of;
; retlw kk  instructions and stores the word in data memory   ;
; (low byte first). The macro also handles all paging and/or  ;
; bank switching involved.                                    ;
;                                                             ;
; Arguments:                                                  ;
;            RomAddr    Source address in program memory.     ;
;            RamAddr    Destination address in data memory.   ;
;-------------------------------------------------------------;
COPY_ROM_WORD_TO_RAM  MACRO  RomAddr, RamAddr

        PAGESEL  RomAddr        ;   Switch to correct ROM page,
        call     RomAddr        ; then read the low byte

        BANKSEL  RamAddr        ;   Switch to correct RAM bank,
        movwf    RamAddr        ; then write the low byte

        call     1 + RomAddr    ;   Read the high byte from ROM
        movwf    1 + RamAddr    ; and store it in RAM

                      ENDM
;-------------------------------------------------------------;

;***********************************************************;
VARIABLES   UDATA_OVR
;-----------------------------------------------------------;
; Data used for copying const. data into RAM
;
; Note:  All the locations in this section can be reused
;        by user programs. This can be done by declaring
;        a section with the same name and attribute:
;        i.e.
;             VARIABLES  UDATA_OVER          (in MPASM)
;        or
;            #pragma udata overlay VARIABLES (in MPLAB-C)
;-----------------------------------------------------------;
num_init             RES   2  ;Number of entries in init table
init_entry_from_addr RES   2  ;ROM address to copy const. data from
init_entry_to_addr   RES   2  ;RAM address to copy const. data to
init_entry_size      RES   2  ;Number of bytes in each init.section
init_entry_index     RES   2  ;Used to index through array of init. data
;-----------------------------------------------------------;

; ****************************************************************
_copy_idata_sec    CODE

; ****************************************************************
; * Copy initialized data from ROM to RAM                        *
; ****************************************************************
;
;   The values to be stored in initialized data are stored in
; program memory sections. The actual initialized variables are
; stored in data memory in a section defined by the IDATA directive
; in MPASM or automatically defined by MPLAB-C. There are 'num_init'
; such sections in a program. The table below has an entry for each
; section. Each entry contains the starting address in program memory
; where the data is to be copied from, the starting address in data
; memory where the data is to be copied, and the number of bytes to copy.
;   The startup code below walks the table, reading those starting
; addresses and counts, and copies the data from program to data memory.
;
;
;             +============================+
;  _cinit     | num_init (low)             |
;             +----------------------------+
;             | num_init (high)            |
;             +============================+
;             | init_entry_from_addr (low) |       IDATA (0)
;             +----------------------------+
;             | init_entry_from_addr (high)|
;             +----------------------------+
;             | init_entry_to_addr (low)   |
;             +----------------------------+
;             | init_entry_to_addr (high)  |
;             +----------------------------+
;             | init_entry_size   (low)    |
;             +----------------------------+
;             | init_entry_size   (high)   |
;             +============================+
;             |            .               |           .
;                          .                           .
;             |                            |
;             +============================+
;             | init_entry_from_addr (low) |       IDATA (num_init - 1)
;             +----------------------------+
;             | init_entry_from_addr (high)|
;             +----------------------------+
;             | init_entry_to_addr (low)   |
;             +----------------------------+
;             | init_entry_to_addr (high)  |
;             +----------------------------+
;             | init_entry_size   (low)    |
;             +----------------------------+
;             | init_entry_size   (high)   |
;             +============================+

;   Start of code that copies initialization
; data from program to data memory
copy_init_data

;   First read the count of entries (_cinit)
	COPY_ROM_WORD_TO_RAM   _cinit, num_init
        TABLE_OFFSET = TABLE_OFFSET + 2

;   For (num_init) do copy data for each initialization
; entry. Decrement 'num_init' every time and when it
; reaches 0 we are done copying initialization data
;
_loop_num_init
	BANKSEL num_init
	movf    num_init, W
	iorwf   num_init+1, 0
	btfss   STATUS, Z            ;   If num_init is not down to 0,
	goto    _copy_init_sec       ; then we have more sections to copy,
	goto    _end_copy_init_data  ; otherwise, we're done copying data.

;   For a single initialization section, read the
; starting addresses in both program and data memory,
; as well as the number of bytes to copy.
;
_copy_init_sec
	COPY_ROM_WORD_TO_RAM   TABLE_OFFSET + _cinit, init_entry_from_addr
        TABLE_OFFSET = TABLE_OFFSET + 2   ;Increment by 2 since it's a word
        COPY_ROM_WORD_TO_RAM   TABLE_OFFSET + _cinit, init_entry_to_addr
        TABLE_OFFSET = TABLE_OFFSET + 2   ;Increment by 2 since it's a word
	COPY_ROM_WORD_TO_RAM   TABLE_OFFSET + _cinit, init_entry_size
        TABLE_OFFSET = TABLE_OFFSET + 2   ;Increment by 2 since it's a word

;    Check 'init_entry_size'. If it's 0, then go
; to the next entry in the table (if it exits).
; If 'init_entry_size' is non-zero, then go ahead
; and copy the bytes.
;
_start_copying_data
        BANKSEL init_entry_size
        movf    init_entry_size, W
        iorwf   init_entry_size+1, W
        btfsc   STATUS, Z
        goto    _dec_num_init

;   Set up the destination address for the data in the FSR so
; we are prepared to copy data using indirect addressing
        BANKSEL init_entry_to_addr
        movf    init_entry_to_addr, W
        movwf   FSR

;   Read a single data byte by doing a long jump
; into the section in program memory
        goto   _Dummy2
_Dummy1
        movf   init_entry_from_addr+1, W
        movwf  PCLATH
        movf   init_entry_from_addr, W
        movwf  PCL
_Dummy2
        call   _Dummy1                    ;Puts return address on stack

;   Now write the data to RAM using indirect addressing
 	bcf     STATUS, IRP               ;Clear the IRP bit.
	movf   init_entry_to_addr+1, 1    ;Check if upper portion of
    btfss   STATUS, Z                 ;address is non-zero. If so, then
	bsf     STATUS, IRP               ;set the IRP bit.
	movwf   INDF

;  After copying one entry we need to:
;    1. Increment the program memory (source) address
;    2. Increment the data memory (destination) address
;    3. Decrement the init_entry_size

    BANKSEL init_entry_from_addr
	incf    init_entry_from_addr,1
    btfsc   STATUS, C
     incf    init_entry_from_addr+1,1

    BANKSEL init_entry_to_addr        ;Increment the address
	incf    init_entry_to_addr,1      ;_init_entry_to_addr
	btfsc   STATUS, C
     incf    init_entry_to_addr+1,1

    BANKSEL init_entry_size           ;Decrement the count
    movf    init_entry_size,1         ;_init_entry_size
    btfsc   STATUS, Z
     decf    init_entry_size+1,1
	decf    init_entry_size,1

	goto _start_copying_data          ;Back to do another section

_dec_num_init
        BANKSEL num_init
        movf    num_init,1
        btfsc   STATUS, Z
	decf    num_init+1,1
	decf    num_init, 1

        goto  _loop_num_init


_end_copy_init_data           ;We're done copying initialized data

   return

;   Must declare copy_init_data as GLOBAL to be able
; to call it from other assembly modules
   GLOBAL   copy_init_data

   END

