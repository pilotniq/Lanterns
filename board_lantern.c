/*
        board_lantern.c

	Copied from simavr example
 */

#include <stdlib.h>
#include <stdio.h>
#include <string.h>
#include <unistd.h>
#include <pthread.h>

#if 0
#include <libgen.h>
#if __APPLE__
#include <GLUT/glut.h>
#else
#include <GL/glut.h>
#endif
#endif

#include "sim_avr.h"
#include "avr_ioport.h"
#include "sim_elf.h"
#include "sim_gdb.h"
#include "sim_vcd_file.h"
#include "avr_spi.h"

/* #include "button.h" */

// button_t button;
// int do_button_press = 0;
avr_t * avr = NULL;
avr_vcd_t vcd_file;
// uint8_t	pin_state = 0;	// current port B

// float pixsize = 64;
// int window;
#if 0
/*
 * called when the AVR change any of the pins on port B
 * so lets update our buffer
 */
void pin_changed_hook(struct avr_irq_t * irq, uint32_t value, void * param)
{
	pin_state = (pin_state & ~(1 << irq->irq)) | (value << irq->irq);
}

void displayCB(void)		/* function called whenever redisplay needed */
{
	// OpenGL rendering goes here...
	glClear(GL_COLOR_BUFFER_BIT);

	// Set up modelview matrix
	glMatrixMode(GL_MODELVIEW); // Select modelview matrix
	glLoadIdentity(); // Start with an identity matrix

	float grid = pixsize;
	float size = grid * 0.8;
    glBegin(GL_QUADS);
	glColor3f(1,0,0);

	for (int di = 0; di < 8; di++) {
		char on = (pin_state & (1 << di)) != 0;
		if (on) {
			float x = (di) * grid;
			float y = 0; //(si * grid * 8) + (di * grid);
			glVertex2f(x + size, y + size);
			glVertex2f(x, y + size);
			glVertex2f(x, y);
			glVertex2f(x + size, y);
		}
	}

    glEnd();
    glutSwapBuffers();
    //glFlush();				/* Complete any pending operations */
}

void keyCB(unsigned char key, int x, int y)	/* called on key press */
{
	if (key == 'q')
		exit(0);
	static uint8_t buf[64];
	switch (key) {
		case 'q':
		case 0x1f: // escape
			exit(0);
			break;
		case ' ':
			do_button_press++; // pass the message to the AVR thread
			break;
		case 'r':
			printf("Starting VCD trace\n");
			avr_vcd_start(&vcd_file);
			break;
		case 's':
			printf("Stopping VCD trace\n");
			avr_vcd_stop(&vcd_file);
			break;
	}
}

// gl timer. if the pin have changed states, refresh display
void timerCB(int i)
{
	static uint8_t oldstate = 0xff;
	// restart timer
	glutTimerFunc(1000/64, timerCB, 0);

	if (oldstate != pin_state) {
		oldstate = pin_state;
		glutPostRedisplay();
	}
}
#endif
static void * avr_run_thread(void * oaram)
{
  //	int b_press = do_button_press;
	
	while (1) {
		avr_run(avr);
#if 0
		if (do_button_press != b_press) {
			b_press = do_button_press;
			printf("Button pressed\n");
			button_press(&button, 1000000);
		}
#endif
	}
}

