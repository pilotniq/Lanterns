all: flash

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

#include ${simavr}/Makefile.common

board_lantern: board_lantern.c
	gcc -std=c99 $(CFLAGS) $(IPATH) board_lantern.c -o board_lantern $(LDFLAGS)

main.o:	main.S
tlc.o:	tlc.S config.h
tlcTest.o: tlcTest.S config.h

tlcTest: tlcTest.o tlc.o
	avr-ld -nostdlib tlcTest.o tlc.o -o tlcTest

wordClock: main.o tlc.o
	avr-ld -nostdlib main.o tlc.o -o wordClock

wordClock.hex: wordClock
	avr-objcopy -O ihex wordClock wordClock.hex

tlcTest.hex: tlcTest
	avr-objcopy -O ihex tlcTest tlcTest.hex

tlctest-flash: tlcTest.hex
	avrdude -c avrisp -p m168 -P $(USBPORT) $(AVRDUDE_PARAMS) -U flash:w:tlcTest.hex

flash: wordClock.hex
	avrdude -c usbasp -p m168 -P /dev/parport0 -U flash:w:wordClock.hex

clean:
	rm *~ *.o *.hex wordClock
