#include "scheme.h"

#define NUM_PRIMS_PLATFORM_DEPENDENT	6

	.text
	.align	3
prim_delay_ms:
	addi	$sp,$sp,-16
	sw	$ra,12($sp)
	lw	$a0,($a0)
	CHECK_FIXNUM($a0)
	sra	$a0,$a0,3
	li	$t0,1000
	mul	$a0,$a0,$t0
	jal	sceKernelDelayThread
	lw	$ra,12($sp)
	addi	$sp,$sp,16
	la	$a0,str_ok
	j	intern

	.align	3
prim_psp_clear:
	addi	$sp,$sp,-16
	sw	$ra,12($sp)
	jal	pspDebugScreenClear
	lw	$ra,12($sp)
	addi	$sp,$sp,16
	la	$a0,str_ok
	j	intern

	.align	3
prim_psp_back_color:
	addi	$sp,$sp,-16
	sw	$ra,12($sp)
	lw	$t0,4($a0)
	lw	$a0,($a0)
	lw	$a1,($t0)
	lw	$t0,4($t0)
	lw	$a2,($t0)
	CHECK_FIXNUM($a0)
	CHECK_FIXNUM($a1)
	CHECK_FIXNUM($a2)
	xori	$a1,$a1,TAG_FIXNUM
	xori	$a2,$a2,TAG_FIXNUM
	sra	$a0,$a0,3
	sll	$a1,$a1,8 - 3
	sll	$a2,$a2,16 - 3
	or	$a0,$a0,$a1
	or	$a0,$a0,$a2
	li	$t0,0xff000000
	or	$a0,$a0,$t0
	jal	pspDebugScreenSetBackColor
	lw	$ra,12($sp)
	addi	$sp,$sp,16
	la	$a0,str_ok
	j	intern

	.align	3
prim_psp_text_color:
	addi	$sp,$sp,-16
	sw	$ra,12($sp)
	lw	$t0,4($a0)
	lw	$a0,($a0)
	lw	$a1,($t0)
	lw	$t0,4($t0)
	lw	$a2,($t0)
	CHECK_FIXNUM($a0)
	CHECK_FIXNUM($a1)
	CHECK_FIXNUM($a2)
	xori	$a1,$a1,TAG_FIXNUM
	xori	$a2,$a2,TAG_FIXNUM
	sra	$a0,$a0,3
	sll	$a1,$a1,8 - 3
	sll	$a2,$a2,16 - 3
	or	$a0,$a0,$a1
	or	$a0,$a0,$a2
	li	$t0,0xff000000
	or	$a0,$a0,$t0
	jal	pspDebugScreenSetTextColor
	lw	$ra,12($sp)
	addi	$sp,$sp,16
	la	$a0,str_ok
	j	intern

	.align	3
prim_psp_wait_button:
	addi	$sp,$sp,-16
	sw	$ra,12($sp)
	jal	psp_wait_button
	move	$a0,$v0
	lw	$ra,12($sp)
	addi	$sp,$sp,16
	jr	$ra

	.align	3
prim_psp_get_analog:
	addi	$sp,$sp,-16
	sw	$ra,12($sp)
	jal	psp_get_analog
	move	$a0,$v0
	move	$a1,$v1
	lw	$ra,12($sp)
	addi	$sp,$sp,16
	j	cons


	.globl	add_prims_platform_dependent
add_prims_platform_dependent:
	addi	$sp,$sp,-16
	sw	$ra,12($sp)
	sw	$a0,8($sp)
	sw	$s0,4($sp)
	sw	$s1,($sp)
	li	$a0,1		# PSP_CTRL_MODE_ANALOG
	jal	sceCtrlSetSamplingMode
	li	$a0,0
	jal	sceCtrlSetSamplingCycle
	li	$s0,NUM_PRIMS_PLATFORM_DEPENDENT
	la	$s1,prims_platform_dependent
1:
	beqz	$s0,2f
	lw	$a0,($s1)
	jal	intern
	lw	$a1,4($s1)
	ori	$a1,$a1,TAG_PROCEDURE
	lw	$a2,8($sp)
	jal	define_variable
	addi	$s1,$s1,8
	addi	$s0,$s0,-1
	j	1b
2:
	lw	$s1,($sp)
	lw	$s0,4($sp)
	lw	$ra,12($sp)
	addi	$sp,$sp,16
	jr	$ra


	.section	.rodata
	.globl	prims_platform_dependent
prims_platform_dependent:
	.word	str_delay_ms
	.word	prim_delay_ms

	.word	str_psp_clear
	.word	prim_psp_clear

	.word	str_psp_back_color
	.word	prim_psp_back_color

	.word	str_psp_text_color
	.word	prim_psp_text_color

	.word	str_psp_wait_button
	.word	prim_psp_wait_button

	.word	str_psp_get_analog
	.word	prim_psp_get_analog

str_delay_ms:		.string	"delay-ms"
str_psp_clear:		.string	"psp-clear"
str_psp_back_color:	.string	"psp-back-color"
str_psp_text_color:	.string	"psp-text-color"
str_psp_wait_button:	.string	"psp-wait-button"
str_psp_get_analog:	.string	"psp-get-analog"
str_ok:			.string	"ok"
