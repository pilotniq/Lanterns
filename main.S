;; ****************************************************************************
;; Instead of string numbers we could use offsets into GS data, byte+
;; half byte; nybble address
;;
;; Registers
;;
;; NOTE: TODO: MUL result is put in registers r0:r1, so we need to reallocate
;; r0 and r1 so that they are not used without saving in interrupt handlers
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
#include "config.h"

#define DO_ADC 0
#define INITIAL_INTENSITY 0x100
	
;; CONSTANTS
;; TICKS_PER_STEP is the number of timer0 ticks per clock step.
;; For Erland's clock a clock step is five minutes, for Mac's it will be
;; one minute.
;; MINUTES_PER_STEP is defined in the relevant config.h file
;; 16000000 / (1024 * 255) timer ticks per second * 60 * 60
;; .equ	TICKS_PER_STEP, (16000000 * 60 * MINUTES_PER_STEP) / (1024 * 255)
;;
;; 16 000 000 / (1024 * 250) = 62.5 ticks/second
;; 18750 / 62.5 = 300 seconds per step.
;; For timing calibration, to two seconds per step
;; If it were running to overflow, it would run 255 / 250 slow. 5/250=1/50=
;; Would be 28 minutes/day. Is it that bad? No.
;; Is it 1/250? Would be about 6 minutes per day. Could be.
;; .equ	TICKS_PER_STEP, 125
.equ	TICKS_PER_STEP, 18750

/* .equ	TICKS_PER_STEP, (16000000 * 2) / (1024 * 255) */
.equ	STEPS_PER_HOUR, (60 / MINUTES_PER_STEP)

.text

;; INTERRUPT VECTORS, .org = advance location counter.
;; Since this code is the first to be excuted, the memory location is the
;; one for interrupts.
.org  0
	rjmp	init			;; boot & reset vector
.org OC2Aaddr * 2
	rjmp	TLC_spiTimerInterrupt
.org OC0Aaddr * 2
	rjmp	timerInterrupt
	;; .org OVF0addr * 2
	;; rjmp	timerInterrupt ; Timer 0 overflow
.org SPIaddr * 2
	rjmp TLC_spiInterrupt
.org INT_VECTORS_SIZE * 2

init:
	;; PORT SETUP
	;; set outputs before port direction, so values will be correct on
	;; switch
#if DO_ADC
	call	adc_init
	;;
	;; Start ADC conversion now, so we have result before starting display
	;;
	call	adc_start
#endif // DO_ADC
	
	call	TLC_init

	;; Set button pins to inputs
	cbi	BUTTON_DDR, BUTTON_PIN_INC_TIME
	cbi	BUTTON_DDR, BUTTON_PIN_DEC_TIME
	;; set button port pull-ups
	;; NOTE: this is special for Erl's board, change for Mac
	sbi	BUTTON_PORT, BUTTON_PIN_INC_TIME
	sbi	BUTTON_PORT, BUTTON_PIN_DEC_TIME

	ldi	REG_PREV_BUTTON_STATE, 0xff
	
	;; Initialize the time to midnight
	ldi 	MINS_PAST, 	0	; 5 minutes past hour
	ldi 	HOURS,		0	; hour

	;; Initialize timer tick counter
	ldi	REG_TICK_COUNTER_LOW, 	0
	ldi 	REG_TICK_COUNTER_HIGH, 	0

	;; Set up timer 0 with 1024 prescaler
	;; 	clr	REG_SCRATCH_4   ; Overflow mode
	ldi	REG_SCRATCH_4, 0b10	; CTC mode
	out	TCCR0A,	REG_SCRATCH_4	; TCCR = timer/counter control register
	ldi	REG_SCRATCH_4,	0b00001101 ; CTC mode, 1024 prescaler
	out	TCCR0B, REG_SCRATCH_4	; Select prescaler 1024, turn on
	;; ldi	REG_SCRATCH_4,1	; Enable interrupt on overflow (TOIE0 bit)
	;; Set it to count to 250
	;; 	ldi	REG_SCRATCH_4, 250 
	ldi	REG_SCRATCH_4, 249
	out	OCR0A,	REG_SCRATCH_4
	ldi	REG_SCRATCH_4,	0b10	; Enable interrupt on compare A
	sts	TIMSK0, REG_SCRATCH_4
#if DO_ADC
	;; TODO:
	;; We should probably read the LDR before starting the main loop
	;; to set the initial LED intensity.
	;;
	;; Wait for complete ADC conversion. ADIF bit in ADCSRA
	call	adc_wait

	call	setIntensityFromADC
