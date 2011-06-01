;; ****************************************************************************
;; Instead of string numbers we could use offsets into GS data, byte+
;; half byte; nybble address
;;
;; Registers
;;
;; r0 = scratch used by interrupt processor, don't use!
;; r1 = SPI reading, used in interrupt
;; r2 = SPI counter
;; r3 = Target Intensity
;; r4l:r5h = LED brightness
;; r6 = TLC SPI Byte type
;; r7 = scratch used in interrupt processing
;; r10 = channel # parameter to TLC_setChannelTargetIntensity
;; N r11: low byte of channel parameter
;; N r12: high byte of channel parameter
;; I r17 = minutes past hour
;; I r18 = hours (0-11)
;; N r19 = temp, can be overwritten by any function, but not overwritten
;;       in interrupt handlers
;; r20 = scratch for interrupt handling
;; r21 = scratch for interrupt handling
;; r24:r25 = timer counter
;; r26:r27 X, used in TLC_setChannelTargetIntensity.
;; r30:r31 Z = SPI read pointer
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

;; CONSTANTS
;; TICKS_PER_STEP is the number of timer0 ticks per clock step.
;; For Erland's clock a clock step is five minutes, for Mac's it will be
;; one minute.
;; MINUTES_PER_STEP is defined in the relevant config.h file
;; 16000000 / (1024 * 255) timer ticks per second * 60 * 60
/* .equ	TICKS_PER_STEP, (16000000 * 60 * MINUTES_PER_STEP) / (1024 * 255) */
.equ	TICKS_PER_STEP, (16000000 * 12) / (1024 * 10 * 255)
.equ	STEPS_PER_HOUR, (60 / MINUTES_PER_STEP)

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

	;; Initialize the time to midnight
	ldi 	MINS_PAST, 	0	; 5 minutes past hour
	ldi 	HOURS,		0	; hour

	;; Initialize timer tick counter
	ldi	REG_TICK_COUNTER_LOW, 	0
	ldi 	REG_TICK_COUNTER_HIGH, 	0

	;; Set up timer 0 with 1024 prescaler
	clr	REG_SCRATCH_4
	out	TCCR0A,	REG_SCRATCH_4	; TCCR = timer/counter control register
	ldi	REG_SCRATCH_4,	5
	out	TCCR0B, REG_SCRATCH_4	; Select prescaler 1024, turn on
	ldi	REG_SCRATCH_4,	1
	sts	TIMSK0, REG_SCRATCH_4	; Enable interrupt on overflow (TOIE0 bit)
	;; TODO:
	;; We should probably read the LDR before starting the main loop
	;; to set the initial LED intensity.
	;;
	;; For now we'll set it to maximum intensity
	ldi	REG_SCRATCH_4, 0xff
	mov	REG_CHANNEL_INTENSITY_LOW, REG_SCRATCH_4
	ldi	REG_SCRATCH_4, 0x0f
	mov	REG_CHANNEL_INTENSITY_HIGH, REG_SCRATCH_4

	call	clockFace_init
	
	;; Everything set up, enable interrupts
	sei			; Enable interrupts

	/* clr r16	*/	/* Sets r16 to 0x00 */
	/* out PORTB, r16	*/	/* Sets portB outputs to 0? */
	/* out PORTD, r16	*/ /* Sets portD outputs to 0? */

loop:
	; Mac: Idle Sleep ??? isn't it ADC noise reduction ???
	; Erl: No. The lowest bit is SE (Sleep enable) the three bits above that
	;      are 0, which is idle sleep mode
	ldi 	REG_SCRATCH_4,	1
	out	SMCR,	REG_SCRATCH_4		; SMCR = Sleep mode control register
	sleep

doneSetting:
	;; Increment time counter if required
	;; Time counter is in r24, increased 62.5 times per second ==
	;; 18750 == 0x493e times per 5 minutes
	ldi	REG_SCRATCH_4,	hi8( TICKS_PER_STEP )
	cli			; make sure r24 doesn't change while comparing
	cpi	REG_TICK_COUNTER_LOW, lo8( TICKS_PER_STEP ) ; compare with immediate
	cpc	REG_TICK_COUNTER_HIGH, REG_SCRATCH_4		; compare with carry
	sei
	brsh	noNewTime		; branch if minus

	inc	MINS_PAST		; 5 minutes past the hour
	cli
	subi	REG_TICK_COUNTER_LOW, lo8( TICKS_PER_STEP )	; subtract immediate
	sbci	REG_TICK_COUNTER_HIGH, hi8( TICKS_PER_STEP ) ; subtract immediate with carry
	sei
	cpi	MINS_PAST, STEPS_PER_HOUR
	brlo	noNewHour		; branch if lower

	inc 	HOURS			; increment hour count
	cpi	HOURS, HOURS_PER_DAY
	brlo	noNewHour
	ldi 	HOURS, 0

noNewHour:
	;; Change time words if time changed
	call	clockFace_setStrings
	
	;; If we get here, minutes changed, but not hours
	/*
	cpi	MINS_PAST, 0
	brne	isItTenPast
	*/
	;;
	;; call function to set all minute strings to intensity
	;;
	
isItTenPast:

noNewTime:
	/* Check buttons */
	/* Check LDR, adjust PWM */
	rjmp loop

timerInterrupt:
	/* save status byte */
	in	r0, 0x3f
	push	r0

	clr	r0
	inc	r0
	;; Incremement time counter (actual freq = 62.5Hz
	add	REG_TICK_COUNTER_LOW, r0
	clr	r0
	adc	REG_TICK_COUNTER_HIGH, r0

doneSetting2:
	;;  restore status register
	pop	r0
	out	0x3f, r0
	reti
	
.end
