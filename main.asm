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

 LIST P=16f688
 processor 16f688
 include <p16f688.inc>

 __CONFIG _WDT_OFF

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
 endc

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
 org 0
 goto main

; minus by one because it is zero based
prog_len 		equ (3 - 1)
timeout_high 	equ 0x04
timeout_low 	equ 0x00

program:
 addwf PCL
 dt 0x1,0x8,0x8,0xF,0x6,0x8,0xD,0x2,0x5,0xF,0x0,0x0,0x0,0x0,0x0,0x0

main:
; In this case you load the program from the bottom and run it
#if 0
 ; Load the entire program into ram
 movlw CPROG
 movwf FSR
 clrf  PC	; here the PC is used to wrap through the entire program
 
read_in_memory:
 movfw PC
 call program
 movwf INDF
 incf FSR, 1
 incf PC, 1
 btfss PC, 4 	; when you reach PC = 16 then it is time to stop
  goto read_in_memory
#else
 ; In this case you set everything to zero and just run it
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
#endif

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
  
 call results_to_lprog
 
no_update:
 ; now add one to the program
 movlw CPROG
 movwf FSR
 clrf TEMP
prog_inc_loop:
 incf INDF, F
 movlw 0x0F
 andwf INDF
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
 movf LCOUNT, W
 goto $

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
 rlf TEMP, F
 rlf TEMP, F
 rlf TEMP, F
 rlf TEMP, F
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
 call clear_multibyte
 
 ; clear TIMEOUT
 movlw TIMEOUT
 movwf FSR
 movlw 0x2
 movwf TEMP
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
 call clear_multibyte
 goto rp_fin
; load the next instruction
continue_main_loop:
 lcw

; add it to the PCL so that you use the jump table
 addwf PCL, 1
 
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

; dt	0x3, 0x8, 0xA, 0xF
; dt	0, 0, 0, 0
; dt	0, 0, 0, 0	
; dt	0, 0, 0, 0

;4:   3	8	10	15		      					32	
;5:   4	1	8	10	15		      				62
;6:   4	8	8	13	2	15		      			93
;7:   1	8	10	14	4	1	15	      			172
;8:   1	8	10	14	4	2	4	15	      		482
;9:   1	3	8	10	15	1	4	2	15       	512
;10:  1	8	8	15	6	8	13	2	5	15    	1173
;11:  1	3	8	10	8	10	15	1	4	2	15 	1024
;12:
;13:
;14:
;15:
;16:

 end