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
#include "config.h"

#define	DO_ADC 1
#define INTERLACE_ADC 1
	
#define INITIAL_INTENSITY 0x00f0

;; CONSTANTS
;; TICKS_PER_STEP is the number of timer0 ticks per TLC test
;; MINUTES_PER_STEP is defined in the relevant config.h file
;; 16000000 / (1024 * 255) timer ticks per second * 60 * 60
;; For some reaseon, doesn't work properly with TSECONDS 10 or lower.
.equ	TSECONDS_PER_TEST, 12
.equ	TICKS_PER_STEP, 18750
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
	rjmp	timerInterrupt	  	;; Timer 0 overflow
.org SPIaddr * 2
	rjmp TLC_spiInterrupt
.org INT_VECTORS_SIZE * 2

init:
	;; PORT SETUP
	
	;; set outputs before port direction, so values will be correct on
	;; switch
	call	adc_init
	call	adc_start
	
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

	call	adc_wait
	call	setIntensityFromADC
	
	mov	REG_CHANNEL_INTENSITY_LOW, REG_TLC_CHANNEL_INTENSITY_LOW
	mov	REG_CHANNEL_INTENSITY_HIGH, REG_TLC_CHANNEL_INTENSITY_HIGH
	call	clockFace_init
	call	clockFace_setStrings

	;; Everything set up, enable interrupts
	sei			; Enable interrupts

	;; 16, 18, 21, 24, 25, 26, 29, 31
	
	ldi	REG_SCRATCH_4, 18
	mov	REG_TLC_CHANNEL_NUMBER, REG_SCRATCH_4
	ldi	REG_TLC_CHANNEL_INTENSITY_LOW, 0xff
	ldi	REG_TLC_CHANNEL_INTENSITY_HIGH, 0b00001111
	call	TLC_setChannelTargetIntensity

	ldi	REG_SCRATCH_4, 31
	mov	REG_TLC_CHANNEL_NUMBER, REG_SCRATCH_4
	ldi	REG_TLC_CHANNEL_INTENSITY_LOW, 0xff
	ldi	REG_TLC_CHANNEL_INTENSITY_HIGH, 0b00001111
	call	TLC_setChannelTargetIntensity

	ldi	REG_SCRATCH_4, 1
	mov	REG_TLC_CHANNEL_NUMBER, REG_SCRATCH_4
	ldi	REG_TLC_CHANNEL_INTENSITY_LOW, 0xff
	ldi	REG_TLC_CHANNEL_INTENSITY_HIGH, 0b00001111
	call	TLC_setChannelTargetIntensity

	ldi	REG_SCRATCH_4, 2
	mov	REG_TLC_CHANNEL_NUMBER, REG_SCRATCH_4
	ldi	REG_TLC_CHANNEL_INTENSITY_LOW, 0xff
	ldi	REG_TLC_CHANNEL_INTENSITY_HIGH, 0b00001111
	call	TLC_setChannelTargetIntensity

	ldi	REG_SCRATCH_4, 3
	mov	REG_TLC_CHANNEL_NUMBER, REG_SCRATCH_4
	ldi	REG_TLC_CHANNEL_INTENSITY_LOW, 0xff
	ldi	REG_TLC_CHANNEL_INTENSITY_HIGH, 0b00001111
	;; 	call	TLC_setChannelTargetIntensity

	ldi	REG_SCRATCH_4, 4
	mov	REG_TLC_CHANNEL_NUMBER, REG_SCRATCH_4
	ldi	REG_TLC_CHANNEL_INTENSITY_LOW, 0xff
	ldi	REG_TLC_CHANNEL_INTENSITY_HIGH, 0b00001111
	call	TLC_setChannelTargetIntensity

	ldi	REG_SCRATCH_4, 5
	mov	REG_TLC_CHANNEL_NUMBER, REG_SCRATCH_4
	ldi	REG_TLC_CHANNEL_INTENSITY_LOW, 0xff
	ldi	REG_TLC_CHANNEL_INTENSITY_HIGH, 0b00001111
	call	TLC_setChannelTargetIntensity

	ldi	REG_SCRATCH_4, 6
	mov	REG_TLC_CHANNEL_NUMBER, REG_SCRATCH_4
	ldi	REG_TLC_CHANNEL_INTENSITY_LOW, 0xff
	ldi	REG_TLC_CHANNEL_INTENSITY_HIGH, 0b00001111
	call	TLC_setChannelTargetIntensity

	ldi	REG_SCRATCH_4, 7
	mov	REG_TLC_CHANNEL_NUMBER, REG_SCRATCH_4
	ldi	REG_TLC_CHANNEL_INTENSITY_LOW, 0xff
	ldi	REG_TLC_CHANNEL_INTENSITY_HIGH, 0b00001111
	call	TLC_setChannelTargetIntensity

	ldi	REG_SCRATCH_4, 8
	mov	REG_TLC_CHANNEL_NUMBER, REG_SCRATCH_4
	ldi	REG_TLC_CHANNEL_INTENSITY_LOW, 0xff
	ldi	REG_TLC_CHANNEL_INTENSITY_HIGH, 0b00001111
	call	TLC_setChannelTargetIntensity

	ldi	REG_SCRATCH_4, 9
	mov	REG_TLC_CHANNEL_NUMBER, REG_SCRATCH_4
	ldi	REG_TLC_CHANNEL_INTENSITY_LOW, 0xff
	ldi	REG_TLC_CHANNEL_INTENSITY_HIGH, 0b00001111
	call	TLC_setChannelTargetIntensity

	ldi	REG_SCRATCH_4, 10
	mov	REG_TLC_CHANNEL_NUMBER, REG_SCRATCH_4
	ldi	REG_TLC_CHANNEL_INTENSITY_LOW, 0xff
	ldi	REG_TLC_CHANNEL_INTENSITY_HIGH, 0b00001111
	call	TLC_setChannelTargetIntensity

	ldi	REG_SCRATCH_4, 11
	mov	REG_TLC_CHANNEL_NUMBER, REG_SCRATCH_4
	ldi	REG_TLC_CHANNEL_INTENSITY_LOW, 0xff
	ldi	REG_TLC_CHANNEL_INTENSITY_HIGH, 0b00001111
	call	TLC_setChannelTargetIntensity

	ldi	REG_SCRATCH_4, 12
	mov	REG_TLC_CHANNEL_NUMBER, REG_SCRATCH_4
	ldi	REG_TLC_CHANNEL_INTENSITY_LOW, 0xff
	ldi	REG_TLC_CHANNEL_INTENSITY_HIGH, 0b00001111
	call	TLC_setChannelTargetIntensity

	ldi	REG_SCRATCH_4, 13
	mov	REG_TLC_CHANNEL_NUMBER, REG_SCRATCH_4
	ldi	REG_TLC_CHANNEL_INTENSITY_LOW, 0xff
	ldi	REG_TLC_CHANNEL_INTENSITY_HIGH, 0b00001111
	call	TLC_setChannelTargetIntensity

	ldi	REG_SCRATCH_4, 14
	mov	REG_TLC_CHANNEL_NUMBER, REG_SCRATCH_4
	ldi	REG_TLC_CHANNEL_INTENSITY_LOW, 0xff
	ldi	REG_TLC_CHANNEL_INTENSITY_HIGH, 0b00001111
	call	TLC_setChannelTargetIntensity

	ldi	REG_SCRATCH_4, 15
	mov	REG_TLC_CHANNEL_NUMBER, REG_SCRATCH_4
	ldi	REG_TLC_CHANNEL_INTENSITY_LOW, 0xff
	ldi	REG_TLC_CHANNEL_INTENSITY_HIGH, 0b00001111
	;; 	call	TLC_setChannelTargetIntensity

	ldi	REG_SCRATCH_4, 16
	mov	REG_TLC_CHANNEL_NUMBER, REG_SCRATCH_4
	ldi	REG_TLC_CHANNEL_INTENSITY_LOW, 0xff
	ldi	REG_TLC_CHANNEL_INTENSITY_HIGH, 0b00001111
	call	TLC_setChannelTargetIntensity

	ldi	REG_SCRATCH_4, 17
	mov	REG_TLC_CHANNEL_NUMBER, REG_SCRATCH_4
	ldi	REG_TLC_CHANNEL_INTENSITY_LOW, 0xff
	ldi	REG_TLC_CHANNEL_INTENSITY_HIGH, 0b00001111
	call	TLC_setChannelTargetIntensity

	ldi	REG_SCRATCH_4, 18
	mov	REG_TLC_CHANNEL_NUMBER, REG_SCRATCH_4
	ldi	REG_TLC_CHANNEL_INTENSITY_LOW, 0xff
	ldi	REG_TLC_CHANNEL_INTENSITY_HIGH, 0b00001111
	call	TLC_setChannelTargetIntensity

	ldi	REG_SCRATCH_4, 19
	mov	REG_TLC_CHANNEL_NUMBER, REG_SCRATCH_4
	ldi	REG_TLC_CHANNEL_INTENSITY_LOW, 0xff
	ldi	REG_TLC_CHANNEL_INTENSITY_HIGH, 0b00001111
	call	TLC_setChannelTargetIntensity

	ldi	REG_SCRATCH_4, 20
	mov	REG_TLC_CHANNEL_NUMBER, REG_SCRATCH_4
	ldi	REG_TLC_CHANNEL_INTENSITY_LOW, 0xff
	ldi	REG_TLC_CHANNEL_INTENSITY_HIGH, 0b00001111
	call	TLC_setChannelTargetIntensity

	ldi	REG_SCRATCH_4, 21
	mov	REG_TLC_CHANNEL_NUMBER, REG_SCRATCH_4
	ldi	REG_TLC_CHANNEL_INTENSITY_LOW, 0xff
	ldi	REG_TLC_CHANNEL_INTENSITY_HIGH, 0b00001111
	call	TLC_setChannelTargetIntensity

	ldi	REG_SCRATCH_4, 22
	mov	REG_TLC_CHANNEL_NUMBER, REG_SCRATCH_4
	ldi	REG_TLC_CHANNEL_INTENSITY_LOW, 0xff
	ldi	REG_TLC_CHANNEL_INTENSITY_HIGH, 0b00001111
	call	TLC_setChannelTargetIntensity

	ldi	REG_SCRATCH_4, 23
	mov	REG_TLC_CHANNEL_NUMBER, REG_SCRATCH_4
	ldi	REG_TLC_CHANNEL_INTENSITY_LOW, 0xff
	ldi	REG_TLC_CHANNEL_INTENSITY_HIGH, 0b00001111
	call	TLC_setChannelTargetIntensity

	ldi	REG_SCRATCH_4, 24
	mov	REG_TLC_CHANNEL_NUMBER, REG_SCRATCH_4
	ldi	REG_TLC_CHANNEL_INTENSITY_LOW, 0xff
	ldi	REG_TLC_CHANNEL_INTENSITY_HIGH, 0b00001111
	call	TLC_setChannelTargetIntensity

	ldi	REG_SCRATCH_4, 25
	mov	REG_TLC_CHANNEL_NUMBER, REG_SCRATCH_4
	ldi	REG_TLC_CHANNEL_INTENSITY_LOW, 0xff
	ldi	REG_TLC_CHANNEL_INTENSITY_HIGH, 0b00001111
	call	TLC_setChannelTargetIntensity

	ldi	REG_SCRATCH_4, 26
	mov	REG_TLC_CHANNEL_NUMBER, REG_SCRATCH_4
	ldi	REG_TLC_CHANNEL_INTENSITY_LOW, 0xff
	ldi	REG_TLC_CHANNEL_INTENSITY_HIGH, 0b00001111
	call	TLC_setChannelTargetIntensity

	ldi	REG_SCRATCH_4, 27
	mov	REG_TLC_CHANNEL_NUMBER, REG_SCRATCH_4
	ldi	REG_TLC_CHANNEL_INTENSITY_LOW, 0xff
	ldi	REG_TLC_CHANNEL_INTENSITY_HIGH, 0b00001111
	call	TLC_setChannelTargetIntensity

	ldi	REG_SCRATCH_4, 28
	mov	REG_TLC_CHANNEL_NUMBER, REG_SCRATCH_4
	ldi	REG_TLC_CHANNEL_INTENSITY_LOW, 0xff
	ldi	REG_TLC_CHANNEL_INTENSITY_HIGH, 0b00001111
	call	TLC_setChannelTargetIntensity

	ldi	REG_SCRATCH_4, 29
	mov	REG_TLC_CHANNEL_NUMBER, REG_SCRATCH_4
	ldi	REG_TLC_CHANNEL_INTENSITY_LOW, 0xff
	ldi	REG_TLC_CHANNEL_INTENSITY_HIGH, 0b00001111
	call	TLC_setChannelTargetIntensity

	ldi	REG_SCRATCH_4, 30
	mov	REG_TLC_CHANNEL_NUMBER, REG_SCRATCH_4
	ldi	REG_TLC_CHANNEL_INTENSITY_LOW, 0xff
	ldi	REG_TLC_CHANNEL_INTENSITY_HIGH, 0b00001111
	call	TLC_setChannelTargetIntensity

	ldi	REG_SCRATCH_4, 31
	mov	REG_TLC_CHANNEL_NUMBER, REG_SCRATCH_4
	ldi	REG_TLC_CHANNEL_INTENSITY_LOW, 0xff
	ldi	REG_TLC_CHANNEL_INTENSITY_HIGH, 0b00001111
	call	TLC_setChannelTargetIntensity

