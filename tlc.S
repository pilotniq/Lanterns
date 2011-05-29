;; ****************************************************************************
;; Erl's code to drive one or more TLC5940 LED driver chips
;; In GNU Assembler for AVR ATMega168s
;;
;; Registers used:
;;   r0, r7, r8, r9 interrupt time scratch
;;   r2 = SPI Channel index
;;   r6 = SPI Byte type (0-2)
;;   r21, r22 scratch for interrupt handling
;;
;;   r24:r25	Scratch for interrupt handling
;;   r26:r27 = X Used interrupt time to index current values (but pushed)
;;   r28:r29 = Y Used interrupt time to index target values
;;   r30:r31 = Z Used in SPI to point into current
;; ****************************************************************************


;; INCLUDES
.include "m168.h"
#include "reg_mnemonics.h"
.include "config.h"


;; GLOBAL SYMBOLS for linking with other code
.global	TLC_init
.global TLC_spiInterrupt
.global TLC_spiTimerInterrupt


;; TLC5940 PIN DEFINITIONS
.equ	SCLK_PORT,	PORTB	; Serial data shift clock.
.equ	SCLK_PIN,	5
.equ	GSCLK_PORT,	PORTB	; PWM reference clock
.equ	GSCLK_PIN,	0
.equ	XLAT_PORT,	PORTB	; Latch: HIGH sends data to DC og GS registers.
.equ	XLAT_PIN,	1
.equ	BLANK_PORT,	PORTB	; Blank all outputs. LOW = PWM active.
.equ	BLANK_PIN,	2
.equ	DCPRG_PORT,	PORTD	; When DCPRG = H, DC changes DC register.
.equ	DCPRG_PIN,	4
.equ	VPRG_PORT,	PORTD	; When VPRG = GND, the device is in GS mode.
.equ	VPRG_PIN,	7


.text

TLC_init:
	;; Init TLC5940 control pin values (cbi = clear bit)
	cbi	DCPRG_PORT,	DCPRG_PIN
	cbi	VPRG_PORT,	VPRG_PIN
	cbi	XLAT_PORT,	XLAT_PIN

	;; Start display blanked until time has been set (sbi = set bit)
	sbi	BLANK_PORT,	BLANK_PIN

	;; PB4 = MISO is input, others output
	ldi	r16,	0b11101111	; ldi = load immediate
	out	DDRB,	r16		; Set port B to all outputs, except MISO
	ser	r16			; Sets r16 to 0xff (ser = set to 0xFF)
	out	DDRD,	r16		; Set port D to all outputs

	;; Enable SPI, set clock rate fck/2, idle low, data on rise
	;; The setting of the clock is bits 0,1 of SPCR and bit 0 of SPSR
	ldi	r16,	0b11010000
	out	SPCR,	r16		; SPCR = SPI control register
	out	SPSR,	0b00000001	; SPSR = SPI status register

	;; Setup timer A for SPI
	ldi	r16, 	0b11000010	; Set OC2A on match, No OC2, CTC Mode
	sts	TCCR2A, r16		; TCCR = Timer/counter control register
	ldi	r16, 	3		; Set comparison value for timer A
	sts	OCR2A, r16		; OCR = Output compare register

	;; Setup timer B
	ldi	r16, 	0b00000111
	sts	TCCR2B, r16		; Select prescaler 1024, turn on

	;; Enable interrupt on compare A (OCIE2A bit)
	ldi	r16,	0b00000010
	sts	TIMSK2, r16

	;; Reset the GS data
	ldi	r16,		2
	mov	HAVE_NEW_DATA,	r16	; we want two updates of gs data

	;; then just blanks
/*	cbi	BLANK_PORT, BLANK_PIN */

	;; initialize current values to 1 and target values to 0. Will cause
	;; initial refresh of all values to 0.
	;; Must initialize current and target to 0 here, unless RAM is 0
	;; by default

	ldi	ZH,	hi8( currentChannelValues )
	ldi	ZL,	lo8( currentChannelValues )
	ldi	r16,	2 * 16 * NUMBER_TLC_CHIPS
	ldi	r19,	0
	
initCurrentValuesLoop:
	dec	r16
	breq	doneInitCurrentValues

	ldi	r19,	0	; High word to 0
	st	Z+,	r19
	ldi	r19,	1	; Low word to 1
	st	Z+,	r19
	rjmp	initCurrentValuesLoop

doneInitCurrentValues:
	ldi	ZH,	hi8( targetChannelValues )
	ldi	ZL,	lo8( targetChannelValues )
	ldi	r16,	2 * 16 * NUMBER_TLC_CHIPS
	ldi	r19,	0
initTargetValuesLoop:	
	dec	r16
	breq	doneInitTargetValues

	st	Z+,	r19
	rjmp	initTargetValuesLoop

doneInitTargetValues:	
	clr	REG_I_SPI_BYTE_INDEX

	ret				; return from subrutine

