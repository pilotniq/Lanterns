;;; ****************************************************************************
;;; Erl's code for ADC on ATMega168 for the Light Dependent Resistor (LDR) on
;;; a Word Clock. In GNU Assembler for AVR ATMega168
;;; ****************************************************************************

.include "m168.h"
#include "reg_mnemonics.h"
		
;; GLOBAL SYMBOLS for linking with other code
.global	adc_init
.global adc_start
.global adc_wait
	
;;; adc_init: sets up Analog To Digital Converter
;;; uses registers REG_SCRATCH_1, REG_SCRATCH_4
adc_init:	
	;;
	;; ADC Setup
	;;
	;; 1.1V reference, input 0
	;; ldi	REG_SCRATCH_4, 0b11000000
	;; AREF, input 0
	ldi	REG_SCRATCH_4, 0b00000000
	sts	ADMUX, REG_SCRATCH_4
	;; Enable ADC, no interrupts, /128 prescaler
	ldi	REG_SCRATCH_4, 0b10000111
	sts	ADCSRA, REG_SCRATCH_4
	;; ACME=Analog Comparator Multiplexer Enable
	ldi	REG_SCRATCH_4, 0
	sts	ADCSRB, REG_SCRATCH_4

	;; Switch pull-up resistor off for analog in 0
	cbi	PORTC, 0

	;; Set analog 0 as input
	cbi	DDRC,  0
	
	;; Disable digital input buffer on ADC pin 0 to save power
	ldi	REG_SCRATCH_4, 1
	sts	DIDR0, REG_SCRATCH_4

	ret

adc_start:
	;;
	lds	REG_SCRATCH_4, ADCSRA
	sbr	REG_SCRATCH_4, (1<<ADSC)
	sts	ADCSRA, REG_SCRATCH_4	; Start conversion
	
	ret

;;; Returns when ADC conversin is complete
adc_wait:
	ldi	REG_SCRATCH_4, ADCSRA
	sbrs	REG_SCRATCH_4, ADIF
	rjmp	adc_wait

	ret

	.end