#endif
	ldi	REG_TLC_CHANNEL_INTENSITY_LOW, lo8( INITIAL_INTENSITY )
	ldi	REG_TLC_CHANNEL_INTENSITY_HIGH, hi8( INITIAL_INTENSITY )

	mov	REG_CHANNEL_INTENSITY_LOW, REG_TLC_CHANNEL_INTENSITY_LOW
	mov	REG_CHANNEL_INTENSITY_HIGH, REG_TLC_CHANNEL_INTENSITY_HIGH
	call	clockFace_init
	call	clockFace_setStrings
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
	;;
	;; Check if tick count changed, otherwise loop. 
	;;
	ldi	REG_SCRATCH_4,	0
	cp	REG_TICKED,	REG_SCRATCH_4
	breq	loop

	dec	REG_TICKED	; assume atomic

#if DO_ADC
	;; Check if ADC conversion finished, if so set new intensity target value
	;; and start a new ADC conversion
	call	setIntensityFromADC
#endif
	;; Increment time counter if required
	;; Time counter is in r24, increased 62.5 times per second ==
	;; 18750 == 0x493e times per 5 minutes
	ldi	REG_SCRATCH_4,	hi8( TICKS_PER_STEP - 1 )
	;; CLI: make sure REG_TICK_COUNTER_HIGH, LOW don't change while comparing
	cli			
	cpi	REG_TICK_COUNTER_LOW, lo8( TICKS_PER_STEP - 1 ) ; compare with immediate
	cpc	REG_TICK_COUNTER_HIGH, REG_SCRATCH_4		; compare with carry
	sei
	;; Want branch if less than
	brlt	noNewTime		; branch if minus
	;; 	brcs	noNewTime		; branch if minus

	;;
	;; Subtract ticks from tick counter
	;; 
	cli
	subi	REG_TICK_COUNTER_LOW, lo8( TICKS_PER_STEP )	; subtract immediate
	sbci	REG_TICK_COUNTER_HIGH, hi8( TICKS_PER_STEP ) ; subtract immediate with carry
	sei
	
	call	incTime
	
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
	
noNewTime:
	;; Only check buttons if tick counter is less than 60 to keep time
	;; from advancing too quicky (tick counter is reset to 0 when time is
	;; changed)
	cpi	REG_TICK_COUNTER_HIGH, 0
	brne	doCheckButtons

	cpi	REG_TICK_COUNTER_LOW, 60
	brlo	doneButtons
	
	;; 	rjmp	loop

doCheckButtons:	
	;; Check buttons. All buttons are on port C

	in	REG_SCRATCH_4, BUTTON_PIN
	;; 	mov	REG_SCRATCH_1, REG_SCRATCH_4
	;; Temporarily remov debounce
	;; 	or	REG_SCRATCH_4, REG_PREV_BUTTON_STATE
	;; 	mov	REG_PREV_BUTTON_STATE, REG_SCRATCH_1
	
#if TIME_STEP_BUTTONS
	sbrc	REG_SCRATCH_4, BUTTON_PIN_INC_TIME
	rjmp	checkForDecTime

	call	incTime

timeChanged:
	call	clockFace_setStrings
	rjmp	doneButtons

checkForDecTime:
	sbrc	REG_SCRATCH_4, BUTTON_PIN_DEC_TIME
	rjmp	doneButtons

	call	decTime

	rjmp	timeChanged
#else	
	sbrs	REG_SCRATCH_4, BUTTON_PIN_INC_HOUR ; Skip next if bit set
	rjmp	checkForDecHour

	;; Increase hour button pressed this time and last time around
	;; = debounce
	inc	HOURS
	cpi	HOURS,	HOURS_PER_DAY
	brne	noHourWrap

	clr	HOURS

noHourWrap:
doButtonChange:	
	call	clockFace_setStrings
	rjmp	doneButtons

checkForDecHour:
	sbrs	REG_SCRATCH_4, BUTTON_PIN_DEC_HOUR ; Skip next if bit set
	rjmp	checkForIncMinute

	cpi	HOURS,	0
	brne	noHourUnderflow

	ldi	HOURS,	HOURS_PER_DAY - 1
	rjmp	doButtonChange

noHourUnderflow:
	dec	HOURS
	rjmp	doButtonChange

	;; TODO: Mac, implement rest of your buttons here
#endif
	
doneButtons:	
	/* Check LDR, adjust PWM */
	rjmp loop
	
;;;
;;; Increment time by one minute, wrapping hours and minutes as appropriate
;;;
incTime:	
	;; For accurate time setting, zero the counter when time is set.
	;; This is also used to ensure that time is not advanced too fast
	cli
	;; Lines below cause clock to advance quickly even if button not pressed.
	;; Don't know why.
	clr	REG_TICK_COUNTER_LOW
	clr	REG_TICK_COUNTER_HIGH
	sei

	inc	MINS_PAST		; 5 minutes past the hour
	cpi	MINS_PAST, STEPS_PER_HOUR
	brlo	noNewHour		; branch if lower

	inc 	HOURS			; increment hour count
	clr	MINS_PAST
	cpi	HOURS, HOURS_PER_DAY
	brlo	noNewHour
	ldi 	HOURS, 0

