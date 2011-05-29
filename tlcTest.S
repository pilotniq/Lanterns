;; ****************************************************************************
;; Instead of string numbers we could use offsets into GS data, byte+
;; half byte; nybble address
;;
;; Registers
;;
;; r0 = scratch used by interrupt processor, don't use!
;; r1 = SPI reading, used in interrupt
;; r2 = SPI counter
;; r3 = have new gs data
;; r4l:r5h = LED brightness
;; r6 = TLC SPI Byte type
;; r7 = scratch used in interrupt processing
;; r10 = channel # parameter to TLC_setChannelTargetIntensity
;; r17 = test number
;; r19 = temp, can be overwritten by any function, but not overwritten
;;       in interrupt handlers
;; I r20:r21 = timer counter
;; N r22: low byte of intensity parameter
;; N r23: high byte of intensity parameter
;; I r24:r25 Interrupt scratch. Current intensity in TLC SPI Interrupt. 
;; N r26:r27 X, used in TLC_setChannelTargetIntensity.
;; I r30:r31 Z = SPI read pointer
;;
;; Pins:
;;
;; PB0 CLKO - TLC5940 GSCLK
;; PB1      - TLC5940 XLAT   0
;; PB2      - TLC5940 BLANK  1
;; PB3 MOSI - TLC5940 SIN
;; PB4 MISO - ArduinoISP
;; PB5 SCK  - TLC5940 SCLK   0
;; PB6 XTAL1 - Crystal
;; PB7 XTAL2 - Crystal
;; PD4       - TLC5940 DCPRG 0
;; PD7       - TLC5940 VPRG  1
;;
;; Timers
;;
;; Timer0: Time handling. clock divider 1024
;; Timer2: TLC Handling. Clock divider 1024, max counter 3
;; ****************************************************************************


;; INCLUDES
.include "m168.h"
#include "reg_mnemonics.h"
.include "config.h"

#define REG_TEST_COUNTER r17
	
;; CONSTANTS
;; TICKS_PER_STEP is the number of timer0 ticks per TLC test
;; MINUTES_PER_STEP is defined in the relevant config.h file
;; 16000000 / (1024 * 255) timer ticks per second * 60 * 60
;; For some reaseon, doesn't work properly with TSECONDS 10 or lower.
.equ	TSECONDS_PER_TEST, 12
.equ	TICKS_PER_STEP, (16000000 * TSECONDS_PER_TEST) / (1024 * 10 * 255)

.text

;; INTERRUPT VECTORS, .org = advance location counter.
;; Since this code is the first to be excuted, the memory location is the
;; one for interrupts.
.org  0
	rjmp	init			;; boot & reset vector
.org OC2Aaddr * 2
	rjmp	TLC_spiTimerInterrupt
.org OVF0addr * 2
	rjmp	timerInterrupt	  	;; Timer 0 overflow
.org SPIaddr * 2
	rjmp TLC_spiInterrupt
.org INT_VECTORS_SIZE * 2

init:
	;; PORT SETUP
	
	;; set outputs before port direction, so values will be correct on
	;; switch
	call	TLC_init
	
	;; Initialize the test counter
	ldi 	REG_TEST_COUNTER, 	0

	;; Initialize timer tick counter
	ldi	REG_TICK_COUNTER_LOW, 	0
	ldi 	REG_TICK_COUNTER_HIGH, 	0

	;; Set up timer 0 with 1024 prescaler
	clr	r16
	out	TCCR0A,	r16	; TCCR = timer/counter control register
	ldi	r16,	5
	out	TCCR0B, r16	; Select prescaler 1024, turn on
	ldi	r16,	1
	sts	TIMSK0, r16	; Enable interrupt on overflow (TOIE0 bit)

	;; Everything set up, enable interrupts
	sei			; Enable interrupts

	;; Turn on channel 0 to full intensity
	;; Experiments: channel 0 doesn't seem to light anything
	;; channel 1 lights channel 14, not full intensity
	;; channel 2 lights channel 13 at full intensity
	;; channel 3 lights channel 12 at low intensity
	;; channel 4 lighs nothing?
	;; channel 5 lights channel 10 at low
	;; channel 6 lights channel 9 at full intensity
	;; channel 7 lights channel 8 at low
	;; channel 8 lights nothing
	;; channel 9 lights channel 6 at low
	;; channel 10 lights nothing
	;; channel 11 lights nothing
	;; channel 12 lights nothing
	;; channel 13 lights nothing
	;; channel 14 lights channel 1 at high
	;; channel 15 lights channel 0 at low
	;;
	;; Second round of experiments:
	;; channel 0 lights nothing
	;; channel 1 lights channel 14 and channel 0 weak
	;; channel 2 lights channel 13 brighter and channel 0 weak
	;; channel 3 lights only channel 0 weak
	;; channel 4 lights nothing
	;; channel 5 lights channel 10
	;; channel 6 lights channel 9 brighter
	;; channel 15 lights channel 0
	;; 
	;; Third round of tests:
	;; channel 0 lights nothing
	;; channel 1-3 lights channel 1-3
	;; channel 4 lights nothing
	;; channel 5-7 lights channel 5-7
	;; channel 8 lights nothing
	;; channel 9-
