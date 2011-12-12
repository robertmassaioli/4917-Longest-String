; Author: Robert Masasioli
; Date: 11/12/2011
;
; Prelude:
; Beware he who stumbles upon this file: it is a little bit of a mess but it does have a structure.
; I have attempted to extract as many of the processes into their own functions as I can but please keep in mind
; that I do not have a stack to push and pop variables into when I call these functions so all of my registers have
; been carefully chosen to avoid conflicts. I know that it goes against the whole point of abstraction but there was
; nothing I can do, this cheap microcontroller only has an 8 deep stack that is reserved purely for return values.
;
; The parts required for this kit are not that expensive, you can buy the microcontroller directly from Microchip for a dollar
; and this Assembly code should be runnable on most of their microcontrollers.
;
; Hardware Connections
;  The only device that is connected to this PIC Micro is a LCD Screen because that is all that will fit. It only leaves one
;  output pin free. It would not be so bad if I got an LCD Screen that accepted 4-bit instead of 8-bit data lines. However
;  that means that RC0-5 (6-bits) are connected to the LCD DB0-5 and RA0-1 are connected to LCD DB6-7. That leaves:
;   - RA2 => LCD E
;   - RC4 => LCD RS
;   - RA5 => LCD RW
;  The only pin that leaves free on the 16f688 in RC5 which can be used as an LED status light maybe.

; minus by one because it is zero based
prog_len 		equ (4 - 1)
timeout_high 	equ 0x04
timeout_low 	equ 0x00

; LCD Defines
LCD_E 	set RA2
LCD_RS 	set RA4
LCD_RW 	set RA5

LCD_DELAY_START equ 0xEB 	; 30ms
LCD_DELAY_MED   equ 0x0C 	; 1.5ms

LCD_CONTROL_DELAY 	equ 0x13
LCD_WRITE_DELAY 	equ 0x15

; LCD Control Commands
LCD_CLEAR_SCREEN 	equ b'00000001'
LCD_RETURN_HOME 	equ b'00000010'

 LIST P=16f688
 processor 16f688
 include <p16f688.inc>
 
 extern copy_init_data

; The WDT needs to be off because we do not want it resetting on us.
; INTOSCIO means it will run at 8MHz
 __CONFIG _WDT_OFF & _INTOSCIO

 cblock 0x20
	R0
	R1 
	PC
	TEMP
	CPROG:16	; The CURRENT program being run
	PROG:16
	CCOUNT:4	; The number of characters printed.
	LPROG:8
	LCOUNT:4 	; The Longest number of characters ever printed
	TIMEOUT:2
	DELAY
	LCDOUT
	LCDCONTROL
 endc
 
;;;;;;
;; Macros
;;;;;;

; keep in mind that macros need to be declared before they are used

; increments the PC and wraps it at the 4-bit boundary too
increment_pc macro
 incf PC, 1
 movlw 0x0F
 andwf PC, 1
 endm

wrap_r0 macro
 movlw 0x0F
 andwf R0, 1
 endm
 
wrap_r1 macro
 movlw 0x0F
 andwf R1, 1
 endm

; loads the current value into w 
lcw macro
 movlw PROG
 addwf PC, 0
 movwf FSR
 movf INDF, 0
 endm

; The start of the program
 org 0x0
 goto main
 
; Interrupts are handled here
 org 0x4
 banksel INTCON
 btfss INTCON, T0IF
  goto tmr0_interrupt_end
  
 movf DELAY, F
 btfss STATUS, Z
  decf DELAY, F
 
 bcf INTCON, T0IF
 
tmr0_interrupt_end:
 banksel PC
 retfie