loop:
	; Mac: Idle Sleep ??? isn't it ADC noise reduction ???
	; Erl: No. The lowest bit is SE (Sleep enable) the three bits above that
	;      are 0, which is idle sleep mode
#if 0	
	ldi 	r16,	1
	out	SMCR,	r16		; SMCR = Sleep mode control register
	sleep
#endif

doneSetting:
	;;
	;; Check if tick count changed, otherwise loop. 
	;;
#if 1
	ldi	REG_SCRATCH_4,	0
	cp	REG_TICKED,	REG_SCRATCH_4
	breq	loop

	cli
	dec	REG_TICKED	; assume atomic
	sei
#endif
#if 0	
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
#endif
	# re-loop if adc not completed
	ldi	REG_SCRATCH_4, ADCSRA
	sbrs	REG_SCRATCH_4, ADIF
	
	rjmp	loop
	;; 	call	adc_wait
	lds	REG_TLC_CHANNEL_INTENSITY_LOW,	ADCL
	lds	REG_TLC_CHANNEL_INTENSITY_HIGH, ADCH

	call	adc_start
	;;  	cpi	REG_TLC_CHANNEL_INTENSITY_LOW,	70
	;; 	brcc	setMax

	;; 	clr	REG_TLC_CHANNEL_INTENSITY_LOW
	;; 	clr	REG_TLC_CHANNEL_INTENSITY_HIGH
	;; 	rjmp	callSet

	;; Max input should be around 1.1V = 220. Assume 256. So, shift left
	;; 4 times (time 16), max will be 4096.
	;; Multiply by 2^4 = 16
	;; Multiplied by 2 extra to see if it looks better
	lsl	REG_TLC_CHANNEL_INTENSITY_LOW
	rol	REG_TLC_CHANNEL_INTENSITY_HIGH
	lsl	REG_TLC_CHANNEL_INTENSITY_LOW
	rol	REG_TLC_CHANNEL_INTENSITY_HIGH
	lsl	REG_TLC_CHANNEL_INTENSITY_LOW
	rol	REG_TLC_CHANNEL_INTENSITY_HIGH
	lsl	REG_TLC_CHANNEL_INTENSITY_LOW
	rol	REG_TLC_CHANNEL_INTENSITY_HIGH
	lsl	REG_TLC_CHANNEL_INTENSITY_LOW
	rol	REG_TLC_CHANNEL_INTENSITY_HIGH

	;; setMax:
	;; 	ldi	REG_TLC_CHANNEL_INTENSITY_LOW,	0xff
	;; 	ldi	REG_TLC_CHANNEL_INTENSITY_HIGH, 0x0f
