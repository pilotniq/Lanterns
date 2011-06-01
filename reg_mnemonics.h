/*
 * Scratch variable, may be used in any interrupt handler
 */
#define REG_I_SCRATCH_R0 r0
#define REG_I_SCRATCH_R1 r1
/*
 * used in TLC_spiTimerInterrupt
 */
#define REG_I_CHANGE_COUNTER r2
/* Set in tlcInit, R/W in TLC_spiInterrupt */
/* SPI byte index. Starts at max + 1, then decremented */
#define REG_I_G_SPI_BYTE_INDEX r3
/* REG_CHANNEL_INTENSITY_x contains the desired intensity for the current 
   ambient light level */
#define REG_CHANNEL_INTENSITY_LOW r4
#define REG_CHANNEL_INTENSITY_HIGH r5
#define REG_I_SPI_BYTE_TYPE r6
#define REG_SCRATCH_1 r7
#define REG_SCRATCH_2 r8
#define REG_SCRATCH_3 r9
#define REG_SCRATCH_4 r16
#define MINS_PAST r17
#define HOURS r18

#define REG_I_G_SPI_POINTER r11
#define REG_I_G_SPI_POINTER_LOW r11
#define REG_I_G_SPI_POINTER_HIGH r12

/* 62.5Hz time counter */
#define REG_TICK_COUNTER	r20
#define REG_TICK_COUNTER_LOW	r20
#define REG_TICK_COUNTER_HIGH	r21
/*
 * Parameters to TLC functions
 */
#define REG_TLC_CHANNEL_NUMBER r10
#define REG_TLC_CHANNEL_INTENSITY_LOW r22
#define REG_TLC_CHANNEL_INTENSITY_HIGH r23

/* 
 * Used for loop in TLC_spiTimerInterrupt.
*/
#define REG_I_CHANNEL_INDEX r19
/*
 * Used in TLC SPI Timer interrupt for storing current LED value
 * I in name stands for interrupt time variable
 */
#define REG_I_LED_CURRENT_LOW r24
#define REG_I_LED_CURRENT_HIGH r25
/*
 * Two below used in TLC_spiInterrupt (so can use same regs as stuff in 
 * TLC_spiTimerInterrupt)
 */
#define REG_I_FIRST_BYTE r24
#define REG_I_SECOND_BYTE r25

#define XL r26
#define XH r27
#define YL r28
#define YH r29
#define ZL r30
#define ZH r31