;; Should send next byte if there is more data to be sent
TLC_spiInterrupt:
	in	REG_I_SCRATCH_R0,	SREG	; copy status register to r0
	push	REG_I_SCRATCH_R0	; push status register = r0
	push	XL			; push X register lo byte
	push	XH			; push X register hi byte

	;; Move on to the next TLC channel
	dec	REG_I_SPI_BYTE_INDEX
	brne	spiSendNext		; done!

	;; Sent last byte. Now make blank high to stop PWM, pulse XLAT,
	;; make blank low
	sbi	BLANK_PORT, BLANK_PIN

	;; XLAT pulse minimum duration is 20 ns. One clock @ 16 MHz is 62 ns.
	;; No problem.
	sbi	XLAT_PORT, XLAT_PIN
	cbi	XLAT_PORT, XLAT_PIN

	cbi	BLANK_PORT, BLANK_PIN ; Start new PWM cycle
	
	rjmp	spiReturn

spiSendNext:
	;; REG_I_SPI_BYTE_INDEX contains index of byte to send.
	;;
	;; Byte 0: high byte of channel 0 intensity
	;; Byte 1: low nybble of channel 0 intensity, high nybble of channel 1
	;; Byte 2: low byte of channel 1
	;;
	;; Repeat
	;;
	;; Call Byte 0 type 2, Z points to high byte of ch0, send nybble
	;; Call byte 1 type 1, Z points to low byte of ch0
	;; Call byte 2 type 0, Z points to low byte of ch1
	;;
	;; Current values stored in big endian byte format.
	;;
	;; Track byte type in one register, channel index in another, drop
	;; byte counter. Start with highest channel.
	clr	REG_I_SCRATCH_R0
	cp	REG_I_SPI_BYTE_TYPE,	r0
	brne	nextByteTypeNot0

	ld	REG_I_FIRST_BYTE,	Z+

	;; next byte type will be 2
	ldi	REG_I_SECOND_BYTE,	2
	mov	REG_I_SPI_BYTE_TYPE,	REG_I_SECOND_BYTE

	rjmp	sendByte

nextByteTypeNot0:
	inc	REG_I_SCRATCH_R0 ; was 0 above, is now 1
	cp	REG_I_SPI_BYTE_TYPE,	REG_I_SCRATCH_R0
	
	brne	nextByteTypeIs2
	;; Byte type is 1, Z points to low byte. was r22
	ld	REG_I_FIRST_BYTE,	Z+
	;; Z now points to high byte of next channel
	;; 
	lsl	REG_I_FIRST_BYTE
	lsl	REG_I_FIRST_BYTE
	lsl	REG_I_FIRST_BYTE
	lsl	REG_I_FIRST_BYTE

	ld	REG_I_SECOND_BYTE,	Z+

	or	REG_I_FIRST_BYTE,	REG_I_SECOND_BYTE
	dec	REG_I_SPI_BYTE_TYPE

	rjmp	sendByte	; one way of saying "goto" (uncondit. branch)

nextByteTypeIs2:
	ld	REG_I_FIRST_BYTE,	Z+ ; high nybble of ch0 in low nybble

	lsl	REG_I_FIRST_BYTE
	lsl	REG_I_FIRST_BYTE
	lsl	REG_I_FIRST_BYTE
	lsl	REG_I_FIRST_BYTE

	ld	REG_I_SECOND_BYTE,	Z ; second nybble of ch0 in high nybble

	lsr	REG_I_SECOND_BYTE
	lsr	REG_I_SECOND_BYTE
	lsr	REG_I_SECOND_BYTE
	lsr	REG_I_SECOND_BYTE

	or	REG_I_FIRST_BYTE, REG_I_SECOND_BYTE

	dec	REG_I_SPI_BYTE_TYPE

sendByte:
	out	SPDR,	REG_I_FIRST_BYTE	; SPDR = SPI data register

spiReturn:
	;;  restore status register
	pop	XH
	pop	XL
	pop	REG_I_SCRATCH_R0
	out	SREG, 	REG_I_SCRATCH_R0		; reset status register

	reti				; return from interrupt

;;;
;;; If new data, initiate SPI transfer
;;; Else just pulse blank
;;;
TLC_spiTimerInterrupt:
	;; save status byte
	in	REG_I_SCRATCH_R0, SREG
	push	REG_I_SCRATCH_R0
	push	XL
	push	XH

	;;
	;; Check if the system is sending serial data, if so return immediately
	;; 
	tst	REG_I_SPI_BYTE_INDEX
	brne	returnFromInterrupt
	
	;; Check if any diffs are not zero
	;; X = r26:r27 current value
	;; Y = r28:r29 target value
	ldi	XL,	lo8( currentChannelValues )
	ldi	XH,	hi8( currentChannelValues )

	ldi	YL,	lo8( targetChannelValues )
	ldi	YH,	hi8( targetChannelValues )

	ldi	REG_I_CHANNEL_INDEX,	16 * NUMBER_TLC_CHIPS

	clr	REG_I_CHANGE_COUNTER		; R2 is change counter