callSet:	
	ldi	REG_SCRATCH_4, 1
	mov	REG_TLC_CHANNEL_NUMBER, REG_SCRATCH_4
	call	TLC_setChannelTargetIntensity

	ldi	REG_SCRATCH_4, 2
	mov	REG_TLC_CHANNEL_NUMBER, REG_SCRATCH_4
	call	TLC_setChannelTargetIntensity
	ldi	REG_SCRATCH_4, 3
	mov	REG_TLC_CHANNEL_NUMBER, REG_SCRATCH_4
	call	TLC_setChannelTargetIntensity
	ldi	REG_SCRATCH_4, 4
	mov	REG_TLC_CHANNEL_NUMBER, REG_SCRATCH_4
	call	TLC_setChannelTargetIntensity
	ldi	REG_SCRATCH_4, 5
	mov	REG_TLC_CHANNEL_NUMBER, REG_SCRATCH_4
	call	TLC_setChannelTargetIntensity
	ldi	REG_SCRATCH_4, 6
	mov	REG_TLC_CHANNEL_NUMBER, REG_SCRATCH_4
	call	TLC_setChannelTargetIntensity
	ldi	REG_SCRATCH_4, 7
	mov	REG_TLC_CHANNEL_NUMBER, REG_SCRATCH_4
	call	TLC_setChannelTargetIntensity
	ldi	REG_SCRATCH_4, 8
	mov	REG_TLC_CHANNEL_NUMBER, REG_SCRATCH_4
	call	TLC_setChannelTargetIntensity
	ldi	REG_SCRATCH_4, 9
	mov	REG_TLC_CHANNEL_NUMBER, REG_SCRATCH_4
	call	TLC_setChannelTargetIntensity
	ldi	REG_SCRATCH_4, 10
	mov	REG_TLC_CHANNEL_NUMBER, REG_SCRATCH_4
	call	TLC_setChannelTargetIntensity
	ldi	REG_SCRATCH_4, 11
	mov	REG_TLC_CHANNEL_NUMBER, REG_SCRATCH_4
	call	TLC_setChannelTargetIntensity
	ldi	REG_SCRATCH_4, 12
	mov	REG_TLC_CHANNEL_NUMBER, REG_SCRATCH_4
	call	TLC_setChannelTargetIntensity
	ldi	REG_SCRATCH_4, 13
	mov	REG_TLC_CHANNEL_NUMBER, REG_SCRATCH_4
	call	TLC_setChannelTargetIntensity

	ldi	REG_SCRATCH_4, 15
	mov	REG_TLC_CHANNEL_NUMBER, REG_SCRATCH_4
	call	TLC_setChannelTargetIntensity

	rjmp	loop


	/* sbi	PIND,	6 */
	;; Debug: Gets here
	;;
	;; Do tests here.
	;; Test 0 - 16 is turning the corresponding LED on at full intensity
	;; Test 32 - 63 is fading LED 1 up from 0 to full intensity over one
	;; minute
	;;
	mov	r16,	REG_SCRATCH_4
	andi	r16, 0b11100000 ; test if lower than 16
	brne	testAfter15

	call	adc_wait
	
	mov	REG_TLC_CHANNEL_NUMBER, REG_SCRATCH_4
	ldi	REG_TLC_CHANNEL_INTENSITY_LOW, 0xff
	ldi	REG_TLC_CHANNEL_INTENSITY_HIGH, 0b00001111
	call	TLC_setChannelTargetIntensity

	cpi	REG_SCRATCH_4, 0
	brne	notFirstLED