main:
 pagesel setup_hardware
 call setup_hardware
 banksel LCDCONTROL
 bcf LCDCONTROL, 0
 
 movlw 'R'
 banksel LCDOUT
 movwf LCDOUT
 pagesel lcd_write_data_busy
 call lcd_write_data_busy
 
 movlw 'O'
 banksel LCDOUT
 movwf LCDOUT
 pagesel lcd_write_data_busy
 call lcd_write_data_busy
 
 pagesel copy_init_data
 call copy_init_data
 
 banksel hex_st
 movlw hex_st
 movwf FSR
 movlw 0xA
 addwf FSR, F
 bankisel hex_st
 movf INDF, W
 banksel LCDOUT
 movwf LCDOUT
 pagesel lcd_write_data_busy
 call lcd_write_data_busy
 goto $
 
 call print_status

 ; set all of the program memory to zero
 clrf PC
 movlw CPROG
 movwf FSR
 clrw
set_to_w_loop:
 movwf INDF
 incf FSR, 1
 incf PC, 1
 btfss PC, 4
  goto set_to_w_loop

 ; clear LCOUNT
 movlw LCOUNT
 movwf FSR
 movlw 0x4
 movwf TEMP
 call clear_multibyte

; make it not all zeros
start_calc:
 movlw CPROG
 movwf FSR
 movlw prog_len
 addwf FSR, F
 movlw 0x1
 movwf INDF

start_calc_loop:
 ; check to see if it has all zeroed
 movlw CPROG
 movwf FSR
 movlw prog_len
 addwf FSR, F
 movf INDF, W
 btfsc STATUS, Z
  goto end_calc_loop

inner_loop:
 ; now run the program to see it go
 call run_program
 ; now check to see if this program output more characters than any previous ones 
 ; LCOUNT - CCOUNT will tell the story if there is a carry at the end then we know that CCOUNT was bigger
 movf    CCOUNT, W
 subwf   LCOUNT, W  
 movf    (CCOUNT+1), W
 btfss   STATUS, C
 incfsz  (CCOUNT+1), W
 subwf   (LCOUNT+1), W
 movf    (CCOUNT+2), W
 btfss   STATUS, C
 incfsz  (CCOUNT+2), W
 subwf   (LCOUNT+2), W
 movf    (CCOUNT+3), W
 btfss   STATUS, C
 incfsz  (CCOUNT+3), W
 subwf   (LCOUNT+3), W
 btfsc STATUS, C
  goto no_update
 
 ; It is better than the previous results, update 
 call results_to_lprog
 ; Write the current best result to the screen
 call print_status
 
no_update:
 ; now add one to the program
 movlw CPROG
 movwf FSR
 clrf TEMP
prog_inc_loop:
 incf INDF, F
 movlw 0x0F
 andwf INDF, F
 btfss STATUS, Z
  goto start_calc_loop
 incf FSR, F
 movf TEMP, W
 sublw prog_len
 btfsc STATUS, Z
  goto start_calc_loop
 incf TEMP, F
 goto prog_inc_loop
 
end_calc_loop:
 goto fin

fin: 
 ; now we are done, you are free to loop forever doing nothing
 ;call print_status
 goto $

;;;;;;
;; Helper Functions
;;;;;;

; setup_hardware - function
; Purpose:
;  This function sets up all of the hardware in the device.
setup_hardware:
 ; Set all pins to be output pins
 ; WARNING: RA3 cannot be set to output, it will remain as an input pin...WTF right?
 banksel PORTA
 clrf PORTA
 clrf PORTC
 ; Digital I/O
 movlw 0x7
 movwf CMCON0
 banksel ANSEL
 clrf ANSEL
 ; Set all ports as outputs
 banksel TRISA
 clrf TRISA
 clrf TRISC
 
 ; Start the TMR0
 banksel OPTION_REG
 bcf OPTION_REG, T0CS
 
 ; Disable interrupts
 banksel INTCON
 bcf INTCON, GIE
 
 ; setup the lcd screen
 call lcd_setup
 
 return
 
