; ISR_example.asm: a) Increments/decrements a BCD variable every half second using
; an ISR for timer 2; b) Generates a 2kHz square wave at pin P3.7 using
; an ISR for timer 0; and c) in the 'main' loop it displays the variable
; incremented/decremented using the ISR for timer 2 on the LCD.  Also resets it to 
; zero if the 'BOOT' pushbutton connected to P4.5 is pressed.
$NOLIST
$MODLP51
$LIST

; There is a couple of typos in MODLP51 in the definition of the timer 0/1 reload
; special function registers (SFRs), so:

TIMER0_RELOAD_L DATA 0xf2
TIMER1_RELOAD_L DATA 0xf3
TIMER0_RELOAD_H DATA 0xf4
TIMER1_RELOAD_H DATA 0xf5

CLK           EQU 22118400 ; Microcontroller system crystal frequency in Hz
TIMER0_RATE   EQU 4096     ; 2048Hz squarewave (peak amplitude of CEM-1203 speaker)
TIMER0_RELOAD EQU ((65536-(CLK/TIMER0_RATE)))
TIMER2_RATE   EQU 1000     ; 1000Hz, for a timer tick of 1ms
TIMER2_RELOAD EQU ((65536-(CLK/TIMER2_RATE)))

BOOT_BUTTON   equ P4.5
HOUR_BUTTON	  equ P0.1
SOUND_OUT     equ P3.7
UPDOWN        equ P0.0
SAVE_ALARM    equ P2.4
STOP_ALARM    equ P2.0
ALARM_MODE    equ P0.4
STOPWATCH_MODE   equ P2.1
TIMER_mode 		 equ P2.5


; Reset vector
org 0x0000
    ljmp main

; External interrupt 0 vector (not used in this code)
org 0x0003
	reti

; Timer/Counter 0 overflow interrupt vector
org 0x000B
	ljmp Timer0_ISR

; External interrupt 1 vector (not used in this code)
org 0x0013
	reti

; Timer/Counter 1 overflow interrupt vector (not used in this code)
org 0x001B
	reti

; Serial port receive/transmit interrupt vector (not used in this code)
org 0x0023 
	reti
	
; Timer/Counter 2 overflow interrupt vector
org 0x002B
	ljmp Timer2_ISR

; In the 8051 we can define direct access variables starting at location 0x30 up to location 0x7F
dseg at 0x30
Count1ms:     ds 2 ; Used to determine when half second has passed
BCD_counter:  ds 1 ; The BCD counter incrememted in the ISR and displayed in the main loop
MIN_counter:  ds 3
HOURS_counter:  ds 4
AM_PM_flag: ds 5
ALARM_hours: ds 6
ALARM_minutes: ds 7
ALARM_am_pm_flag:ds 8
ALARM_stop: ds 1
STRING_COUNTER: ds 1
STOPWATCH_starter: ds 1
STOPWATCH_minutes: ds 2
STOPWATCH_seconds: ds 2
TIMER_starter: ds 2
TIMER_100: ds 2
AM_PM_changer: ds 2


; In the 8051 we have variables that are 1-bit in size.  We can use the setb, clr, jb, and jnb
; instructions with these variables.  This is how you define a 1-bit variable:
bseg
half_seconds_flag: dbit 1 ; Set to one in the ISR every time 500 ms had passed

cseg
; These 'equ' must match the wiring between the microcontroller and the LCD!
LCD_RS equ P1.1
LCD_RW equ P1.2
LCD_E  equ P1.3
LCD_D4 equ P3.2
LCD_D5 equ P3.3
LCD_D6 equ P3.4
LCD_D7 equ P3.5
$NOLIST
$include(LCD_4bit.inc) ; A library of LCD related functions and utility macros
$LIST

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;    
    