isFirstLED:
	ldi	r16,	15
	mov	REG_TLC_CHANNEL_NUMBER, r16
	rjmp	setChannelNumber
notFirstLED:	
	;; If not first LED, turn off the previous LED
	mov	REG_TLC_CHANNEL_NUMBER, REG_SCRATCH_4
	dec	REG_TLC_CHANNEL_NUMBER
setChannelNumber:	
	ldi	REG_TLC_CHANNEL_INTENSITY_LOW, 0x00
	ldi	REG_TLC_CHANNEL_INTENSITY_HIGH, 0x00
	call	TLC_setChannelTargetIntensity
	
	inc	REG_SCRATCH_4
	rjmp loop
	
testAfter15:	
	ldi	REG_SCRATCH_4, 0 ; restart tests
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

	cli
	inc	REG_TICKED
	sei
	
doneSetting2:	
	;;  restore status register
	pop	r0
	out	0x3f, r0
	reti

setIntensityFromADC:
	ldi	REG_SCRATCH_4, ADCSRA
	sbrs	REG_SCRATCH_4, ADIF
	
	ret

	;; Max input should be around 1.1V = 220. Assume 256. So, shift left
	;; 4 times (time 16), max will be 4096.
	;; Multiply by 2^4 = 16

	;; Set intensity to (1024-ADC result)*4
	;; 	ldi	REG_SCRATCH_4, 0x04
	;; 	lds	REG_SCRATCH_1, ADCL
	;; 	sub	REG_SCRATCH_4, REG_SCRATCH_1
	;; 	clr	REG_SCRATCH_1
	;; 	lds	REG_SCRATCH_2, ADCH
	;; 	sbc	REG_SCRATCH_1, REG_SCRATCH_2

	lds	REG_TLC_CHANNEL_INTENSITY_LOW, ADCL
	lds	REG_TLC_CHANNEL_INTENSITY_HIGH, ADCH
