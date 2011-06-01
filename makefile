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
CFLAGS=-mmcu=atmega168
ASFLAGS=-mmcu=atmega168
#include ${simavr}/Makefile.common

board_lantern: board_lantern.c
	gcc -std=c99 $(CFLAGS) $(IPATH) board_lantern.c -o board_lantern $(LDFLAGS)

main.o:	main.S
tlc.o:	tlc.S config.h
tlcTest.o: tlcTest.S config.h
clockCommon.o: clockCommon.S reg_mnemonics.h m168.h
erlClock.o: erlClock.S reg_mnemonics.h

tlcTest: tlcTest.o tlc.o
	avr-ld -nostdlib tlcTest.o tlc.o -o tlcTest

wordClock-erl: main.o tlc.o clockCommon.o erlClock.o
	avr-ld -nostdlib main.o tlc.o clockCommon.o erlClock.o -o wordClock-erl

wordClock-erl.hex: wordClock-erl
	avr-objcopy -O ihex wordClock-erl wordClock-erl.hex

tlcTest.hex: tlcTest
	avr-objcopy -O ihex tlcTest tlcTest.hex

tlctest-flash: tlcTest.hex
	avrdude -c avrisp -p m168 -P $(USBPORT) $(AVRDUDE_PARAMS) -U flash:w:tlcTest.hex

flash-erl: wordClock-erl.hex
	avrdude -c avrisp -p m168 -P ${USBPORT} ${AVRDUDE_PARAMS} -U flash:w:wordClock-erl.hex

clean:
	rm *~ *.o *.hex wordClock-erl
