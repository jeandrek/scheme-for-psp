#include <pspctrl.h>
#include <pspdisplay.h>
#include <pspsdk.h>
#include <stdint.h>

#include "scheme.h"

static void	*symbol_ok;
static void	*symbol_cross;
static void	*symbol_circle;
static void	*symbol_triangle;
static void	*symbol_square;
static void	*symbol_left_trigger;
static void	*symbol_right_trigger;
static void	*symbol_up;
static void	*symbol_down;
static void	*symbol_left;
static void	*symbol_right;

void
init_platdep(void)
{
	symbol_ok	= intern("ok");
	symbol_cross	= intern("cross");
	symbol_circle	= intern("circle");
	symbol_triangle	= intern("triangle");
	symbol_square	= intern("square");
	symbol_left_trigger	= intern("left-trigger");
	symbol_right_trigger	= intern("right-trigger");
	symbol_up	= intern("up");
	symbol_down	= intern("down");
	symbol_left	= intern("left");
	symbol_right	= intern("right");

	sceCtrlSetSamplingMode(PSP_CTRL_MODE_ANALOG);
	sceCtrlSetSamplingCycle(0);
}

PRIMITIVE void *
prim_delay_ms(void *args)
{
	uint32_t arg = ((uint32_t *)args)[0];
	CHECK_FIXNUM(arg);
	arg >>= 3;
	sceKernelDelayThread(1000 * arg);
	return symbol_ok;
}

PRIMITIVE void *
prim_psp_vblank(void *args)
{
	sceDisplayWaitVblankStart();
	return symbol_ok;
}

PRIMITIVE void *
prim_psp_clear(void *args)
{
	pspDebugScreenClear();
	return symbol_ok;
}

PRIMITIVE void *
prim_psp_screen_x_y(void *args)
{
	uint32_t arg1, arg2;

	arg1 = ((uint32_t *)args)[0];
	args = ((void **)args)[1];
	arg2 = ((uint32_t *)args)[0];

	CHECK_FIXNUM(arg1);
	CHECK_FIXNUM(arg2);
	arg1 >>= 3;
	arg2 >>= 3;
	pspDebugScreenSetXY(arg1, arg2);
	return symbol_ok;
}

PRIMITIVE void *
prim_psp_back_color(void *args)
{
	uint32_t arg1, arg2, arg3, color;

	arg1 = ((uint32_t *)args)[0];
	args = ((void **)args)[1];
	arg2 = ((uint32_t *)args)[0];
	args = ((void **)args)[1];
	arg3 = ((uint32_t *)args)[0];

	CHECK_FIXNUM(arg1);
	CHECK_FIXNUM(arg2);
	CHECK_FIXNUM(arg3);
	arg1 >>= 3;
	arg2 ^= TAG_FIXNUM;
	arg3 ^= TAG_FIXNUM;

	color = 0xff << 24 | arg3 << (16 - 3) | arg2 << (8 - 3) | arg1;
	pspDebugScreenSetBackColor(color);

	return symbol_ok;
}

PRIMITIVE void *
prim_psp_text_color(void *args)
{
	uint32_t arg1, arg2, arg3, color;

	arg1 = ((uint32_t *)args)[0];
	args = ((void **)args)[1];
	arg2 = ((uint32_t *)args)[0];
	args = ((void **)args)[1];
	arg3 = ((uint32_t *)args)[0];

	CHECK_FIXNUM(arg1);
	CHECK_FIXNUM(arg2);
	CHECK_FIXNUM(arg3);
	arg1 >>= 3;
	arg2 ^= TAG_FIXNUM;
	arg3 ^= TAG_FIXNUM;

	color = 0xff << 24 | arg3 << (16 - 3) | arg2 << (8 - 3) | arg1;
	pspDebugScreenSetTextColor(color);

	return symbol_ok;
}


PRIMITIVE void *
prim_psp_wait_button(void *args)
{
	SceCtrlLatch latch;

	for (;;) {
		sceCtrlReadLatch(&latch);
		if (latch.uiBreak & PSP_CTRL_CROSS)	return symbol_cross;
		if (latch.uiBreak & PSP_CTRL_CIRCLE)	return symbol_circle;
		if (latch.uiBreak & PSP_CTRL_TRIANGLE)	return symbol_triangle;
		if (latch.uiBreak & PSP_CTRL_SQUARE)	return symbol_square;
		if (latch.uiBreak & PSP_CTRL_LTRIGGER)
			return symbol_left_trigger;
		if (latch.uiBreak & PSP_CTRL_RTRIGGER)
			return symbol_right_trigger;
		if (latch.uiBreak & PSP_CTRL_UP)	return symbol_up;
		if (latch.uiBreak & PSP_CTRL_DOWN)	return symbol_down;
		if (latch.uiBreak & PSP_CTRL_LEFT)	return symbol_left;
		if (latch.uiBreak & PSP_CTRL_RIGHT)	return symbol_right;
	}
}

PRIMITIVE void *
prim_psp_get_analog(void *args)
{
	SceCtrlData pad;

	sceCtrlPeekBufferPositive(&pad, 1);
	return cons((void *)(pad.Lx << 3 | TAG_FIXNUM),
		    (void *)(pad.Ly << 3 | TAG_FIXNUM));
}

struct prim_decl prims_platform_dependent[] = {
	{"delay-ms",		prim_delay_ms},
	{"psp-vblank",		prim_psp_vblank},
	{"psp-clear",		prim_psp_clear},
	{"psp-screen-x-y",	prim_psp_screen_x_y},
	{"psp-back-color",	prim_psp_back_color},
	{"psp-text-color",	prim_psp_text_color},
	{"psp-wait-button",	prim_psp_wait_button},
	{"psp-get-analog",	prim_psp_get_analog},
	{NULL, NULL}
};

void
add_prims_platform_dependent(void *env)
{
	struct prim_decl *prim_decls = prims_platform_dependent;
	void *prim;
	int i = 0;

	init_platdep();
	while (prim_decls[i].name != NULL) {
		prim = (void *)((uint32_t)prim_decls[i].addr | TAG_PROCEDURE);
		define_variable(intern(prim_decls[i].name), prim, env);
		i++;
	}
}
