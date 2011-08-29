; This is the main ASM file in which everything will run.
processor 16f688
include <p16f688.inc>

cblock 0x20
	R0, 
	R1, 
	PC,
	TEMP,
	PROG:16
endc

; The start of the program
org 0

; Load the entire program into ram
movlw PROG
movwf FSR
movlw 0
movwf PC

read_in_memory 
movfw PC
call program
movwf INDF
incf FSR
incf PC
btfss PC, 4
goto read_in_memory

; while the PC does not point to a 0 we are good

; Start the program off in the initial state

; Run the program as it should be run

fin: goto fin

program
addwf PCL
dt	3, 8, 10, 15
dt	0, 0, 0, 0
dt	0, 0, 0, 0	
dt	0, 0, 0, 0

end