; setup_lcd - function
; Purpose:
;  This function sets up the lcd to be used correctly.
lcd_setup:
 banksel DELAY
 movlw LCD_DELAY_START
 movwf DELAY
 call lcd_delay
 
 ; setup the lcd
 bsf LCDCONTROL, 0  ; these are all control messages
 
 ; Two Line mode with small font
 movlw b'00111000'
 movwf LCDOUT
 call lcd_write_data
 
 movlw LCD_CONTROL_DELAY
 movwf DELAY 		
 call lcd_short_delay
 
 ; Display On, Cursor Off, Blink Off
 movlw b'00001101'
 movwf LCDOUT
 call lcd_write_data
 
 movlw LCD_CONTROL_DELAY
 movwf DELAY
 call lcd_short_delay
 
 ; Clear the display
 movlw LCD_CLEAR_SCREEN
 movwf LCDOUT
 call lcd_write_data
 
 movlw LCD_DELAY_MED
 movwf DELAY
 call lcd_delay
 
 ; set the entry mode to increment, no shift
 movlw b'00000110'
 movwf LCDOUT
 call lcd_write_data
 
 return
 
lcd_wait_busy:
 ; read the ports
 banksel TRISA
 movlw b'11'
 iorwf TRISA, F
 banksel TRISC
 movlw 0xFF
 movwf TRISC
 
 ; now start reading the line
 banksel PORTA
 bcf PORTA, LCD_RS
 bsf PORTA, LCD_RW
 bsf PORTA, LCD_E
 
 nop ; just in case nop
 nop
 nop
 
 btfsc PORTA, RA1
  goto $-1
 
 bcf PORTA, LCD_E
 return

lcd_write_data_busy:
 pagesel lcd_wait_busy
 call lcd_wait_busy
 pagesel lcd_write_data
 call lcd_write_data
 return

; lcd_write_data - function
; Purpose
;  The purpose of this function is to write the data in LCDOUT to the LCD
;  If the first bit of LCDCONTROL is 1 then it will be a control message and if not then it will be a write message
lcd_write_data:
 ; setup ports
 banksel TRISA
 clrf TRISA
 banksel TRISC
 clrf TRISC
 
 ; setup the message
 banksel LCDOUT
 movf LCDOUT, W
 movwf PORTC
 
 bcf PORTA, RA0
 btfsc LCDOUT, 6
  bsf PORTA, RA0
 
 bcf PORTA, RA1
 btfsc LCDOUT, 7
  bsf PORTA, RA1
 
 bcf PORTA, LCD_RW
 
 ; If it is a control message or not then set it correctly
 btfss LCDCONTROL, 0
  bsf PORTA, LCD_RS
 btfsc LCDCONTROL, 0
  bcf PORTA, LCD_RS
  
 nop
 
 ; now enable the message send and delay the appropriate time
 bsf PORTA, LCD_E
 nop ; we only need a 230ns delay which is less than one instruction
  ; now turn of the enable
 bcf PORTA, LCD_E
 bcf PORTA, LCD_RS
 bcf PORTA, LCD_RW
 
 ; wait for the device to recognise the message
 nop
 nop
 
 return

; lcd_short_delay - function
; This has a short delay measured in instructions. It takes 2c to call into this function. 2c to leave this function.
; It also uses: (delay - 1) * 4 + 3 in general operation.
; Therefore, Total Delay: 7 + 4(delay - 1)
lcd_short_delay:
 decf DELAY, F			; 1c
 btfss STATUS, Z		; 2c if skip and, 1c if not
  goto lcd_short_delay  ; 2c every time
  
 return					; 2c every time

; lcd_delay - This function expects to wait a set amount of time before being delayed.
; You just set the DELAY registers to the right values and it just works.
lcd_delay:
 ; turn on TMR0 Interrupts
 banksel INTCON
 bcf INTCON, T0IF
 bsf INTCON, T0IE
 bsf INTCON, GIE
 
 ; clear the timer
 banksel TMR0
 clrf TMR0
 
 ; poll until the delay variable is 0
 banksel DELAY