;---------------------------------;
; Routine to initialize the ISR   ;
; for timer 0                     ;
;---------------------------------;
Timer0_Init:
	mov a, TMOD
	anl a, #0xf0 ; Clear the bits for timer 0
	orl a, #0x01 ; Configure timer 0 as 16-timer
	mov TMOD, a
	mov TH0, #high(TIMER0_RELOAD)
	mov TL0, #low(TIMER0_RELOAD)
	; Set autoreload value
	mov TIMER0_RELOAD_H, #high(TIMER0_RELOAD)
	mov TIMER0_RELOAD_L, #low(TIMER0_RELOAD)
	; Enable the timer and interrupts
    setb ET0  ; Enable timer 0 interrupt
    setb TR0  ; Start timer 0
    mov HOURS_counter, #0x01 ;Initialize Hours here
    mov MIN_counter, #0x0 ;Initiliaze Minutes here
    mov AM_PM_flag, #0x0 ;Initialize am_pm flag here
    mov ALARM_hours, #0x0 ;Initialize alarm hours here
    mov ALARM_minutes, #0x0 ;Initialize alarm minutes here
    mov ALARM_stop, #0x01 ;Initialize alarm stop here
    mov STOPWATCH_minutes, #0x00 ;Initialize string counter here
    mov STOPWATCH_seconds,#0x00
    mov STOPWATCH_starter,#0x00
    mov TIMER_100,#0x99
	ret

;---------------------------------;
; ISR for timer 0.  Set to execute;
; every 1/4096Hz to generate a    ;
; 2048 Hz square wave at pin P3.7 ;
;---------------------------------;
Timer0_ISR:
	;clr TF0  ; According to the data sheet this is done for us already.
	;cpl SOUND_OUT ; Connect speaker to P3.7!
	reti

;---------------------------------;
; Routine to initialize the ISR   ;
; for timer 2                     ;
;---------------------------------;
Timer2_Init:
	mov T2CON, #0 ; Stop timer/counter.  Autoreload mode.
	mov TH2, #high(TIMER2_RELOAD)
	mov TL2, #low(TIMER2_RELOAD)
	; Set the reload value
	mov RCAP2H, #high(TIMER2_RELOAD)
	mov RCAP2L, #low(TIMER2_RELOAD)
	; Init One millisecond interrupt counter.  It is a 16-bit variable made with two 8-bit parts
	clr a
	mov Count1ms+0, a
	mov Count1ms+1, a
	; Enable the timer and interrupts
    setb ET2  ; Enable timer 2 interrupt
    setb TR2  ; Enable timer 2
	ret

;---------------------------------;
; ISR for timer 2                 ;
;---------------------------------;
Timer2_ISR:
	clr TF2  ; Timer 2 doesn't clear TF2 automatically. Do it in ISR
	cpl P3.6 ; To check the interrupt rate with oscilloscope. It must be precisely a 1 ms pulse.
	
	; The two registers used in the ISR must be saved in the stack
	push acc
	push psw
	
	; Increment the 16-bit one mili second counter
	inc Count1ms+0    ; Increment the low 8-bits first
	mov a, Count1ms+0 ; If the low 8-bits overflow, then increment high 8-bits
	jnz Inc_Done
	inc Count1ms+1

Inc_Done:
	; Check if one second has passed
	mov a, Count1ms+0
	cjne a, #low(1000), Timer2_ISR_done ; 
	mov a, Count1ms+1
	cjne a, #high(1000), Timer2_ISR_done
	
	; 1000 milliseconds have passed.  Set a flag so the main program knows
	setb half_seconds_flag ; Let the main program know a second had passed
	cpl TR0 ; Enable/disable timer/counter 0. This line creates a beep-silence-beep-silence sound.
	; Reset to zero the milli-seconds counter, it is a 16-bit variable
	clr a
	mov Count1ms+0, a
	mov Count1ms+1, a
	; Increment the BCD counter
	mov a, BCD_counter
	jnb UPDOWN, Timer2_ISR_decrement
	
;adding	
	
adding1:
	add a, #0x01
	sjmp Timer2_ISR_da
Timer2_ISR_decrement:
	add a, #0x99 ; Adding the 10-complement of -1 is like subtracting 1.
