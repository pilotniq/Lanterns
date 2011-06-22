all: flash-erl

CC = avr-gcc
AS = avr-as
#ASFLAGS = -mmcu=atmega168
#ASFLAGS = -Wa,mmcu=atmega168
LD = avr-ld
LDFLAGS = -nostdlib
# USBPORT = /dev/parport0
USBPORT = /dev/tty.usbserial-A6008gHF
AVRDUDE_PARAMS = -b 19200
simavr = ../simavr
IPATH = -I${simavr}/include -I${simavr}/simavr/sim

LDFLAGS=${simavr}/simavr/obj-x86_64-linux-gnu/libsimavr.a -lpthread -lelf
CFLAGS=-mmcu=atmega168 -g
ASFLAGS=-mmcu=atmega168 -g
#include ${simavr}/Makefile.common

board_lantern: board_lantern.c
	gcc -std=c99 $(IPATH) board_lantern.c -o board_lantern $(LDFLAGS)

main.o:	main.S
tlc.o:	tlc.S config.h
tlcTest.o: tlcTest.S config.h
clockCommon.o: clockCommon.S reg_mnemonics.h m168.h
erlClock.o: erlClock.S reg_mnemonics.h
adc.o: adc.S reg_mnemonics.h m168.h
ch31TestMain.o: ch31TestMain.S
erlClockTest.o: erlClockTest.S

testCh31: ch31TestMain.o erlClockTest.o tlc.o clockCommon.o
	avr-ld -nostdlib ch31TestMain.o erlClockTest.o clockCommon.o tlc.o -o testCh31

tlcTest: tlcTest.o tlc.o
	avr-ld -nostdlib tlcTest.o tlc.o -o tlcTest

adcTest: adcTest.o tlc.o adc.o
	avr-ld -nostdlib adcTest.o adc.o tlc.o -o adcTest

wordClock-erl: main.o tlc.o clockCommon.o erlClock.o adc.o
	avr-ld -nostdlib main.o tlc.o clockCommon.o erlClock.o adc.o -o wordClock-erl

wordClock-erl.hex: wordClock-erl
	avr-objcopy -O ihex wordClock-erl wordClock-erl.hex

tlcTest.hex: tlcTest
	avr-objcopy -O ihex tlcTest tlcTest.hex

adcTest.hex: adcTest
	avr-objcopy -O ihex adcTest adcTest.hex

testCh31.hex: testCh31
	avr-objcopy -O ihex testCh31 testCh31.hex

tlctest-flash: tlcTest.hex
	avrdude -c avrisp -p m168 -P $(USBPORT) $(AVRDUDE_PARAMS) -U flash:w:tlcTest.hex

testCh31-flash: testCh31.hex
	avrdude -c avrisp -p m168 -P $(USBPORT) $(AVRDUDE_PARAMS) -U flash:w:testCh31.hex

adcTest-flash: adcTest.hex
	avrdude -c avrisp -p m168 -P $(USBPORT) $(AVRDUDE_PARAMS) -U flash:w:adcTest.hex

flash-erl: wordClock-erl.hex
	avrdude -c avrisp -p m168 -P ${USBPORT} ${AVRDUDE_PARAMS} -U flash:w:wordClock-erl.hex

fuse:
	avrdude -c avrisp -p m168 -P ${USBPORT} ${AVRDUDE_PARAMS} -U lfuse:w:0xb7:m -U hfuse:w:0xdf:m -U efuse:w:0xf8:m

clean:
	rm *~ *.o *.hex wordClock-erl