lcd_delay_poll:
 nop
 nop
 movf DELAY, F
 btfss STATUS, Z
 goto lcd_delay_poll
 
 ; turn off TMR0 Interrupts
 banksel INTCON
 bcf INTCON, GIE
 bcf INTCON, T0IE
 return

; current_to_prog - function
; input values:
;  CPROG
; used values could end as anything:
;  TEMP
;  PC
;  R0
;  R1
; return values:
;  none - WREG undefined
; Purpose: 
;  The purpose of this function is to copy the current program into prog which is the input to run_program.
;  Thus its entire purpose is to get run_program prepared. It might even be expeciant to call it at the beginning
;  of run_program so that the user does not need to be aware that it even exists.
;  
current_to_prog:
 movlw CPROG
 movwf R0
 movlw PROG
 movwf R1
 clrf PC
 
ctp_loop:
 movf R0, 0
 movwf FSR
 incf R0, 1
 movf INDF, 0
 movwf TEMP
 movf R1, 0
 movwf FSR
 incf R1, 1
 movf TEMP, 0
 movwf INDF
 incf PC, 1
 btfss PC, 4
  goto ctp_loop
 
 return
 
; print_status - function
; Purpose:
;  The purpose of this function is to print out the current status of the device to the LCD screen.
;  Now the screen has two rows, each with 16 characters printable. For that purpose:
;   - The top row will show the current largest program in hexidecimal
;   - The bottom row will show "Len: <num> [Done]"
print_status:
 bsf LCDCONTROL, 0
 movlw LCD_CLEAR_SCREEN
 movfw LCDOUT
 pagesel lcd_write_data_busy
 call lcd_write_data_busy

 banksel FSR
 movlw LPROG
 movwf FSR
 bcf LCDCONTROL, 0

 movlw D'8'
 movwf PC 	; Use PC as the counter down
print_status_lprog:
 movf INDF, W
 movwf TEMP
 pagesel print_byte_as_hex
 call print_byte_as_hex
 decf PC, F
 btfss STATUS, Z
  goto print_status_lprog
 
 return

; print_byte_as_hex - function
; This function assumes that the number to print is in TEMP
; This function assumes that the lcd is in write mode not control mode
print_byte_as_hex:
 swapf TEMP, W
 andlw 0x0F
 pagesel get_hex_char
 call get_hex_char
 banksel LCDOUT
 movwf LCDOUT
 pagesel lcd_write_data_busy
 call lcd_write_data_busy
 
 movf TEMP, W
 andlw 0x0F
 pagesel get_hex_char
 call get_hex_char
 banksel LCDOUT
 movwf LCDOUT
 pagesel lcd_write_data_busy
 call lcd_write_data_busy
 return

; get_hex_char - function
; Assumes that W contains the value to convert to hex
get_hex_char:
 ; select the character to read
 banksel FSR
 movwf FSR
 movlw hex_st
 addwf FSR, F
 bankisel hex_st
 movf INDF, W
 return

; print_string - function
; Assumes that WREG holds the string that you want to print
print_string:
 return

print_number:
 return
 
; results_to_lprog - function
; Purpose:
;  The purpose of this function is to copy the values in the current program to the largest program save registers.
;  You call this function when the current value in CCOUNT and CPROG are the longest program that you have seen so far.
results_to_lprog:
 movlw CPROG
 movwf R0
 movlw LPROG
 movwf R1
 clrf PC
 
rtl_loop:
 ; load the first two values into TEMP
 movf R0, W
 movwf FSR
 incf R0, F
 movf INDF, W
 movwf TEMP
 swapf TEMP, F  ; Put it on the other side and make way for the next.
 incf FSR, F
 incf R0, F
 movf INDF, W
 iorwf TEMP, F
 
 ; move temp into the next slot in LPROG
 movf R1, W
 movwf FSR
 incf R1, F
 movf TEMP, W
 movwf INDF
 
 incf PC, F
 btfss PC, 3	; skip when you reach 8
  goto rtl_loop
  
 ; now copy CCOUNT to LCOUNT
 movlw CCOUNT
 movwf R0
 movlw LCOUNT
 movwf R1
 clrf PC
 
