; This is the main ASM file in which everything will run.
 LIST P=16f688
 processor 16f688
 include <p16f688.inc>

 __CONFIG _WDT_OFF

 cblock 0x20
	R0
	R1 
	PC
	TEMP
	PROG:16
	CCOUNT:4
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

; Load the entire program into ram
 movlw PROG
 movwf FSR
 movlw 0
 movwf PC

read_in_memory:
 movfw PC
 call program
 movwf INDF
 incf FSR
 incf PC
 btfss PC, 4
 goto read_in_memory

; while the PC does not point to a 0 we are good
start_program:
 movlw 0
 movwf PC
 movwf R0
 movwf R1

; Get the next instruction from memory
main_loop:
; load the next instruction
 lcw

; add it to the PCL so that you use the jump table
 addwf PCL, 1
 
begin_jumptable:
 goto zero
 goto one
 goto two
 goto three
 goto four
 goto five
 goto six
 goto seven 
 goto eight
 goto nine
 goto ten
 goto eleven
 goto twelve
 goto thirteen
 goto fourteen
 goto fifteen
 
zero:
 goto fin
 
one:
; R0 = R0 + R1
 movf R1, 0		; Load R1 into W
 addwf R0, 1	; Add R1 to R0 and store back in R0
 wrap_r0
 goto end_case
 
two:
; R0 = R0 - R1
 movf R1, 0 ; 
 subwf R0, 1
 wrap_r0
 goto end_case
 
three:
; R0++
 incf R0, 1
 wrap_r0
 goto end_case
 
four:
 incf R1, 1
 wrap_r1
 goto end_case
 
five:
 decf R0, 1
 wrap_r0
 goto end_case
 
six:
 decf R1, 1
 wrap_r1
 goto end_case
 
seven:
 ; This is a side effect instruction that we can ignore
 goto end_case
 
eight:
; 8	x	Print x
; This is the most complicated step where we have to calculate how many characters get printed to the screen
 increment_pc
 goto end_case

nine:
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
 goto end_case
 
ten:
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
 goto end_case
 
eleven:
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
 
 goto end_case
 
twelve:
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
 goto end_case
 
thirteen:
; 13	x	Goto x
 increment_pc
 lcw 
 movwf PC 
 ; start looping again
 goto main_loop
 
fourteen:
; 14	x	If R0 == 0 Then Goto x
 increment_pc
 bcf STATUS, Z
 movf R0, 1
 btfss STATUS, Z
  goto end_case
 lcw
 movwf PC
 goto main_loop
 
fifteen:
; 15	x	If R0 != 0 Then Goto x
 increment_pc
 bcf STATUS, Z
 movf R0, 1
 btfsc STATUS, Z
  goto end_case
 lcw
 movwf PC
 goto main_loop

end_case:
 increment_pc
 goto main_loop

fin: 
 goto fin

program:
 addwf PCL
; be careful here, all numbers must be in HEX!!!
 dt	0x3, 0x8, 0xA, 0xF
 dt	0, 0, 0, 0
 dt	0, 0, 0, 0	
 dt	0, 0, 0, 0

 end