int main(int argc, char *argv[])
{
	elf_firmware_t f;
	const char * fname =  "wordClock-erl";
	char path[256];

//	sprintf(path, "%s/%s", dirname(argv[0]), fname);
//	printf("Firmware pathname is %s\n", path);
	elf_read_firmware(fname, &f);

	strcpy( f.mmcu, "atmega168" ); // hack
	f.frequency = 16000000;
	printf("firmware %s f=%d mmcu=%s\n", fname, (int)f.frequency, f.mmcu);
	
	avr = avr_make_mcu_by_name(f.mmcu);
	if (!avr) {
		fprintf(stderr, "%s: AVR '%s' now known\n", argv[0], f.mmcu);
		exit(1);
	}
	avr_init(avr);
	avr_load_firmware(avr, &f);

	// initialize our 'peripheral'
	// button_init(avr, &button, "button");
	// "connect" the output irw of the button to the port pin of the AVR
	/*
	avr_connect_irq(
		button.irq + IRQ_BUTTON_OUT,
		avr_io_getirq(avr, AVR_IOCTL_IOPORT_GETIRQ('C'), 0));
	*/
	// connect all the pins on port B to our callback
#if 0
	for (int i = 0; i < 8; i++)
		avr_irq_register_notify(
			avr_io_getirq(avr, AVR_IOCTL_IOPORT_GETIRQ('B'), i),
			pin_changed_hook, 
			NULL);
#endif
	// even if not setup at startup, activate gdb if crashing
	avr->gdb_port = 1234;
	if (0) {
		//avr->state = cpu_Stopped;
		avr_gdb_init(avr);
	}

	/*
	 *	VCD file initialization
	 *	
	 *	This will allow you to create a "wave" file and display it in gtkwave
	 *	Pressing "r" and "s" during the demo will start and stop recording
	 *	the pin changes
	 *     
	 *      Initially set to 100 000 usec = 100 ms. I think it is how often
	 *      to flush its' log.
	 */
	avr_vcd_init(avr, "gtkwave_output.vcd", &vcd_file, 100 /* usec */);

	/* want MOSI, SCLK, XLAT, BLANK */
	avr_vcd_add_signal( &vcd_file, 
			    avr_io_getirq(avr, AVR_IOCTL_SPI_GETIRQ(0), 
					  SPI_IRQ_OUTPUT), 
			    8, "MOSI" );

	avr_vcd_add_signal(&vcd_file, 
			   avr_io_getirq(avr, AVR_IOCTL_IOPORT_GETIRQ('B'), 1 ),
			   1, "XLAT" );
	avr_vcd_add_signal(&vcd_file, 
			   avr_io_getirq(avr, AVR_IOCTL_IOPORT_GETIRQ('B'), 2 ),
			   1, "BLANK" );
	avr_vcd_add_signal(&vcd_file, 
			   avr_io_getirq(avr, AVR_IOCTL_IOPORT_GETIRQ('B'), 5 ),
			   1, "SCLK" );
#if 0
	avr_vcd_add_signal(&vcd_file, 
		button.irq + IRQ_BUTTON_OUT, 1 /* bits */ ,
		"button" );

	// 'raise' it, it's a "pullup"
	avr_raise_irq(button.irq + IRQ_BUTTON_OUT, 1);
#endif
	avr_vcd_start( &vcd_file );
							       
	printf( "Demo launching. " );
#if 0
	/*
	 * OpenGL init, can be ignored
	 */
	glutInit(&argc, argv);		/* initialize GLUT system */

	glutInitDisplayMode(GLUT_RGB | GLUT_DOUBLE);
	glutInitWindowSize(8 * pixsize, 1 * pixsize);		/* width=400pixels height=500pixels */
	window = glutCreateWindow("Glut");	/* create window */

	// Set up projection matrix
	glMatrixMode(GL_PROJECTION); // Select projection matrix
	glLoadIdentity(); // Start with an identity matrix
	glOrtho(0, 8 * pixsize, 0, 1 * pixsize, 0, 10);
	glScalef(1,-1,1);
	glTranslatef(0, -1 * pixsize, 0);

	glutDisplayFunc(displayCB);		/* set window's display callback */
	glutKeyboardFunc(keyCB);		/* set window's key callback */
	glutTimerFunc(1000 / 24, timerCB, 0);
#endif
	// the AVR run on it's own thread. it even allows for debugging!
	pthread_t run;
	pthread_create(&run, NULL, avr_run_thread, NULL);

	sleep( 60 ); // wait 5 seconds, then exit.

	avr_vcd_stop(&vcd_file);

	/*	glutMainLoop(); */
}