rtl_count_loop:
 movf R0, W
 movwf FSR
 incf R0, F
 movf INDF, W
 movwf TEMP
 movf R1, W
 movwf FSR
 incf R1, F
 movf TEMP, W
 movwf INDF
 
 incf PC, F
 btfss PC, 2
  goto rtl_count_loop
  
 return
 
; current_program_length - function
; Purpose:
;  The purpose of this function is to give back the length of the current program. You do that by starting at
;  the end of the program and working out how many spaces of zeroes there are; then how ever many trailing zeros 
;  there are the length of the program is 16 - trailing_zeroes
current_program_length:
 clrf TEMP
 movlw CPROG
 movwf FSR
 movlw 0x0F
 addwf FSR, 1
 
cpl_loop:
 movf INDF, 0
 btfss STATUS, Z
  goto cpl_end_loop
 decf FSR, 1
 incf TEMP, 1
 goto cpl_loop
 
cpl_end_loop:
 movf TEMP, 0
 sublw 0x10
 return

; run_program - function
; input values
;  PROG
; affected registers that could end up being anything after the function is called
;  WREG
;  PC, R0, R1
;  PROG
;  TEMP
; return values
;  WREG - Undefined
;  CCOUNT - The number of characters that the program would have printed out to a screen.
run_program:
 call current_to_prog

 clrf PC
 clrf R0
 clrf R1
 ; clear CCOUNT
 movlw CCOUNT
 movwf FSR
 movlw 0x4
 movwf TEMP
 pagesel clear_multibyte
 call clear_multibyte
 
 ; clear TIMEOUT
 movlw TIMEOUT
 movwf FSR
 movlw 0x2
 movwf TEMP
 pagesel clear_multibyte
 call clear_multibyte

 movlw LCOUNT

; Get the next instruction from memory
rp_main_loop:
; increment the timeout. It it has timed out then clear the CCOUNT and break out
 incf TIMEOUT, F
 btfsc STATUS, Z
  incf (TIMEOUT+1), F
 
 ; compare against timeout values
 movf TIMEOUT, W
 sublw timeout_low
 btfss STATUS, Z
  goto continue_main_loop
 movf (TIMEOUT+1), W
 sublw timeout_high
 btfss STATUS, Z
  goto continue_main_loop
 
 ; clear CCOUNT
 movlw CCOUNT
 movwf FSR
 movlw 0x4
 movwf TEMP
 pagesel clear_multibyte
 call clear_multibyte
 goto rp_fin
; load the next instruction
continue_main_loop:
 lcw

; add it to the PCL so that you use the jump table
 movwf TEMP
 pageselw rp_begin_jumptable
 movf TEMP, W
 addlw rp_begin_jumptable
 btfsc STATUS, C
  incf PCLATH, F
 movwf PCL
 
rp_begin_jumptable:
 goto rp_zero
 goto rp_one
 goto rp_two
 goto rp_three
 goto rp_four
 goto rp_five
 goto rp_six
 goto rp_seven 
 goto rp_eight
 goto rp_nine
 goto rp_ten
 goto rp_eleven
 goto rp_twelve
 goto rp_thirteen
 goto rp_fourteen
 goto rp_fifteen
 
rp_zero:
 goto rp_fin
 
rp_one:
; R0 = R0 + R1
 movf R1, 0		; Load R1 into W
 addwf R0, 1	; Add R1 to R0 and store back in R0
 wrap_r0
 goto rp_end_case
 
rp_two:
; R0 = R0 - R1
 movf R1, 0 ; 
 subwf R0, 1
 wrap_r0
 goto rp_end_case
 
rp_three:
; R0++
 incf R0, 1
 wrap_r0
 goto rp_end_case
 
rp_four:
 incf R1, 1
 wrap_r1
 goto rp_end_case
 
rp_five:
 decf R0, 1
 wrap_r0
 goto rp_end_case
 
