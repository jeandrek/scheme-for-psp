/*
 * Copyright (c) 2024 Jeandre Kruger
 * All rights reserved.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions
 * are met:
 * 1. Redistributions of source code must retain the above copyright
 *    notice, this list of conditions and the following disclaimer.
 * 2. Redistributions in binary form must reproduce the above copyright
 *    notice, this list of conditions and the following disclaimer in the
 *    documentation and/or other materials provided with the distribution.
 *
 * THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
 * ``AS IS'' AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
 * LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A
 * PARTICULAR PURPOSE ARE DISCLAIMED.  IN NO EVENT SHALL THE FOUNDATION OR
 * CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL,
 * EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO,
 * PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR
 * PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF
 * LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING
 * NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
 * SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 */

#include <pspsdk.h>
#include <psploadexec.h>
#include <pspctrl.h>
#include <string.h>
#include <stdio.h>

#include "scheme.h"

PSP_MODULE_INFO("scheme", 0, 1, 1);

void	screen_readline(void);
char	boot_scm_path[] = "ms0:/boot.scm";



/*FILE *current_input_file = NULL;*/
/*FILE *current_output_file = NULL;*/

FILE *
open_input_file(char *path)
{
	FILE *f = fopen(path, "r");
	if (f == NULL)
		error("Cannot load specified file", NULL);
	return f;
}

void
close_input_file(FILE *f)
{
	fclose(f);
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
C_peekchar(FILE *input_file)
{
	if (input_file) {
		int c = getc(input_file);
		ungetc(c, input_file);
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
C_readchar(FILE *input_file)
{
	if (input_file) {
		int c = getc(input_file);
		return c;
	}

	int c = C_peekchar(NULL);
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
	sceKernelExitGame();
}

int
callback_thread(SceSize args, void *arg)
{
	int cbid;

	cbid = sceKernelCreateCallback("exit_callback", exit_callback, NULL);
	sceKernelRegisterExitCallback(cbid);
	sceKernelSleepThreadCB();
}

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
