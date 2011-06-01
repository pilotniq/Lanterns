;;;
;;; Code for Erland's Swedish Word Clock with 5 minute resolution, to set the
;;; proper LED strings on depending on the time.
;;;

#import "reg_mnemonics.h"
	
.text
	
.global clockFace_init
.global	clockFace_setStrings
	
clockFace_init:
	;; Set the first three strings on ("KLO", "CKA", "N ÄR") 
	;; 
	;; Get the desired intensity due to ambient light, use as parameter to
	;; set TLC intensity
	mov	REG_TLC_CHANNEL_INTENSITY_LOW, REG_CHANNEL_INTENSITY_LOW
	mov	REG_TLC_CHANNEL_INTENSITY_HIGH, REG_CHANNEL_INTENSITY_HIGH

	clr	REG_TLC_CHANNEL_NUMBER
	call	TLC_setChannelTargetIntensity

	inc	REG_TLC_CHANNEL_NUMBER
	call	TLC_setChannelTargetIntensity
	
	inc	REG_TLC_CHANNEL_NUMBER
	call	TLC_setChannelTargetIntensity
	
	ret
	
clockFace_setStrings:
	;; Set strings related to minutes
	;; This will be channel numbers 3,4,5,6,7,8,9,10,11,12,13
	;; Loop twice, first turn channels off, then turn channels on, just to
	;; avoid moving stuff in and out of the TLC parameter registers all the
	;; time.
	
	;;
	;; Load Z with program memory address of minute word
	;;
	ldi	REG_SCRATCH_4, 8
	mov	REG_SCRATCH_3, REG_SCRATCH_4 ; Counter will be decremented
	
	ldi	ZH,	hi8( minuteStringData )
	ldi	ZL, 	lo8( minuteStringData )
	
	mov	REG_SCRATCH_1, MINS_PAST
	;; Multiply minutes past by two to get index into table (because each
	;; entry is two bytes
	lsl	REG_SCRATCH_1
	add	ZL, REG_SCRATCH_1
	clr	REG_SCRATCH_1
	adc	ZH, REG_SCRATCH_1

	push	ZL
	push	ZH		  ; Save
	
	clr	REG_TLC_CHANNEL_INTENSITY_LOW
	clr	REG_TLC_CHANNEL_INTENSITY_HIGH

	ldi	REG_SCRATCH_4, 3	; Channel number of first channel
	mov	REG_SCRATCH_2, REG_SCRATCH_4
	
	lpm	REG_SCRATCH_1, Z+ ; REG_SCRATCH_1 now has low byte of string

	call	clockFace_setOffChannels
	;;
	;; When we get here, the first 8 variable channels (3-10) which should
	;; be off have been turned off
	;;
	;; Handle the remaining three minute channels
	;;
	ldi	REG_SCRATCH_4, 3
	mov	REG_SCRATCH_3, REG_SCRATCH_4 ; Counter

	lpm	REG_SCRATCH_1, Z+ ; REG_SCRATCH_1 now has high byte of string

	call	clockFace_setOffChannels

	;;
	;; When we get here, all channels that should be off have been turned
	;; off.
	pop	ZH
	pop	ZL

	;;
	;; Set desired on intensity
	;; 
	mov	REG_TLC_CHANNEL_INTENSITY_LOW, REG_CHANNEL_INTENSITY_LOW
	mov	REG_TLC_CHANNEL_INTENSITY_HIGH, REG_CHANNEL_INTENSITY_HIGH

	ldi	REG_SCRATCH_4, 8 ; Counter
	mov	REG_SCRATCH_3, REG_SCRATCH_4

	ldi	REG_SCRATCH_4, 3
	mov	REG_SCRATCH_2, REG_SCRATCH_4 ; First channel
	
	lpm	REG_SCRATCH_1, Z+ ; REG_SCRATCH_1 now has low byte of string

	call	clockFace_setOnChannels

	ldi	REG_SCRATCH_4, 3
	mov	REG_SCRATCH_3, REG_SCRATCH_4 ; Counter
	
	lpm	REG_SCRATCH_1, Z+ ; REG_SCRATCH_1 now has high byte of string

	call	clockFace_setOnChannels
	;;
	;; When we get here, all minute channels should be set to their proper
	;; target value. Do the same thing with the hour values
	;;
	;;
	;; Load Z with program memory address of minute word
	;;
	ldi	ZH,	hi8( hourStringData )
	ldi	ZL, 	lo8( hourStringData )
	mov	REG_SCRATCH_1, HOURS
	;;
	;; If minutes past is 5 or greater, use the next hour, because we will
	;; be using "halv" or "i" forms of time.
	;; 
	cpi	MINS_PAST, 5
	brlo	keepHour

	mov	REG_SCRATCH_4, REG_SCRATCH_1
	cpi	REG_SCRATCH_4, 11
	brne	notMidnight

	clr	REG_SCRATCH_1
	rjmp	keepHour
	
notMidnight:
	inc	REG_SCRATCH_1
	
keepHour:	
	;; Multiply hours by two to get index into table (because each
	;; entry is two bytes
	lsl	REG_SCRATCH_1
	add	ZL, REG_SCRATCH_1
	clr	REG_SCRATCH_1
	adc	ZH, REG_SCRATCH_1

	push	ZL
	push	ZH		  ; Save
	
	clr	REG_TLC_CHANNEL_INTENSITY_LOW
	clr	REG_TLC_CHANNEL_INTENSITY_HIGH

	ldi	REG_SCRATCH_4, 8
	mov	REG_SCRATCH_3, REG_SCRATCH_4 ; Counter will be decremented
	
	ldi	REG_SCRATCH_4, 14 ; Channel number of first channel
	mov	REG_SCRATCH_2, REG_SCRATCH_4 ; Channel number of first channel
	
	lpm	REG_SCRATCH_1, Z+ ; REG_SCRATCH_1 now has low byte of string

	call	clockFace_setOffChannels

	ldi	REG_SCRATCH_4, 8
	mov	REG_SCRATCH_3, REG_SCRATCH_4  ; use all 8 bits
	
	lpm	REG_SCRATCH_1, Z+ ; REG_SCRATCH_1 now high byte of bit mask

	call	clockFace_setOffChannels
	;;
	;; When we get here, all hour channels which should be off have been
	;; turned off.
	;;
	;; Turn hour channels on
	;;
	pop	ZH
	pop	ZL

	lpm	REG_SCRATCH_1, Z+ ; REG_SCRATCH_1 now has low byte of string

	;;
	;; Set desired on intensity
	;; 
	mov	REG_TLC_CHANNEL_INTENSITY_LOW, REG_CHANNEL_INTENSITY_LOW
	mov	REG_TLC_CHANNEL_INTENSITY_HIGH, REG_CHANNEL_INTENSITY_HIGH

	ldi	REG_SCRATCH_4, 8 ; Counter
	mov	REG_SCRATCH_3, REG_SCRATCH_4 ; Counter

	ldi	REG_SCRATCH_4, 14 ; First channel
	mov	REG_SCRATCH_2, REG_SCRATCH_4 ; First channel
	
	lpm	REG_SCRATCH_1, Z+ ; REG_SCRATCH_1 now has low byte of string

	call	clockFace_setOnChannels

	ldi	REG_SCRATCH_4, 8 ; Counter
	mov	REG_SCRATCH_3, REG_SCRATCH_4 ; Counter

	lpm	REG_SCRATCH_1, Z+ ; REG_SCRATCH_1 now has low byte of string

	call	clockFace_setOnChannels
	;;
	;; Done!
	;;
	ret
	
	;; There are 11 strings related to minutes
	;; this table has one word (16 bits) to indicate which strings are on
	;;
	;; LSB in each word is for string 3, bit 10 for string d
minuteStringData:
	.word	0x0000
	.word	0x0001
	.word	0x0003
	.word	0x0007
	.word	0x000f
	.word	0x001f
	.word	0x002f
	.word	0x003f
	.word	0x007f
	.word	0x00ff
	.word	0x01ff
	.word	0x03ff
	
	/*
	.word	0x0000		   ; on the hour
	.word	0b0000000110000100 ; five past the hour (fem över) 0x184
	.word	0b0000000110001000 ; ten past the hour  (tio över)
	.word	0b0000000110110000 ; quarter past the hour (kvart över)
	.word	0b0000000110000011 ; twenty past the hour  (tjugo över)
	.word   0b0000011001000100 ; twenty five past the hour (fem i halv)
	.word   0b0000011000000000 ; half past ("halv")
	.word   0b0000011110000100 ; 35 minutes past (fem över halv)
	.word   0b0000000001000011 ; 40 minutes past (tjugo i)
	.word   0b0000000111000000 ; 45 minutes past (kvart i)
	.word	0b0000000001001000 ; 50 minutes past (tio i)
	.word   0b0000000001000100 ; 55 minutes past (fem i)
*/
	;; There are 16 strings related to hours
hourStringData:
	.word   0x0001
	.word   0x0002
	.word   0x0004
	.word   0x0008
	.word   0x0010
	.word   0x0020
	.word   0x0040
	.word   0x0080
	.word   0x0100
	.word   0x0200
	.word   0x0400
	.word   0x0800
	
	/*
	
	.word	0b0110000000000000 ; 12
	.word	0b0000000000000010 ;  1
	.word	0b0000000000000001 ;  2
	.word	0b0000000010000000 ;  3
	.word	0b0000000000001100 ;  4
	.word	0b0000000000010000 ;  5
	.word	0b0000001000000000 ;  6
	.word	0b0001000000000000 ;  7
	.word	0b0000000001100000 ;  8
	.word	0b1000000000000000 ;  9
	.word	0b0000000100000000 ; 10
	.word	0b0000110000000000 ; 11
	*/
.end
	