noNewHour:
	ret

;;;
;;; Decrement time by one minute step, wrapping hours and minutes as appropriate
;;;
decTime:
	cpi	MINS_PAST,	0
	brne	doDecMinutes

	ldi	MINS_PAST,	MINUTES_PER_STEP - 1

	cpi	HOURS,	0
	brne	doDecHours

	ldi	HOURS,	HOURS_PER_DAY - 1
	rjmp	doneDecTime

doDecHours:
	dec	HOURS
	rjmp	doneDecTime

doDecMinutes:
	dec	MINS_PAST

doneDecTime:
	;; For accurate time setting, zero the counter when time is set.
	;; This is also used to ensure that time is not advanced too fast
	cli
	clr	REG_TICK_COUNTER_LOW
	clr	REG_TICK_COUNTER_HIGH
	sei

	ret
	
;;;
;;; Called 62.5 timer per second to increment tick counter
;;; 
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

	inc	REG_TICKED
	
doneSetting2:
	;;  restore status register
	pop	r0
	out	0x3f, r0
	reti
	
#if DO_ADC
	;; Uses REG_SCRATCH_4, REG_SCRATCH_1
setIntensityFromADC:
	ldi	REG_SCRATCH_4, ADCSRA
	sbrs	REG_SCRATCH_4, ADIF
	ret

	;; Set intensity to (1024-ADC result)*4
	;; 	ldi	REG_SCRATCH_4, 0x04
	;; 	lds	REG_SCRATCH_1, ADCL
	;; 	sub	REG_SCRATCH_4, REG_SCRATCH_1
	;; 	clr	REG_SCRATCH_1
	;; 	lds	REG_SCRATCH_2, ADCH
	;; 	sbc	REG_SCRATCH_1, REG_SCRATCH_2

	lds	REG_TLC_CHANNEL_INTENSITY_LOW, ADCL
	lds	REG_TLC_CHANNEL_INTENSITY_HIGH, ADCH

	;; Start next conversion
	call	adc_start

	cpi	REG_TLC_CHANNEL_INTENSITY_HIGH, 0
	breq	doADCMultiply

	ldi	REG_TLC_CHANNEL_INTENSITY_LOW, 0xff
	ldi	REG_TLC_CHANNEL_INTENSITY_HIGH, 0x0f
	rjmp	setNewIntensities

doADCMultiply:
	push	XL
	push	XH
	
	ldi	XL,	lo8( intensityCounter )
	ldi	XH,	hi8( intensityCounter )

	ld	REG_TLC_CHANNEL_INTENSITY_LOW, X+
	ld	REG_TLC_CHANNEL_INTENSITY_HIGH, X

	adiw	REG_TLC_CHANNEL_INTENSITY_LOW, 1

	ldi	XL,	lo8( intensityCounter )
	ldi	XH,	hi8( intensityCounter )

	st	X+, REG_TLC_CHANNEL_INTENSITY_LOW
	st	X+, REG_TLC_CHANNEL_INTENSITY_HIGH

	pop	XH
	pop	XL

	;; 	ldi	REG_TLC_CHANNEL_INTENSITY_LOW,
	;; 	ldi	REG_TLC_CHANNEL_INTENSITY_HIGH, 0x01
	rjmp	setNewIntensities

	;; Check if > 256, if so set max intensity
	;; Multiply by 16 to get proper range
	lsl	REG_TLC_CHANNEL_INTENSITY_LOW
	rol	REG_TLC_CHANNEL_INTENSITY_HIGH

	lsl	REG_TLC_CHANNEL_INTENSITY_LOW
	rol	REG_TLC_CHANNEL_INTENSITY_HIGH
	
	lsl	REG_TLC_CHANNEL_INTENSITY_LOW
	rol	REG_TLC_CHANNEL_INTENSITY_HIGH
	
	lsl	REG_TLC_CHANNEL_INTENSITY_LOW
	rol	REG_TLC_CHANNEL_INTENSITY_HIGH

setNewIntensities:
	;; 	mov	REG_CHANNEL_INTENSITY_LOW, REG_TLC_CHANNEL_INTENSITY_LOW
	;; 	mov	REG_CHANNEL_INTENSITY_HIGH, REG_TLC_CHANNEL_INTENSITY_HIGH
	ldi	REG_SCRATCH_4, 3
	mov	REG_TLC_CHANNEL_NUMBER, REG_SCRATCH_4
	;; TODO: Continue here with fading debugging.
	;; Entire display flickers if we call setChannelTargetIntensity for one
	;; string here. Strange.
	call	TLC_setChannelTargetIntensity
	;; 	call	TLC_setNewTargetIntensity

	ret

.data
	.comm	intensityCounter, 2
#endif
.end