/*	ldi	r16,	15
	mov	REG_TLC_CHANNEL_NUMBER, r16
	ldi	REG_TLC_CHANNEL_INTENSITY_LOW, 0xff
	ldi	REG_TLC_CHANNEL_INTENSITY_HIGH, 0b00001111
	call	TLC_setChannelTargetIntensity

	;; Turn on channel 1 to full intensity
	ldi	r16,	4
	mov	REG_TLC_CHANNEL_NUMBER, r16
	ldi	REG_TLC_CHANNEL_INTENSITY_LOW, 0xff
	ldi	REG_TLC_CHANNEL_INTENSITY_HIGH, 0b00001111
	call	TLC_setChannelTargetIntensity

	;; Turn on channel 14 to full intensity
	ldi	r16,	5
	mov	REG_TLC_CHANNEL_NUMBER, r16
	ldi	REG_TLC_CHANNEL_INTENSITY_LOW, 0xff
	ldi	REG_TLC_CHANNEL_INTENSITY_HIGH, 0b00001111
	call	TLC_setChannelTargetIntensity

	;; Turn on channel 1 to full intensity
	ldi	r16,	4
	mov	REG_TLC_CHANNEL_NUMBER, r16
	ldi	REG_TLC_CHANNEL_INTENSITY_LOW, 0xff
	ldi	REG_TLC_CHANNEL_INTENSITY_HIGH, 0b00001111
	call	TLC_setChannelTargetIntensity

	;; Turn on channel 1 to full intensity
	ldi	r16,	5
	mov	REG_TLC_CHANNEL_NUMBER, r16
	ldi	REG_TLC_CHANNEL_INTENSITY_LOW, 0xff
	ldi	REG_TLC_CHANNEL_INTENSITY_HIGH, 0b00001111
	call	TLC_setChannelTargetIntensity
*/
loop:
	; Mac: Idle Sleep ??? isn't it ADC noise reduction ???
	; Erl: No. The lowest bit is SE (Sleep enable) the three bits above that
	;      are 0, which is idle sleep mode
	ldi 	r16,	1
	out	SMCR,	r16		; SMCR = Sleep mode control register
	sleep

doneSetting:
	;; Increment time counter if required
	;; Time counter is increased 62.5 times per second ==
	;; 18750 == 0x493e times per 5 minutes
	ldi	r16,	hi8( TICKS_PER_STEP )
	cli			; make sure r24 doesn't change while comparing
	cpi	REG_TICK_COUNTER_LOW,	lo8( TICKS_PER_STEP )	; compare with immediate
	cpc	REG_TICK_COUNTER_HIGH,	r16			; compare with carry
	sei
	brsh	loop

	cli
	subi	REG_TICK_COUNTER_LOW, lo8( TICKS_PER_STEP )	; subtract immediate
	sbci	REG_TICK_COUNTER_HIGH, hi8( TICKS_PER_STEP )	; subtract immediate with carry
	sei

	/* sbi	PIND,	6 */
	;; Debug: Gets here
	;;
	;; Do tests here.
	;; Test 0 - 16 is turning the corresponding LED on at full intensity
	;; Test 32 - 63 is fading LED 1 up from 0 to full intensity over one
	;; minute
	;;
	mov	r16,	REG_TEST_COUNTER
	andi	r16, 0b11110000 ; test if lower than 16
	brne	testAfter15

	mov	REG_TLC_CHANNEL_NUMBER, REG_TEST_COUNTER
	ldi	REG_TLC_CHANNEL_INTENSITY_LOW, 0xff
	ldi	REG_TLC_CHANNEL_INTENSITY_HIGH, 0b00001111
	call	TLC_setChannelTargetIntensity

	cpi	REG_TEST_COUNTER, 0
	brne	notFirstLED

isFirstLED:
	ldi	r16,	15
	mov	REG_TLC_CHANNEL_NUMBER, r16
	rjmp	setChannelNumber
notFirstLED:	
	;; If not first LED, turn off the previous LED
	mov	REG_TLC_CHANNEL_NUMBER, REG_TEST_COUNTER
	dec	REG_TLC_CHANNEL_NUMBER
setChannelNumber:	
	ldi	REG_TLC_CHANNEL_INTENSITY_LOW, 0x00
	ldi	REG_TLC_CHANNEL_INTENSITY_HIGH, 0x00
	call	TLC_setChannelTargetIntensity
	
	inc	REG_TEST_COUNTER
	rjmp loop
	
testAfter15:	
	ldi	REG_TEST_COUNTER, 0 ; restart tests
	;; Not implemented yet
	rjmp loop


timerInterrupt:
	/* save status byte */
	in	r0, 0x3f
	push	r0

	;; Incremement time counter (actual freq = 62.5Hz
	clr	r0
	inc	r0
	add	REG_TICK_COUNTER_LOW, r0
	clr	r0
	adc	REG_TICK_COUNTER_HIGH, r0

	;;  restore status register
	pop	r0
	out	0x3f, r0
	reti

.end