Timer2_ISR_da:
	da a ; Decimal adjust instruction.  Check datasheet for more details!
	cjne a,#0x60,print ; adjust seconds limit here
	mov a,#0x00
	
	
print:
	mov BCD_counter, a
	cjne a,#0x00, Timer2_ISR_done
	
add_min:
	mov a, MIN_counter
	add a,#0x01
	da a
	cjne a,#0x60, plus_minutes ; adjust minutes limit here
	mov a,#0x00
	
plus_minutes:
	mov MIN_counter, a
	cjne a,#0x00,Timer2_ISR_done	
 
add_hour:
	mov a, HOURS_counter
	add a,#0x01
	da a
	cjne a,#0x13, plus_hours ; adjust hours limit here
	mov a,#0x01

plus_hours:
	mov HOURS_counter, a
	mov a,#0x00
	
	
Timer2_ISR_done:
	pop psw
	pop acc
	reti
	
	

; These custom characters copied from https://cdn.instructables.com/ORIG/FGY/5J1E/GYFYDR5L/FGY5J1EGYFYDR5L.txt
Custom_Characters:
	WriteCommand(#40h) ; Custom characters are stored starting at address 40h
; Custom made character 0
	WriteData(#00111B)
	WriteData(#01111B)
	WriteData(#11111B)
	WriteData(#11111B)
	WriteData(#11111B)
	WriteData(#11111B)
	WriteData(#11111B)
	WriteData(#11111B)
; Custom made character 1
	WriteData(#11111B)
	WriteData(#11111B)
	WriteData(#11111B)
	WriteData(#00000B)
	WriteData(#00000B)
	WriteData(#00000B)
	WriteData(#00000B)
	WriteData(#00000B)
; Custom made character 2
	WriteData(#11100B)
	WriteData(#11110B)
	WriteData(#11111B)
	WriteData(#11111B)
	WriteData(#11111B)
	WriteData(#11111B)
	WriteData(#11111B)
	WriteData(#11111B)
; Custom made character 3
	WriteData(#11111B)
	WriteData(#11111B)
	WriteData(#11111B)
	WriteData(#11111B)
	WriteData(#11111B)
	WriteData(#11111B)
	WriteData(#01111B)
	WriteData(#00111B)
; Custom made character 4
	WriteData(#00000B)
	WriteData(#00000B)
	WriteData(#00000B)
	WriteData(#00000B)
	WriteData(#00000B)
	WriteData(#11111B)
	WriteData(#11111B)
	WriteData(#11111B)
; Custom made character 5
	WriteData(#11111B)
	WriteData(#11111B)
	WriteData(#11111B)
	WriteData(#11111B)
	WriteData(#11111B)
	WriteData(#11111B)
	WriteData(#11110B)
	WriteData(#11100B)
; Custom made character 6
	WriteData(#11111B)
	WriteData(#11111B)
	WriteData(#11111B)
	WriteData(#00000B)
	WriteData(#00000B)
	WriteData(#00000B)
	WriteData(#11111B)
	WriteData(#11111B)
; Custom made character 7
	WriteData(#11111B)
	WriteData(#00000B)
	WriteData(#00000B)
	WriteData(#00000B)
	WriteData(#00000B)
	WriteData(#11111B)
	WriteData(#11111B)
	WriteData(#11111B)
	ret

; For all the big numbers, the starting column is passed in register R1
Draw_big_0:
	mov a, R1
	orl a, #0x80 
	lcall ?WriteCommand 
	WriteData(#0)  
	WriteData(#1) 
	WriteData(#2)
	WriteData(#' ')
	mov a, R1
	orl a, #0xc0
	lcall ?WriteCommand 
	WriteData(#3)  
	WriteData(#4)  
	WriteData(#5)
	WriteData(#' ')
	ret
	
Draw_big_1:
	mov a, R1
	orl a, #0x80 
	lcall ?WriteCommand 
	WriteData(#1)
	WriteData(#2)
	WriteData(#' ')
	WriteData(#' ')
	mov a, R1
	orl a, #0xc0
	lcall ?WriteCommand 
	WriteData(#4)
	WriteData(#255)
	WriteData(#4)
	WriteData(#' ')
	ret

Draw_big_2:
	mov a, R1
	orl a, #0x80 
	lcall ?WriteCommand 
	WriteData(#6)
	WriteData(#6)
	WriteData(#2)
	WriteData(#' ')
	mov a, R1
	orl a, #0xc0
	lcall ?WriteCommand 
	WriteData(#3)
	WriteData(#7)
	WriteData(#7)
	WriteData(#' ')
	ret

Draw_big_3:
	mov a, R1
	orl a, #0x80 
	lcall ?WriteCommand 
	WriteData(#6)
	WriteData(#6)
	WriteData(#2)
	WriteData(#' ')
	mov a, R1
	orl a, #0xc0
	lcall ?WriteCommand 
	WriteData(#7)
	WriteData(#7)
	WriteData(#5)
	WriteData(#' ')
	ret

Draw_big_4:
	mov a, R1
	orl a, #0x80 
	lcall ?WriteCommand 
	WriteData(#3)
	WriteData(#4)
	WriteData(#2)
	WriteData(#' ')
	mov a, R1
	orl a, #0xc0
	lcall ?WriteCommand 
	WriteData(#' ')
	WriteData(#' ')
	WriteData(#255)
	WriteData(#' ')
	ret

Draw_big_5:
	mov a, R1
	orl a, #0x80 
	lcall ?WriteCommand 
	WriteData(#255)
	WriteData(#6)
	WriteData(#6)
	WriteData(#' ')
	mov a, R1
	orl a, #0xc0
	lcall ?WriteCommand 
	WriteData(#7)
	WriteData(#7)
	WriteData(#5)
	WriteData(#' ')
	ret

Draw_big_6:
	mov a, R1
	orl a, #0x80 
	lcall ?WriteCommand 
	WriteData(#0)
	WriteData(#6)
	WriteData(#6)
	WriteData(#' ')
	mov a, R1
	orl a, #0xc0
	lcall ?WriteCommand 
	WriteData(#3)
	WriteData(#7)
	WriteData(#5)
	WriteData(#' ')
	ret

Draw_big_7:
	mov a, R1
	orl a, #0x80 
	lcall ?WriteCommand 
	WriteData(#1)
	WriteData(#1)
	WriteData(#2)
	WriteData(#' ')
	mov a, R1
	orl a, #0xc0
	lcall ?WriteCommand 
	WriteData(#' ')
	WriteData(#' ')
	WriteData(#0)
	WriteData(#' ')
	ret

Draw_big_8:
	mov a, R1
	orl a, #0x80 
	lcall ?WriteCommand 
	WriteData(#0)
	WriteData(#6)
	WriteData(#2)
	WriteData(#' ')
	mov a, R1
	orl a, #0xc0
	lcall ?WriteCommand 
	WriteData(#3)
	WriteData(#7)
	WriteData(#5)
	WriteData(#' ')
	ret

Draw_big_9:
	mov a, R1
	orl a, #0x80 
	lcall ?WriteCommand 
	WriteData(#0)
	WriteData(#6)
	WriteData(#2)
	WriteData(#' ')
	mov a, R1
	orl a, #0xc0
	lcall ?WriteCommand 
	WriteData(#' ')
	WriteData(#' ')
	WriteData(#255)
	WriteData(#' ')
	ret

; The number to display is passed in accumulator.  The column where to display the
; number is passed in R1. This works only for numbers 0 to 9.
Display_big_number:
	; We need to multiply the accumulator by 3 because the jump table below uses 3 bytes
	; for each 'ljmp' instruction.
	mov b, #3
	mul ab
	mov dptr, #Jump_table
	jmp @A+dptr
Jump_table:
	ljmp Draw_big_0 ; This instruction uses 3 bytes
	ljmp Draw_big_1
	ljmp Draw_big_2
	ljmp Draw_big_3
	ljmp Draw_big_4
	ljmp Draw_big_5
	ljmp Draw_big_6
	ljmp Draw_big_7
	ljmp Draw_big_8
	ljmp Draw_big_9
; No 'ret' needed because we are counting of on the 'ret' provided by the Draw_big_x functions above




; Takes a BCD 2-digit number passed in the accumulator and displays it at position passed in R0
Display_Big_BCD:
	push acc
	; Display the most significant decimal digit
	mov b, R0
	mov R1, b
	swap a
	anl a, #0x0f
	lcall Display_big_number
	
	; Display the least significant decimal digit, which starts 4 columns to the right of the most significant digit
	mov a, R0
	add a, #3
	mov R1, a
	pop acc
	anl a, #0x0f
	lcall Display_big_number
	
	
	ret



 
;---------------------------------;
; Main program. Includes hardware ;
; initialization and 'forever'    ;
; loop.                           ;
;---------------------------------;
main:
	; Initialization
    mov SP, #0x7F
    lcall Timer0_Init
    lcall Timer2_Init
    ; In case you decide to use the pins of P0 configure the port in bidirectional mode:
    mov P0M0, #0
    mov P0M1, #0
    setb EA   ; Enable Global interrupts
    lcall LCD_4BIT
    lcall Custom_Characters ; Custom characters are needed to display big numbers.  This call generates them.
    setb half_seconds_flag
    setb HOUR_BUTTON 
    ;cpl SOUND_OUT
	mov BCD_counter, #0x00
	
	
	; After initialization the program stays in this 'forever' loop
loop:
	jb SAVE_ALARM, Minutes_button  ; if the 'BOOT' button is not pressed skip
	Wait_Milli_Seconds(#50)	; Debounce delay.  This macro is also in 'LCD_4bit.inc'
	jb SAVE_ALARM, Minutes_button ; if the 'BOOT' button is not pressed skip
	jnb SAVE_ALARM, $		; Wait for button release.  The '$' means: jump to same instruction.
	
	mov ALARM_hours,HOURS_counter
	mov ALARM_minutes,MIN_counter
	mov ALARM_am_pm_flag,AM_PM_flag
	
	mov a, #0x08
    lcall ?WriteCommand
    
    Wait_Milli_Seconds(#255)
    mov a, #0x0E
	lcall ?WriteCommand
		
Minutes_button:
	jb BOOT_BUTTON, Hours_button  ; if the 'MINUTES' button is not pressed skip
	Wait_Milli_Seconds(#50)	; Debounce delay.  
	jb BOOT_BUTTON, Hours_button ; if the 'MINUTES' button is not pressed skip
	jnb BOOT_BUTTON, $		; Wait for button release.  .
	clr TR2                 ; Stop timer 2
	;clr a
	mov a,MIN_counter
	add a, #0x01
	mov MIN_counter, a
	da a
	cjne a,#0x60,plusser
	mov a,#0x00

plusser:
	mov Min_counter, a
	setb TR2                ; Start timer 2
	sjmp loop_b             ; Display the new value


Hours_button:
	jb HOUR_BUTTON, loop_a  ; if the 'BOOT' button is not pressed skip
	Wait_Milli_Seconds(#50)	; Debounce delay.  This macro is also in 'LCD_4bit.inc'
	jb HOUR_BUTTON, loop_a   ; if the 'BOOT' button is not pressed skip
	jnb HOUR_BUTTON, $		; Wait for button release.  The '$' means: jump to same instruction.
	
	clr TR2                 ; Stop timer 2
	;clr a
	mov a,HOURS_counter
	add a, #0x01
	mov HOURS_counter, a
	da a
	cjne a,#0x13,plusser_hour
	mov a,#0x01

plusser_hour:
	mov HOURS_counter, a
	setb TR2                ; Start timer 2
	sjmp loop_b             ; Display the new value
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
	
	
	
		
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

loop_a:
	jnb half_seconds_flag, loop
loop_b:
    clr half_seconds_flag ; We clear this flag in the main loop, but it is set in the ISR for timer 2
    mov R0, #0 ; Column where to display the big font 2-digit number 
    mov a, HOURS_counter ; The number to display using big font
	lcall Display_Big_BCD
	mov R0, #7 ; Column where to display the big font 2-digit number
    mov a, MIN_counter ; The number to display using big font
	lcall Display_Big_BCD
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
			
	
	
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
Stopwatch:
	jb STOPWATCH_MODE, Timer  ; if the 'Stopwatch' button is not pressed skip
	Wait_Milli_Seconds(#50)	; Debounce delay.  
	jb STOPWATCH_MODE, Timer ; if the 'Stopwatch' button is not pressed skip
	jnb STOPWATCH_MODE, $		; Wait for button release. 
	
	mov STOPWATCH_starter, #0x01
	mov BCD_counter,#0x01
	mov a, STOPWATCH_starter
	cjne a,#0x01,Timer

STOPWATCH_display:	
	
	mov a, BCD_counter
	add a,#0x01
	Wait_Milli_Seconds(#255) 
	Wait_Milli_Seconds(#255)
	Wait_Milli_Seconds(#255)
	Wait_Milli_Seconds(#255); wait one second, 255 as 8 bits maximum
	da a
	mov BCD_counter,a
	cjne a,#0x60,print_seconds ; adjust seconds limit here
	mov a, STOPWATCH_minutes ; if STOPWATCH_minutes is not 60, 
	add a,#0x01
	mov STOPWATCH_minutes,a
	mov a,#0x00
	mov BCD_Counter,#0x00 ; reset a
	
print_seconds:	
	mov R0, #7 ; Column where to display the big font 2-digit number
    mov a, BCD_counter; The number to display using big font
	lcall Display_Big_BCD
		
	
print_minutes:	
	;clr half_seconds_flag ; We clear this flag in the main loop, but it is set in the ISR for timer 2
    mov R0, #0 ; Column where to display the big font 2-digit number 
    mov a, STOPWATCH_minutes ; The number to display using big font
	lcall Display_Big_BCD
	
check_for_recurring:
	;mov a,STOPWATCH_STARTER
	
	jb STOPWATCH_MODE, STOPWATCH_display ; if the 'BOOT' button is not pressed skip
	Wait_Milli_Seconds(#50)	; Debounce delay.  This macro is also in 'LCD_4bit.inc'
	jb STOPWATCH_MODE, STOPWATCH_display; if the 'BOOT' button is not pressed skip
	jnb STOPWATCH_MODE, $		; Wait for button release.  The '$' means: jump to same instruction.
	
	
	;cjne a,#0x00,STOPWATCH_display
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
Timer:
	jb TIMER_mode, Alarm_checker_check ; if the 'TIMER' button is not pressed skip
	Wait_Milli_Seconds(#50)	; Debounce delay. 
	jb TIMER_mode, Alarm_checker_check ; if the 'TIMER' button is not pressed skip
	jnb TIMER_mode, $		; Wait for button release.  
	
Timer_subb:
	mov a, TIMER_100
	da a
	subb a,#0x01
	mov TIMER_100,a
	cjne a,#0x90,check_80
	mov a,#0x89
	mov TIMER_100,a
	
check_80:
	cjne a,#0x80,check_70
	mov a,#0x79
	mov TIMER_100, a

check_70:
	cjne a,#0x70,check_60
	mov a,#0x69
	mov TIMER_100, a
	
check_60:
	cjne a,#0x60,check_50
	mov a,#0x59
	mov TIMER_100,a

check_50:
	cjne a,#0x50, print_timer
	mov a,#0x49
	mov TIMER_100,a

	
print_timer:	
	mov R0, #0 ; Column where to display the big font 2-digit number 
    mov a, #0x00 ; The number to display using big font
	lcall Display_Big_BCD
	
	mov R0, #7 ; Column where to display the big font 2-digit number
    mov a, TIMER_100; The number to display using big font
	lcall Display_Big_BCD
	
	Wait_Milli_Seconds(#255)
	Wait_Milli_Seconds(#255)
	Wait_Milli_Seconds(#255)
	Wait_Milli_Seconds(#255)
	
	jb TIMER_mode, Timer_subb ; if the 'TIMER' button is not pressed skip
	Wait_Milli_Seconds(#50)	; Debounce delay.  This macro is also in 'LCD_4bit.inc'
	jb TIMER_mode, Timer_subb; if the 'TIMER' button is not pressed skip
	jnb TIMER_mode, $		; Wait for button release.  The '$' means: jump to same instruction.



;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
Alarm_checker_check:	
	jb ALARM_MODE, Alarm_check  ; if the 'ALARM_CHECK' button is not pressed skip
	Wait_Milli_Seconds(#50)	; Debounce delay. 
	jb ALARM_MODE, Alarm_check ; if the 'ALARM_CHECK' button is not pressed skip
	jnb ALARM_MODE, $		; Wait for button release.  

	mov R0, #0 ; Column where to display the big font 2-digit number 
	mov a, ALARM_hours ; The number to display using big font
	lcall Display_Big_BCD
	mov R0, #7 ; Column where to display the big font 2-digit number
	mov a, ALARM_minutes ; The number to display using big font
	lcall Display_Big_BCD
	
	;Write divider between minutes/hours
	mov a,#0xc6
	lcall ?WriteCommand
	mov a,#'.' 
	lcall ?WriteData
	mov a,#0x86
	lcall ?WriteCommand
	mov a,#'.'
	lcall ?WriteData

;duration 
wait:	
	Wait_Milli_Seconds(#255)
	Wait_Milli_Seconds(#255)
	Wait_Milli_Seconds(#255)
	Wait_Milli_Seconds(#255)
	Wait_Milli_Seconds(#255)
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
	

	
	
	
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;	
	
	
Alarm_check:
	jb STOP_ALARM, alarm_checker  ; if the 'BOOT' button is not pressed skip
	Wait_Milli_Seconds(#50)	; Debounce delay.  This macro is also in 'LCD_4bit.inc'
	jb STOP_ALARM, alarm_checker ; if the 'BOOT' button is not pressed skip
	jnb STOP_ALARM, $		; Wait for button release.  The '$' means: jump to same instruction.
	
	mov ALARM_stop,#0x00
	
	
alarm_checker:
	mov a, HOURS_counter
	cjne a,ALARM_hours, Write_divider
	mov a, MIN_counter
	cjne a,ALARM_minutes, Alarm_flag_setter
	mov a, AM_PM_flag
	cjne a,ALARM_am_pm_flag,Write_divider
	mov a, ALARM_stop
	cjne a,#0x01, Write_divider
	cpl SOUND_OUT

Alarm_flag_setter:
	mov ALARM_stop,#0x01
	ljmp Write_divider

Write_divider:
	mov a,#0x86
	lcall ?WriteCommand
	mov a,#'.'
	lcall ?WriteData
	
	Set_Cursor(1,15)
	Display_BCD(BCD_counter)

	
	mov a,#0xc6
	lcall ?WriteCommand
	mov a,#'.'
	lcall ?WriteData
	
	mov a,#0xcf
	lcall ?WriteCommand
	mov a,#'m'
	lcall ?WriteData
	
	mov R2, HOURS_counter
	cjne R2,#0x11,check_flag ; AM TO PM
	mov R2,MIN_counter
	cjne R2,#0x59,check_flag
	mov R2,BCD_counter
	cjne R2,#0x59,check_flag
	ljmp change_am_pm
	
check_flag:
	mov R2,AM_PM_flag
	cjne R2,#0x00,pm
	ljmp am

change_am_pm:
	MOV R2,AM_PM_flag
	cjne R2,#0x00, make_0
	mov AM_PM_flag,#0x01
	ljmp check_flag

make_0:
	mov AM_PM_flag,#0x00
	ljmp check_flag
		 
am:
	mov a,#0xce
	lcall ?WriteCommand
	mov a,#'a'
	lcall ?WriteData 
	ljmp loop
	
pm:
	mov a,#0xce
	lcall ?WriteCommand
	mov a,#'p'
	lcall ?WriteData
    ljmp loop
    

    
END
