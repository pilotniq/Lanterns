Lanterns - Word clock controller software
=========================================
__Copyright (C) 2011, 2012 Erland Lewin, Mac Ryan__


Description
-----------
Lanterns is the program that runs the core of a word clock. It has 
been written in AVR assembly language, for the ATmega168 µC, using 
__avr-as__ as assembler.

The repo contains different config_xxx.h files that respond to the
specific needs of the two different clocks built by the two 
maintainers.


Licence
-------
This program is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program.  If not, see <http://www.gnu.org/licenses/>.


Circuit
-------
The schematic is available at:

  http://upverter.com/erl/0e9469c201d18d20/WordClock/


DebugWire Debugging with AVR Dragon
-----------------------------------
To debug with an AVR Dragon under Mac OS X, run the following process in one 
window:

avarice --dragon --debugwire --jtag usb --part atmega168 :4242

And in another window:

$ avr-gdb wordClock-erl 
GNU gdb 6.8
Copyright (C) 2008 Free Software Foundation, Inc.
License GPLv3+: GNU GPL version 3 or later <http://gnu.org/licenses/gpl.html>
This is free software: you are free to change and redistribute it.
There is NO WARRANTY, to the extent permitted by law.  Type "show copying"
and "show warranty" for details.
This GDB was configured as "--host=i386-apple-darwin9.8.0 --target=avr"...
(gdb) 
(gdb) target remote localhost:4242
Remote debugging using localhost:4242