rp_six:
 decf R1, 1
 wrap_r1
 goto rp_end_case
 
rp_seven:
 ; This is a side effect instruction that we can ignore
 goto rp_end_case
 
rp_eight:
; 8	x	Print x
; This is the most complicated step where we have to calculate how many characters get printed to the screen
 increment_pc
 lcw
 movwf TEMP
 
 ; TODO Maybe change this code to be a addwf instead so that you can perform a single add instead of two increments
 call increment_ccount
 
 movlw 0xA
 subwf TEMP, 0
 btfsc STATUS, C
  call increment_ccount
 
 goto rp_end_case

rp_nine:
; 9	x	Load value at location x into R0
 increment_pc
 ; load 'x' into WREG
 lcw
 
 ; use 'x' to as an offset to load whatever is at that position
 movwf TEMP
 movlw PROG
 addwf TEMP, 0
 movwf FSR
 movf INDF, 0
 
 ; store the value that you loaded in R0
 movwf R0
 goto rp_end_case
 
rp_ten:
; 10	x	Load value at location x into R1
 increment_pc
 ; load 'x' into WREG
 lcw
 
 ; now use 'x' as an offset to lead whatever is at that position
 movwf TEMP
 movlw PROG
 addwf TEMP, 0
 movwf FSR
 movf INDF, 0
 
 ; store the value that you loaded into R1
 movwf R1
 goto rp_end_case
 
rp_eleven:
; 11	x	Store value in R0 into location x
 increment_pc
 lcw
 
 ; calculate where to store the value
 movwf TEMP
 movlw PROG
 addwf TEMP, 0
 movwf FSR
 
 ; now get and store the value
 movf R0, 0
 movwf INDF
 
 goto rp_end_case
 
rp_twelve:
; 12	x	Store value in R1 into location x
 increment_pc
 lcw
 
 ; calculate where to store the value
 movwf TEMP
 movlw PROG
 addwf TEMP, 0
 movwf FSR
 
 ; now get and store the value
 movf R1, 0
 movwf INDF
 goto rp_end_case
 
rp_thirteen:
; 13	x	Goto x
 increment_pc
 lcw 
 movwf PC 
 ; start looping again
 goto rp_main_loop
 
rp_fourteen:
; 14	x	If R0 == 0 Then Goto x
 increment_pc
 clrf STATUS
 movf R0, 1
 btfss STATUS, Z
  goto rp_end_case
 lcw
 movwf PC
 goto rp_main_loop
 
rp_fifteen:
; 15	x	If R0 != 0 Then Goto x
 increment_pc
 clrf STATUS
 movf R0, 1
 btfsc STATUS, Z
  goto rp_end_case
 lcw
 movwf PC
 goto rp_main_loop

rp_end_case:
 increment_pc
 goto rp_main_loop

rp_fin:
 return
 
increment_ccount:
 movlw CCOUNT
 movwf FSR
 clrf STATUS
 incf INDF, 1
 btfss STATUS, Z
  goto increment_ccount_end
  
 incf FSR, 1
 clrf STATUS
 incf INDF, 1
 btfss STATUS, Z
  goto increment_ccount_end
  
 incf FSR, 1
 clrf STATUS
 incf INDF, 1
 btfss STATUS, Z
  goto increment_ccount_end
  
 incf FSR, 1
 incf INDF, 1

increment_ccount_end: 
 return
 
; clear_multibyte - function
; Purpose:
;  This function clears a variable to zero. It assums that FSR is pointing to the right place and that TEMP contains the 
;  number of bytes to clear.
clear_multibyte:
 clrf INDF
 incf FSR, F
 decf TEMP, F
 btfss STATUS, Z
  goto clear_multibyte
 return

string_data idata 0xA0
welcome_st 	db "4917 Solver", 0
len_st 		db "Len: ", 0
done_st 	db "Done", 0
hex_st 		db "0123456789ABCDEF"

 end