checkDiffsLoop:
	/* Calculate target - current */
	ld	REG_I_SCRATCH_R1,	Y+	; r0=Target High byte
	ld	REG_I_LED_CURRENT_HIGH,	X+	; r0=Current High byte

	ld	REG_I_SCRATCH_R0,	Y+	; Target Low byte
	ld	REG_I_LED_CURRENT_LOW,	X+	; Current High byte
	
	sub	REG_I_SCRATCH_R0, REG_I_LED_CURRENT_LOW	; r0=lo8(target-current)
	sbc	REG_I_SCRATCH_R1, REG_I_LED_CURRENT_HIGH	; r1=hi8(target-current)

	brne	modify

doneModifying:
	dec	REG_I_CHANNEL_INDEX
	brne	checkDiffsLoop

	rjmp	allUpdated

modify:
	;; Update the current values and the diffs
	;; Minus status bit should be set here if the target is less than
	;; the current.
	brmi	decrease

	inc	REG_I_CHANGE_COUNTER
	sbiw	XL,	2	; r26=X Move x ptr back to value we just compared
	adiw	REG_I_LED_CURRENT_LOW,	1
	st	X+,	REG_I_LED_CURRENT_HIGH ; Note: stored big endian
	st	X+,	REG_I_LED_CURRENT_LOW

	rjmp	doneModifying

decrease:
	inc	REG_I_CHANGE_COUNTER
	
	sbiw	XL,	2	; Move x ptr back to value we just compared
	sbiw	REG_I_LED_CURRENT_LOW,	1
	st	X+,	REG_I_LED_CURRENT_HIGH
	st	X+,	REG_I_LED_CURRENT_LOW

	rjmp	doneModifying

allUpdated:
	tst	REG_I_CHANGE_COUNTER
	breq	allDiffsZero

	rjmp	startSending

allDiffsZero:
	;; No new grayscale data, just pulse blank
	sbi	BLANK_PORT, BLANK_PIN
	cbi	BLANK_PORT, BLANK_PIN
	rjmp	returnFromInterrupt

	;;
	;; Executed at interrupt time
	;;
startSending:
	dec	r3		; decrement counter of times to write

	ldi	ZL,	lo8(currentChannelValues)
	ldi	ZH,	hi8(currentChannelValues)

	;; REG_I_SPI_BYTE_INDEX counts sent bytes. 16 channel values are
	;; packed in 24 bytes.
	ldi	REG_I_CHANNEL_INDEX,	24 * NUMBER_TLC_CHIPS 
	mov	REG_I_SPI_BYTE_INDEX,	REG_I_CHANNEL_INDEX

	clr	REG_I_SPI_BYTE_TYPE	; Set byte type to 1 by first setting
	inc	REG_I_SPI_BYTE_TYPE	; to 0 and then inc, due to reg limits
	
	ld	REG_I_FIRST_BYTE,	Z+ ; Hi byte of current value

	lsl	REG_I_FIRST_BYTE
	lsl	REG_I_FIRST_BYTE
	lsl	REG_I_FIRST_BYTE
	lsl	REG_I_FIRST_BYTE

	ld	REG_I_SECOND_BYTE,	Z

	lsr	REG_I_SECOND_BYTE
	lsr	REG_I_SECOND_BYTE
	lsr	REG_I_SECOND_BYTE
	lsr	REG_I_SECOND_BYTE

	or	REG_I_FIRST_BYTE, REG_I_SECOND_BYTE
	out	SPDR,	REG_I_FIRST_BYTE	; Initiates transmission

returnFromInterrupt:
	pop	XH
	pop	XL
	;;  restore status register
	pop	REG_I_SCRATCH_R0
	out	0x3f, REG_I_SCRATCH_R0

	reti

;;;
;;; Actual API
;;;
;;; Parameters: channel number in r10, intensity in r11:r12
;;; Uses r10. Modifies REG_TLC_CHANNEL_NUMBER ! 
;;;
TLC_setChannelTargetIntensity:
	.global TLC_setChannelTargetIntensity

	ldi	XL,	lo8( targetChannelValues )
	ldi	XH,	hi8( targetChannelValues )

	lsl	REG_TLC_CHANNEL_NUMBER
	add	XL,	REG_TLC_CHANNEL_NUMBER
	adc	XH,	0

	st	X+,	REG_TLC_CHANNEL_INTENSITY_HIGH
	st	X+,	REG_TLC_CHANNEL_INTENSITY_LOW

	ret

	.data
	.org	0x100
	;;
	;; <number of channels> * 16 bits. (bits 15..x contain intensity sent
	;; to TLC. In other words, shift right 4 times to get value to be sent.
	;;
	;; Stored big-endian to make sending to TLC chip algorithm easier
	;;
	.comm	currentChannelValues, (2 * 16 * NUMBER_TLC_CHIPS)

	;;
	;; 16 bit signed differences between desired value and current value
	;;
	;; Stored big-endian to be consistend with currentChannelValues
	;;

	.comm	targetChannelValues, 2 * 16 * NUMBER_TLC_CHIPS

	.end
