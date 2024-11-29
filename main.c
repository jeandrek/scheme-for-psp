#include <pspsdk.h>
#include <psploadexec.h>
#include <pspdisplay.h>
#include <pspdebugkb.h>
#include <pspctrl.h>
#include <psputility.h>
#include <string.h>
#include <stdio.h>

PSP_MODULE_INFO("scheme", 0, 1, 1);

void	screen_readline(void);
char	boot_scm_path[] = "ms0:/boot.scm";



FILE *current_input_file = NULL;
/*FILE *current_output_file = NULL;*/

void
open_as_current_input_file(char *path)
{
	current_input_file = fopen(path, "r");
}

void
close_current_input_file(void)
{
	fclose(current_input_file);
	current_input_file = NULL;
}


void
writechar(int c)
{
	pspDebugScreenPrintf("%c", c);
}
void
writenum(int n)
{
	pspDebugScreenPrintf("%d", n);
}
void
writestr(char *s)
{
	pspDebugScreenPrintf("%s", s);
}

char input[100];
size_t idx = 0;

int
C_peekchar(void)
{
	if (current_input_file) {
		int c = getc(current_input_file);
		ungetc(c, current_input_file);
		return c;
	}

	if (input[idx] > 0) {
		return input[idx];
	} else {
		screen_readline();
		return input[0];
	}
}

int
C_readchar(void)
{
	if (current_input_file) {
		int c = getc(current_input_file);
		return c;
	}

	int c = C_peekchar();
	idx++;
	return c;
}



void
screen_readline(void)
{
	int x = pspDebugScreenGetX(), y = pspDebugScreenGetY();
	SceCtrlLatch latch;
	char line[80];
	int i = 0;
	int c = 0;
	int k = 0;

	char keys[] = {
		'a', 'b', 'c', 'd', 'e', 'f', 'g', 'h', 'i', 'j', 'k', 'l',
		'm', 'n', 'o', 'p', 'q', 'r', 's', 't', 'u', 'v', 'w', 'x',
		'y', 'z', '0', '1', '2', '3', '4', '5', '6', '7', '8', '9',
		'(', ')', '+', '-', '*', '/', '<', '=', '>', '?', '\'', '"',
		'#', ' '
	};

	pspDebugScreenSetBackColor(0xffffffff);
	pspDebugScreenPutChar(x*7, y*8, 0, c);
	for (;;) {
		sceCtrlReadLatch(&latch);
		if (latch.uiBreak & PSP_CTRL_RTRIGGER) {
			if (c == 0) {
				c = 'a';
			} else {
				k = k < sizeof (keys) - 1 ? k + 1 : 0;
				c = keys[k];
			}
			pspDebugScreenSetBackColor(c != ' ' ? 0xffffffff : 0xff00ffff);
			pspDebugScreenPutChar(x*7, y*8, 0, c);
		}
		if (latch.uiBreak & PSP_CTRL_LTRIGGER) {
			if (k == 0) {
				c = ' ';
				k = sizeof (keys) - 1;
			} else {
				c = keys[--k];
			}
			pspDebugScreenSetBackColor(c != ' ' ? 0xffffffff : 0xff00ffff);
			pspDebugScreenPutChar(x*7, y*8, 0, c);
		}
		if (latch.uiBreak & PSP_CTRL_CROSS) {
			if (c == 0) continue;
			pspDebugScreenSetBackColor(0);
			pspDebugScreenPutChar(x*7, y*8, 0xffffffff, c);
			x += 1;
			line[i++] = c;
			c = 0;
			k = 0;
			pspDebugScreenSetBackColor(0xffffffff);
			pspDebugScreenPutChar(x*7, y*8, 0, ' ');
		}
		if (latch.uiBreak & PSP_CTRL_SQUARE) {
			pspDebugScreenSetBackColor(0);
			pspDebugScreenPutChar(x*7, y*8, 0xffffffff, ' ');
			x -= 1;
			c = line[--i];
			pspDebugScreenSetBackColor(0xffffffff);
			pspDebugScreenPutChar(x*7, y*8, 0, c);
		}
		if (latch.uiBreak & PSP_CTRL_TRIANGLE) {
			pspDebugScreenSetBackColor(0);
			pspDebugScreenPutChar(x*7, y*8, 0xffffffff,
					      c == 0 ? ' ' : c);
			if (c != 0)
				line[i++] = c;
			x = 0;
			y += 1;
			line[i] = '\n';
			line[i+1] = 0;
			idx = 0;
			strcpy(input, line);
			pspDebugScreenSetXY(x, y);
			break;
		}
	}
}



int
exit_callback(int arg1, int arg2, void *argp)
{
}

int
callback_thread(SceSize args, void *arg)
{
	int cbid;

	cbid = sceKernelCreateCallback("exit_callback", exit_callback, NULL);
	sceKernelRegisterExitCallback(cbid);
	sceKernelSleepThreadCB();
}

void scheme_main(void);

int
main(void)
{
	int thread = sceKernelCreateThread("update_thread", callback_thread, 0x11, 0xfa0, 0, NULL);
	if (thread >= 0)
		sceKernelStartThread(thread, 0, NULL);

	pspDebugScreenInit();
	scheme_main();
	sceKernelExitGame();
	return 0;
}
