;;;
;;; clockCommon.S
;;; 
;;; Common functions for setting TLC strings for the clock
;;;
.include "m168.h"
#include "reg_mnemonics.h"

	.text

.global clockFace_setOffChannels
.global clockFace_setOnChannels

;;; Function: setOffChannels
;;; Takes: a bit mask in REG_SCRATCH_1,
;;;  a starting channel number in REG_SCRATCH_2, and
;;;  a bit counter in REG_SCRATCH_3, and
;;;  assumes intensity 0 set in REG_TLC_CHANNEL_INTENSITY
;;; Calls TLC_setChannelTargetIntensity for each bit in the mask that is zero
;;; Increments the channel number
clockFace_setOffChannels:
	; Rotate Right, rightmost bit of REG_SCRATCH_1 ends up in carry
	ror	REG_SCRATCH_1
	brcs	dontTurnOff

	;; turn off the channel
	mov	REG_TLC_CHANNEL_NUMBER, REG_SCRATCH_2
	call	TLC_setChannelTargetIntensity
	
dontTurnOff:
	inc	REG_SCRATCH_2	; Channel number
	dec	REG_SCRATCH_3	; Counter
	brne	clockFace_setOffChannels

	ret
	
;;; Function: setOnhannels
;;; Takes: a bit mask in REG_SCRATCH_1,
;;;  a starting channel number in REG_SCRATCH_2, and
;;;  a counter in REG_SCRATCH_3, and
;;;  assumes intensity 0 set in REG_TLC_CHANNEL_INTENSITY
;;; Calls TLC_setChannelTargetIntensity for each bit in the mask that is zero
clockFace_setOnChannels:
	; Rotate Right, rightmost bit of REG_SCRATCH_1 ends up in carry
	ror	REG_SCRATCH_1
	brcc	dontTurnOn

	;; turn off the channel
	mov	REG_TLC_CHANNEL_NUMBER, REG_SCRATCH_2
	call	TLC_setChannelTargetIntensity
	
dontTurnOn:
	inc	REG_SCRATCH_2	; Channel number
	dec	REG_SCRATCH_3	; Counter
	brne	clockFace_setOnChannels

	ret
	
	.end