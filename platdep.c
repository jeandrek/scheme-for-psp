#include <pspctrl.h>

#include "scheme.h"

void *
psp_wait_button(void)
{
	SceCtrlLatch latch;

	for (;;) {
		sceCtrlReadLatch(&latch);
		if (latch.uiBreak & PSP_CTRL_CROSS)
			return get_symbol("cross");
		if (latch.uiBreak & PSP_CTRL_CIRCLE)
			return get_symbol("circle");
		if (latch.uiBreak & PSP_CTRL_TRIANGLE)
			return get_symbol("triangle");
		if (latch.uiBreak & PSP_CTRL_SQUARE)
			return get_symbol("square");
		if (latch.uiBreak & PSP_CTRL_LTRIGGER)
			return get_symbol("left-trigger");
		if (latch.uiBreak & PSP_CTRL_RTRIGGER)
			return get_symbol("right-trigger");
		if (latch.uiBreak & PSP_CTRL_UP)
			return get_symbol("up");
		if (latch.uiBreak & PSP_CTRL_DOWN)
			return get_symbol("down");
		if (latch.uiBreak & PSP_CTRL_LEFT)
			return get_symbol("left");
		if (latch.uiBreak & PSP_CTRL_RIGHT)
			return get_symbol("right");
	}
}

void *
psp_get_analog(void)
{
	SceCtrlData pad;

	sceCtrlPeekBufferPositive(&pad, 1);

	asm ("move $v0,%0\n\t"
	     "move $v1,%1"
	     :: "r" (pad.Lx << 3 | TAG_FIXNUM),
	        "r" (pad.Ly << 3 | TAG_FIXNUM));
}
