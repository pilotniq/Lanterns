;;;
;;; Code for Erland's Swedish Word Clock with 5 minute resolution, to set the
;;; proper LED strings on depending on the time.
;;;
;; Channels: 31 = ÖV (över)
;;           30 = HA (halv)
;;; 	     29 = RT (kvart)        24, 25, 26, 21, 29, 31, 18, 16
;;	     28 = TIO
;;; 	     27 = GO (tjugo)
;;; 	     26 = N ÄR (klockan är)
;;; 	     25 = KLO (klockan är)
;;; 	     24 = CKA (klockan är)
;;; 	     23 = TJU (tjugo)
;;;          22 = FEM
;;; 	     21 = KVA
;;;          20 = I
;;;          19 = LV (halv)
;;;          18 = ER (över)
;;;          17 = ETT
;;; 	     16 = TVÅ
;;;          15 = LV (tolv)
;;; 	     14 = SJU
;;;          13 = VA (ELVA)
;;;          12 = TIO (timme)
;;;          11 = ÅT (åtta)
;;;          10 = FEM (timme)
;;;           9 = ?
;;;           8 = ?
;;;           7 = TA (åtta)
;;;           6 = TRE
;;;           5 = SEX
;;;           4 = ?
;;;           3 = TO (tolv)
;;;           2 = NIO
;;;           1 = ?
;;;           0 = ?
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
/*	mov	REG_TLC_CHANNEL_INTENSITY_LOW, REG_CHANNEL_INTENSITY_LOW
	mov	REG_TLC_CHANNEL_INTENSITY_HIGH, REG_CHANNEL_INTENSITY_HIGH

	;; channels 24, 25, 26
	ldi	REG_SCRATCH_4, 24
	mov	REG_TLC_CHANNEL_NUMBER, REG_SCRATCH_4
	call	TLC_setChannelTargetIntensity

	inc	REG_TLC_CHANNEL_NUMBER
	call	TLC_setChannelTargetIntensity
	
	inc	REG_TLC_CHANNEL_NUMBER
	call	TLC_setChannelTargetIntensity
	*/
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

	ldi	REG_SCRATCH_4, 18	; Channel number of first channel
	mov	REG_SCRATCH_2, REG_SCRATCH_4
	
	lpm	REG_SCRATCH_1, Z+ ; REG_SCRATCH_1 now has low byte of string

	call	clockFace_setOffChannels
	;;
	;; When we get here, the first 8 variable channels (3-10) which should
	;; be off have been turned off
	;;
	;; Handle the remaining six minute channels
	;;
	ldi	REG_SCRATCH_4, 5	     ; should this be 26 (18+8)?
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

	ldi	REG_SCRATCH_4, 18
	mov	REG_SCRATCH_2, REG_SCRATCH_4 ; First channel
	
	lpm	REG_SCRATCH_1, Z+ ; REG_SCRATCH_1 now has low byte of string

	call	clockFace_setOnChannels

	ldi	REG_SCRATCH_4, 5
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
	
	ldi	REG_SCRATCH_4, 2 ; Channel number of first channel
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

	;;
	;; Set desired on intensity
	;; 
	mov	REG_TLC_CHANNEL_INTENSITY_LOW, REG_CHANNEL_INTENSITY_LOW
	mov	REG_TLC_CHANNEL_INTENSITY_HIGH, REG_CHANNEL_INTENSITY_HIGH

	ldi	REG_SCRATCH_4, 8 ; Counter
	mov	REG_SCRATCH_3, REG_SCRATCH_4 ; Counter

	ldi	REG_SCRATCH_4, 2 ; First channel
	mov	REG_SCRATCH_2, REG_SCRATCH_4 ; First channel
	
	lpm	REG_SCRATCH_1, Z+ ; REG_SCRATCH_1 now has low byte of string

	call	clockFace_setOnChannels

	ldi	REG_SCRATCH_4, 8 ; Counter
	mov	REG_SCRATCH_3, REG_SCRATCH_4 ; Counter

	lpm	REG_SCRATCH_1, Z+ ; REG_SCRATCH_1 now has high byte of string

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
;;; Minute strings are channels 18 and up
	;;          33222222222211
	;;          10987654321098
	.word	0b0000000111000000 ; on the hour
	.word	0b0010000111010001 ; five past the hour (fem över) 0x184
	.word	0b0010010111000001 ; ten past the hour  (tio över)
	.word	0b0010100111001001 ; quarter past the hour (kvart över)
	.word	0b0010001111100001 ; twenty past the hour  (tjugo över)
	.word   0b0001000111010110 ; twenty five past the hour (fem i halv)
	.word   0b0001000111000010 ; half past ("halv")
	.word   0b0011000111010011 ; 35 minutes past (fem över halv)
	.word   0b0000001111100100 ; 40 minutes past (tjugo i)
	.word   0b0000100111001100 ; 45 minutes past (kvart i)
	.word	0b0000010111000100 ; 50 minutes past (tio i)
	.word   0b0000000111010100 ; 55 minutes past (fem i)

	;; There are 16 strings related to hours. Strings 2-17
hourStringData:
	;;        7654321098765432
	.word   0b0010000000000010 ; Midnight = tolv
	.word   0b1000000000000000 ; ett
	.word   0b0100000000000000 ; två
	.word   0b0000000000010000 ; tre
	.word   0b0000000011000000 ; find fyra
	.word   0b0000000100000000 ; fem
	.word   0b0000000000001000 ; sex
	.word   0b0001000000000000 ; sju
	.word   0b0000001000100000 ; åtta
	.word   0b0000000000000001 ; nio
	.word   0b0000010000000000 ; tio
	.word   0b0000100000000100 ; elva	
.end
	