#define TAG_PROCEDURE	2
#define NUM_PRIMS_PLATFORM_DEPENDENT	2

	.text
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
prim_psp_wait_button:
	addi	$sp,$sp,-16
	sw	$ra,12($sp)
	jal	psp_wait_button
	move	$a0,$v0
	lw	$ra,12($sp)
	addi	$sp,$sp,16
	jr	$ra


	.globl	add_prims_platform_dependent
add_prims_platform_dependent:
	addi	$sp,$sp,-16
	sw	$ra,12($sp)
	sw	$a0,8($sp)
	sw	$s0,4($sp)
	sw	$s1,($sp)
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
	.word	str_psp_clear
	.word	prim_psp_clear

	.word	str_psp_wait_button
	.word	prim_psp_wait_button

str_psp_clear:		.string	"psp-clear"
str_psp_wait_button:	.string	"psp-wait-button"
str_ok:			.string	"ok"