#if INTERLACE_ADC
	;; Start next conversion
	call	adc_start
#endif
	;; If ADC High byte is 0, set to maximum intensity to prevent
	;; overflow
	cpi	REG_TLC_CHANNEL_INTENSITY_HIGH, 0
	breq	doADCMultiply

	ldi	REG_TLC_CHANNEL_INTENSITY_LOW, 0xff
	ldi	REG_TLC_CHANNEL_INTENSITY_HIGH, 0x0f
	rjmp	setNewIntensities

doADCMultiply:
	;; Calculate 0xff - adc result
	;; multiply by 16

	;; Two's complement
	com	REG_TLC_CHANNEL_INTENSITY_LOW

	;; 	ldi	REG_I_CHANGE_COUNTER, 0xff
	;; 	sub	REG_I_CHANGE_COUNTER, REG_TLC_CHANNEL_INTENSITY_LOW
	lsl	REG_TLC_CHANNEL_INTENSITY_LOW
	rol	REG_TLC_CHANNEL_INTENSITY_HIGH

	lsl	REG_TLC_CHANNEL_INTENSITY_LOW
	rol	REG_TLC_CHANNEL_INTENSITY_HIGH
	
	lsl	REG_TLC_CHANNEL_INTENSITY_LOW
	rol	REG_TLC_CHANNEL_INTENSITY_HIGH
	
	lsl	REG_TLC_CHANNEL_INTENSITY_LOW
	rol	REG_TLC_CHANNEL_INTENSITY_HIGH
	
	rjmp	setNewIntensities
#if 0
	push	XL
	push	XH

	;; What is the intensityCounter?
	ldi	XL,	lo8( intensityCounter )
	ldi	XH,	hi8( intensityCounter )

	;; What is this?
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
#endif
setNewIntensities:
	ldi	REG_SCRATCH_4, 0xff
	mov	REG_CHANNEL_INTENSITY_LOW, REG_SCRATCH_4
	ldi	REG_SCRATCH_4, 0x0f
	mov	REG_CHANNEL_INTENSITY_HIGH, REG_SCRATCH_4
	;; 	mov	REG_CHANNEL_INTENSITY_LOW, REG_TLC_CHANNEL_INTENSITY_LOW
	;; 	mov	REG_CHANNEL_INTENSITY_HIGH, REG_TLC_CHANNEL_INTENSITY_HIGH
	
	ldi	REG_SCRATCH_4, 3
	mov	REG_TLC_CHANNEL_NUMBER, REG_SCRATCH_4
	;; TODO: Continue here with fading debugging.
	;; Entire display flickers if we call setChannelTargetIntensity for one
	;; string here. Strange.
	call	TLC_setChannelTargetIntensity2
	;; 	call	TLC_setNewTargetIntensity

	ret

.end
