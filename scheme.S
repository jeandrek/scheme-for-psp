#### A simple Scheme interpreter
#### With a SICP-esque Cheney's algorithm garbage collector

#### Copyright (c) 2024 Jeandre Kruger
#### All rights reserved.

#### Redistribution and use in source and binary forms, with or without
#### modification, are permitted provided that the following conditions
#### are met:
#### 1. Redistributions of source code must retain the above copyright
####    notice, this list of conditions and the following disclaimer.
#### 2. Redistributions in binary form must reproduce the above copyright
####    notice, this list of conditions and the following disclaimer in the
####    documentation and/or other materials provided with the distribution.

#### THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
#### ``AS IS'' AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
#### LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A
#### PARTICULAR PURPOSE ARE DISCLAIMED.  IN NO EVENT SHALL THE FOUNDATION OR
#### CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL,
#### EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO,
#### PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR
#### PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF
#### LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING
#### NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
#### SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

### (Strings are allocated using malloc and swept by GC, possibly
### not ideal)

### The following routines return a result in $v0 instead of $a0:
### all primitives; apply; eval; lookup; make_procedure; set_variable
### define_variable
###
### I.e., apply, eval, and those routines to which eval delegates
### execution of certain expression types


#include "scheme.h"

#define REG_FROMSPACE	$s5
#define REG_TOSPACE	$s6
#define REG_FREE	$s7
#define PAIR_MEM	pair_memory
#define SPACE_SIZE	0x10000

#define SYMBOL_LENGTH	16

#define BROKEN_HEART	4
#define TRUE		7
#define FALSE		3

#define NUM_PRIMITIVES	24

# Every stack frame reachable by GC must have no dead values.
#define ZEROFRAME		\
	sw	$zero,8($sp);	\
	sw	$zero,4($sp);	\
	sw	$zero,($sp)

#define SYM(name)		sym_ ## name
#define NAME_SYM(n1, n2)	.align 4; sym_ ## n1 = . + 3; .string n2
#define MAKE_SYM(name)		.align 4; .string name


### Glue
	.text
	.globl	peekchar
peekchar:
	addi	$sp,$sp,-16
	sw	$ra,12($sp)
	jal	C_peekchar
	move	$a0,$v0
	lw	$ra,12($sp)
	addi	$sp,$sp,16
	jr	$ra
	.globl	readchar
readchar:
	addi	$sp,$sp,-16
	sw	$ra,12($sp)
	jal	C_readchar
	move	$a0,$v0
	lw	$ra,12($sp)
	addi	$sp,$sp,16
	jr	$ra

	.globl	get_symbol
get_symbol:
	addi	$sp,$sp,-16
	sw	$ra,12($sp)
	jal	intern
	move	$v0,$a0
	lw	$ra,12($sp)
	addi	$sp,$sp,16
	jr	$ra

	.globl	C_cons
C_cons:
	addi	$sp,$sp,-16
	sw	$ra,12($sp)
	jal	cons
	move	$v0,$a0
	lw	$ra,12($sp)
	addi	$sp,$sp,16
	jr	$ra


	.globl	scheme_main
scheme_main:
	la	$t0,gc_top_of_stack
	sw	$sp,($t0)
	la	REG_TOSPACE,PAIR_MEM
	la	REG_FROMSPACE,PAIR_MEM + SPACE_SIZE
	move	REG_FREE,REG_TOSPACE
	addi	$sp,$sp,-16
	ZEROFRAME
	sw	$ra,12($sp)
	la	$t0,error_sp
	sw	$sp,($t0)
	la	$t0,error_pc
	la	$t1,Lprompt
	sw	$t1,($t0)
	la	$a0,str_msg
	jal	writestr
	la	$a0,image_env
	lw	$a0,($a0)
	beqz	$a0,Lnot_imaged
	la	$t0,image_free
	lw	REG_FREE,($t0)
	j	Lready
Lnot_imaged:
	la	$a0,str_fresh
	jal	writestr
	jal	make_initial_environment
	sw	$a0,8($sp)
	jal	add_prims_platform_dependent
	lw	$a1,8($sp)
	la	$t0,global_env
	sw	$a1,($t0)	# For LOAD
	la	$a0,boot_scm_path
	jal	load		# XXX error handling
	lw	$a0,8($sp)
Lready:
	sw	$a0,8($sp)	# Saved for reason of error
Lprompt:
	li	$a0,'>'
	jal	writechar
	li	$a0,0
	jal	read
	lw	$a1,8($sp)
	jal	eval
	la	$t0,SYM(ok)
	beq	$v0,$t0,Lprompt
	move	$a0,$v0
	jal	write
	li	$a0,'\n'
	jal	writechar
	j	Lprompt

	.globl	error
error:
	sw	$a1,12($sp)
	jal	writestr
	lw	$a0,12($sp)
	beqz	$a0,2f
	jal	write
2:
	li	$a0,'\n'
	jal	writechar
	la	$t0,error_sp
	lw	$sp,($t0)
	la	$t0,error_pc
	lw	$t0,($t0)
	jr	$t0

	.globl	load
load:
	addi	$sp,$sp,-16
	sw	$ra,12($sp)
	sw	$zero,($sp)
	sw	$a1,4($sp)
	jal	open_input_file
	sw	$v0,8($sp)
	move	$a0,$v0
1:
	jal	read
	la	$t0,SYM(Eof)
	beq	$a0,$t0,2f
	lw	$a1,4($sp)
	jal	eval
	lw	$a0,8($sp)
	j	1b
2:
	lw	$a0,8($sp)
	jal	close_input_file
	lw	$ra,12($sp)
	addi	$sp,$sp,16
	jr	$ra


### Initial environment and primitives

	.globl	make_initial_environment
make_initial_environment:
	addi	$sp,$sp,-16
	sw	$ra,12($sp)
	sw	$s1,8($sp)
	sw	$s2,4($sp)
	sw	$s3,($sp)
	la	$s1,SYM(ok) + SYMBOL_LENGTH
	li	$s2,NUM_PRIMITIVES
	li	$a1,0
1:
	beqz	$s2,2f
	move	$a0,$s1
	jal	cons
	move	$a1,$a0
	addi	$s1,$s1,SYMBOL_LENGTH
	addi	$s2,$s2,-1
	j	1b
2:
	move	$s3,$a1
	la	$s1,prim_addrs
	li	$s2,NUM_PRIMITIVES
	li	$a1,0
1:
	beqz	$s2,2f
	lw	$a0,($s1)
	ori	$a0,$a0,TAG_PROCEDURE
	jal	cons
	move	$a1,$a0
	addi	$s1,$s1,4
	addi	$s2,$s2,-1
	j	1b
2:
	move	$a0,$s3
	jal	cons
	li	$a1,0
	jal	cons
	lw	$s3,($sp)
	lw	$s2,4($sp)
	lw	$s1,8($sp)
	lw	$ra,12($sp)
	addi	$sp,$sp,16
	jr	$ra

	.align	3
prim_eq:
	DYADIC_ARGS
Lcmp:
	bne	$a0,$a1,1f
	li	$v0,TRUE
	jr	$ra
1:
	li	$v0,FALSE
	jr	$ra

	.align	3
prim_integerp:
	lw	$a0,($a0)
	andi	$a0,$a0,7
	li	$t0,TAG_FIXNUM
	bne	$a0,$t0,1f
	li	$v0,TRUE
	jr	$ra
1:
	li	$v0,FALSE
	jr	$ra

	.align	3
prim_num_eql:
	DYADIC_ARGS
	CHECK_FIXNUM($a0)
	CHECK_FIXNUM($a1)
	j	Lcmp

	.align	3
prim_lt:
	DYADIC_ARGS
	CHECK_FIXNUM($a0)
	CHECK_FIXNUM($a1)
	slt	$v0,$a0,$a1
	sll	$v0,$v0,3
	addi	$v0,$v0,FALSE
	jr	$ra

	.align	3
prim_add:
	DYADIC_ARGS
	CHECK_FIXNUM($a0)
	CHECK_FIXNUM($a1)
	xori	$a1,$a1,TAG_FIXNUM
	add	$v0,$a0,$a1
	jr	$ra

	.align	3
prim_sub:
	DYADIC_ARGS
	CHECK_FIXNUM($a0)
	CHECK_FIXNUM($a1)
	xori	$a1,$a1,TAG_FIXNUM
	sub	$v0,$a0,$a1
	jr	$ra

	.align	3
prim_mul:
	DYADIC_ARGS
	CHECK_FIXNUM($a0)
	CHECK_FIXNUM($a1)
	xori	$a0,$a0,TAG_FIXNUM
	sra	$a1,$a1,3
	mul	$v0,$a0,$a1
	ori	$v0,$v0,TAG_FIXNUM
	jr	$ra

	.align	3
prim_quotient:
	DYADIC_ARGS
	CHECK_FIXNUM($a0)
	CHECK_FIXNUM($a1)
	sra	$a0,$a0,3
	sra	$a1,$a1,3
	div	$v0,$a0,$a1
	sll	$v0,$v0,3
	ori	$v0,$v0,TAG_FIXNUM
	jr	$ra

	.align	3
prim_remainder:
	DYADIC_ARGS
	CHECK_FIXNUM($a0)
	CHECK_FIXNUM($a1)
	sra	$a0,$a0,3
	sra	$a1,$a1,3
	rem	$v0,$a0,$a1
	sll	$v0,$v0,3
	ori	$v0,$v0,TAG_FIXNUM
	jr	$ra

	.align	3
prim_modulo:
	DYADIC_ARGS
	CHECK_FIXNUM($a0)
	CHECK_FIXNUM($a1)
	sra	$a0,$a0,3
	sra	$a1,$a1,3
	## Could this be simpler?
	rem	$v0,$a0,$a1
	bge	$v0,$zero,1f
	blt	$a1,$zero,2f
	add	$v0,$v0,$a1
1:
	bge	$a1,$zero,2f
	add	$v0,$v0,$a1
2:
	sll	$v0,$v0,3
	ori	$v0,$v0,TAG_FIXNUM
	jr	$ra

	.align	3
prim_pairp:
	lw	$a0,($a0)
	andi	$t0,$a0,7
	bnez	$t0,1f
	beqz	$a0,1f
	li	$v0,TRUE
	jr	$ra
1:
	li	$v0,FALSE
	jr	$ra

	.align	3
prim_cons:
	lw	$t0,4($a0)
	lw	$t0,($t0)
	sw	$t0,4($a0)
	move	$v0,$a0
	jr	$ra

	.align	3
prim_car:
	lw	$a0,($a0)
	CHECK_PAIR($a0)
	lw	$v0,($a0)
	jr	$ra

	.align	3
prim_cdr:
	lw	$a0,($a0)
	CHECK_PAIR($a0)
	lw	$v0,4($a0)
	jr	$ra

	.align	3
prim_set_car:
	DYADIC_ARGS
	CHECK_PAIR($a0)
	sw	$a1,($a0)
	la	$v0,SYM(ok)
	jr	$ra

	.align	3
prim_set_cdr:
	DYADIC_ARGS
	CHECK_PAIR($a0)
	sw	$a1,4($a0)
	la	$v0,SYM(ok)
	jr	$ra

	.align	3
prim_list:
	move	$v0,$a0
	jr	$ra

	.align	3
prim_symbolp:
	lw	$a0,($a0)
	andi	$t0,$a0,7
	li	$t1,TAG_SYMBOL
	bne	$t0,$t1,1f
	li	$t0,TRUE
	beq	$a0,$t0,1f
	li	$t0,FALSE
	beq	$a0,$t0,1f
	li	$v0,TRUE
	jr	$ra
1:
	li	$v0,FALSE
	jr	$ra

	.align	3
prim_procedurep:
	lw	$a0,($a0)
	andi	$t0,$a0,7
	li	$t1,TAG_PROCEDURE
	bne	$t0,$t1,1f
	li	$v0,TRUE
	jr	$ra
1:
	li	$v0,FALSE
	jr	$ra

	.align	3
prim_read:
	li	$a0,0
	j	read

	.align	3
prim_write:
	lw	$a0,($a0)
	addi	$sp,$sp,-16
	sw	$ra,12($sp)
	jal	write
	la	$v0,SYM(ok)
	lw	$ra,12($sp)
	addi	$sp,$sp,16
	jr	$ra

	.align	3
prim_display:
	lw	$a0,($a0)
	addi	$sp,$sp,-16
	sw	$ra,12($sp)
	li	$t0,1
	la	$t1,printer_display_flag
	sw	$t0,($t1)
	jal	write
	la	$t1,printer_display_flag
	sw	$zero,($t1)
	la	$v0,SYM(ok)
	lw	$ra,12($sp)
	addi	$sp,$sp,16
	jr	$ra

	.align	3
prim_newline:
	addi	$sp,$sp,-16
	sw	$ra,12($sp)
	li	$a0,'\n'
	jal	writechar
	la	$v0,SYM(ok)
	lw	$ra,12($sp)
	addi	$sp,$sp,16
	jr	$ra

	.align	3
prim_image:
	addi	$sp,$sp,-16
	sw	$ra,12($sp)
	ZEROFRAME
	jal	gc
	blt	REG_TOSPACE,REG_FROMSPACE,1f
	jal	gc
1:
	li	$t0,PAIR_MEM - 16
	lw	$t0,8($t0)
	la	$t1,image_env
	sw	$t0,($t1)
	la	$t1,image_free
	sw	REG_FREE,($t1)
	li	$a0,0
	li	$a1,PAIR_MEM + SPACE_SIZE
	## XXX
	#jal	image
	la	$v0,SYM(ok)
	lw	$ra,12($sp)
	addi	$sp,$sp,16
	jr	$ra

	.align	3
prim_load:
	lw	$a0,($a0)
	CHECK_STRING($a0)
	addi	$sp,$sp,-16
	sw	$ra,12($sp)
	ZEROFRAME
	xori	$a0,$a0,TAG_STRING
	addi	$a0,$a0,5
	la	$a1,global_env
	lw	$a1,($a1)
	jal	load
	la	$v0,SYM(ok)
	lw	$ra,12($sp)
	addi	$sp,$sp,16
	jr	$ra


### Evaluator

	.globl	eval
eval:
	andi	$t0,$a0,7
	bnez	$t0,1f
	beqz	$a0,2f
	j	Leval_pair
1:
	li	$t1,TAG_FIXNUM
	beq	$t0,$t1,Leval_self_evaluating
	li	$t1,TAG_SYMBOL
	bne	$t0,$t1,2f
	li	$t0,FALSE
	beq	$a0,$t0,Leval_self_evaluating
	j	Leval_variable
2:
	li	$t1,TAG_STRING
	beq	$t0,$t1,Leval_self_evaluating
	li	$t0,TRUE
	beq	$a0,$t0,Leval_self_evaluating
	move	$a1,$a0
	la	$a0,str_bad_exp
	j	error

Leval_self_evaluating:
	move	$v0,$a0
	jr	$ra

Leval_variable:
	j	lookup

Leval_pair:
	lw	$t0,($a0)
	la	$t1,SYM(quote)
	beq	$t0,$t1,Leval_quote
	la	$t1,SYM(lambda)
	beq	$t0,$t1,Leval_lambda
	la	$t1,SYM(if)
	beq	$t0,$t1,Leval_if
	la	$t1,SYM(set)
	beq	$t0,$t1,Leval_set
	la	$t1,SYM(begin)
	beq	$t0,$t1,Leval_begin
	la	$t1,SYM(cond)
	beq	$t0,$t1,Leval_cond
	la	$t1,SYM(let)
	beq	$t0,$t1,Leval_let
	la	$t1,SYM(define)
	beq	$t0,$t1,Leval_define
	addi	$sp,$sp,-16
	sw	$zero,($sp)
	sw	$ra,12($sp)
	lw	$a0,4($a0)
	sw	$a1,8($sp)
	sw	$t0,4($sp)
	jal	eval_arguments
	sw	$a0,($sp)
	lw	$a0,4($sp)
	lw	$a1,8($sp)
	jal	eval
	lw	$a1,($sp)
	lw	$ra,12($sp)
	addi	$sp,$sp,16
	move	$a0,$v0
	j	apply


## Special forms

Leval_quote:
	lw	$a0,4($a0)
	lw	$v0,($a0)
	jr	$ra

Leval_lambda:
	lw	$t0,4($a0)
	lw	$a0,($t0)
	move	$a2,$a1
	lw	$a1,4($t0)
	j	make_procedure

Leval_if:
	addi	$sp,$sp,-16
	sw	$ra,12($sp)
	ZEROFRAME
	lw	$t0,4($a0)
	lw	$a0,($t0)
	lw	$t0,4($t0)
	sw	$t0,8($sp)
	sw	$a1,4($sp)
	jal	eval
	lw	$a1,4($sp)
	lw	$t0,8($sp)
	li	$t1,FALSE
	beq	$v0,$t1,Leval_alt
	j	Leval_conseq
Leval_alt:
	lw	$t0,4($t0)
	bnez	$t0,Leval_conseq
	la	$v0,SYM(ok)
	lw	$ra,12($sp)
	addi	$sp,$sp,16
	jr	$ra
Leval_conseq:
	lw	$a0,($t0)
	lw	$ra,12($sp)
	addi	$sp,$sp,16
	j	eval

Leval_set:
	addi	$sp,$sp,-16
	sw	$ra,12($sp)
	sw	$s1,8($sp)
	sw	$s2,4($sp)
	sw	$zero,($sp)
	lw	$a0,4($a0)
	lw	$s1,($a0)
	lw	$a0,4($a0)
	lw	$a0,($a0)
	move	$s2,$a1
	jal	eval
	move	$a1,$v0
	move	$a0,$s1
	move	$a2,$s2
	lw	$s2,4($sp)
	lw	$s1,8($sp)
	lw	$ra,12($sp)
	addi	$sp,$sp,16
	j	set_variable

Leval_begin:
	lw	$a0,4($a0)
	j	eval_sequence

Leval_cond:
	addi	$sp,$sp,-16
	sw	$ra,12($sp)
	sw	$s1,8($sp)
	sw	$s2,4($sp)
	sw	$s3,($sp)
	lw	$s1,4($a0)
	move	$s2,$a1
1:
	bnez	$s1,2f
	la	$v0,SYM(ok)
	lw	$s3,($sp)
	lw	$s2,4($sp)
	lw	$s1,8($sp)
	lw	$ra,12($sp)
	addi	$sp,$sp,16
	jr	$ra
2:
	lw	$t0,($s1)
	lw	$a0,($t0)
	lw	$s3,4($t0)
	move	$a1,$s2
	jal	eval
	li	$t0,FALSE
	beq	$v0,$t0,3f
	move	$a0,$s3
	move	$a1,$s2
	lw	$s3,($sp)
	lw	$s2,4($sp)
	lw	$s1,8($sp)
	lw	$ra,12($sp)
	addi	$sp,$sp,16
	j	eval_sequence
3:
	lw	$s1,4($s1)
	j	1b

Leval_let:
	# $s1 = let bindings
	# $s2 = let body
	# $s3 = variables
	# $s4 = values
	# $s5 = expression
	# $s6 = environment
	addi	$sp,$sp,-32
	sw	$ra,28($sp)
	sw	$s1,24($sp)
	sw	$s2,20($sp)
	sw	$s3,16($sp)
	sw	$s4,12($sp)
	sw	$s5,8($sp)
	sw	$s6,4($sp)
	sw	$zero,($sp)
	lw	$t0,4($a0)
	lw	$s1,($t0)
	lw	$s2,4($t0)
	li	$s3,0
	li	$s4,0
	move	$s6,$a1
1:
	beqz	$s1,2f
	lw	$t0,($s1)
	lw	$s5,4($t0)
	lw	$s5,($s5)
	lw	$a0,($t0)
	move	$a1,$s3
	jal	cons
	move	$s3,$a0
	move	$a0,$s5
	move	$a1,$s6
	jal	eval
	move	$a1,$s4
	jal	cons
	move	$s4,$a0
	lw	$s1,4($s1)
	j	1b
2:
	move	$a0,$s3
	move	$a1,$s4
	jal	cons
	move	$a1,$s6
	jal	cons
	move	$a1,$a0
	move	$a0,$s2
	lw	$s6,4($sp)
	lw	$s5,8($sp)
	lw	$s4,12($sp)
	lw	$s3,16($sp)
	lw	$s2,20($sp)
	lw	$s1,24($sp)
	lw	$ra,28($sp)
	addi	$sp,$sp,32
	j	eval_sequence

Leval_define:
	addi	$sp,$sp,-16
	sw	$ra,12($sp)
	ZEROFRAME
	sw	$a1,8($sp)
	lw	$t0,4($a0)
	lw	$t1,($t0)
	andi	$t2,$t1,7
	bnez	$t2,1f
	lw	$t2,($t1)
	lw	$a0,4($t1)
	lw	$a1,4($t0)
	sw	$t2,4($sp)
	jal	cons
	move	$a1,$a0
	la	$a0,SYM(lambda)
	jal	cons
	j	2f
1:
	lw	$t0,4($t0)
	lw	$a0,($t0)
	sw	$t1,4($sp)
2:
	lw	$a1,8($sp)
	jal	eval
	move	$a1,$v0
	lw	$a0,4($sp)
	lw	$a2,8($sp)
	lw	$ra,12($sp)
	addi	$sp,$sp,16
	j	define_variable

eval_arguments:
	addi	$sp,$sp,-16
	sw	$ra,12($sp)
	move	$t0,$a0
	li	$t1,0
1:
	beqz	$t0,2f
	sw	$t0,8($sp)
	sw	$t1,4($sp)
	sw	$a1,($sp)
	lw	$a0,($t0)
	jal	eval
	move	$a0,$v0
	lw	$a1,4($sp)
	jal	cons
	move	$t1,$a0
	lw	$t0,8($sp)
	lw	$t0,4($t0)
	lw	$a1,($sp)
	j	1b
2:
	move	$a0,$t1
	lw	$ra,12($sp)
	addi	$sp,$sp,16
	j	nreverse

eval_sequence:
	move	$t0,$a0
	lw	$a0,($t0)
	lw	$t0,4($t0)
	beqz	$t0,eval
	addi	$sp,$sp,-16
	sw	$ra,12($sp)
	sw	$zero,($sp)
	j	2f
1:
	lw	$a0,($t0)
	lw	$t0,4($t0)
	beqz	$t0,3f
2:
	sw	$t0,8($sp)
	sw	$a1,4($sp)
	jal	eval
	lw	$a1,4($sp)
	lw	$t0,8($sp)
	j	1b
3:
	lw	$ra,12($sp)
	addi	$sp,$sp,16
	j	eval


### Procedures and environments

	.globl	make_procedure
make_procedure:
	addi	$sp,$sp,-16
	ZEROFRAME
	sw	$ra,12($sp)
	sw	$s1,8($sp)
	move	$s1,$a2
	jal	cons
	move	$a1,$a0
	move	$a0,$s1
	jal	cons
	ori	$v0,$a0,TAG_PROCEDURE
	lw	$s1,8($sp)
	lw	$ra,12($sp)
	addi	$sp,$sp,16
	jr	$ra

	.globl	apply
apply:
	andi	$t0,$a0,7
	li	$t1,TAG_PROCEDURE
	bne	$t0,$t1,Lnot_proc
	xori	$t0,$a0,TAG_PROCEDURE
	la	$t1,PAIR_MEM
	blt	$t0,$t1,Lapply_primitive
	la	$t1,PAIR_MEM + 2*SPACE_SIZE
	bgt	$t0,$t1,Lapply_primitive
	addi	$sp,$sp,-16
	ZEROFRAME
	sw	$ra,12($sp)
	sw	$t0,8($sp)
	lw	$t0,4($t0)
	lw	$a0,($t0)
	jal	cons
	lw	$t0,8($sp)
	lw	$a1,($t0)
	jal	cons
	move	$a1,$a0
	lw	$t0,8($sp)
	lw	$t0,4($t0)
	lw	$a0,4($t0)
	lw	$ra,12($sp)
	addi	$sp,$sp,16
	j	eval_sequence
Lapply_primitive:
	move	$a0,$a1
	jr	$t0
Lnot_proc:
	move	$a1,$a0
	la	$a0,str_not_proc
	j	error

	.globl	lookup
lookup:
	beqz	$a1,Lunbound
	lw	$t1,($a1)
	lw	$t2,($t1)
	lw	$t3,4($t1)
1:
	beqz	$t2,3f
	lw	$t4,($t2)
	beq	$t4,$a0,2f
	lw	$t2,4($t2)
	lw	$t3,4($t3)
	j	1b
2:
	lw	$v0,($t3)
	jr	$ra
3:
	lw	$a1,4($a1)
	j	lookup

	.globl	set_variable
set_variable:
	beqz	$a2,Lunbound
	lw	$t1,($a2)
	lw	$t2,($t1)
	lw	$t3,4($t1)
1:
	beqz	$t2,3f
	lw	$t4,($t2)
	beq	$t4,$a0,2f
	lw	$t2,4($t2)
	lw	$t3,4($t3)
	j	1b
2:
	sw	$a1,($t3)
	la	$v0,SYM(ok)
	jr	$ra
3:
	lw	$a2,4($a2)
	j	set_variable

Lunbound:
	move	$a1,$a0
	la	$a0,str_unbound
	j	error

	.globl	define_variable
define_variable:
	lw	$t0,($a2)
	lw	$t1,($t0)
	lw	$t2,4($t0)
1:
	beqz	$t1,3f
	lw	$t3,($t1)
	beq	$t3,$a0,2f
	lw	$t1,4($t1)
	lw	$t2,4($t2)
	j	1b
2:
	sw	$a1,($t2)
	j	4f
3:
	addi	$sp,$sp,-16
	sw	$zero,($sp)
	sw	$ra,12($sp)
	lw	$t0,($a2)
	sw	$a1,8($sp)
	lw	$a1,($t0)
	sw	$t0,4($sp)
	jal	cons
	lw	$t0,4($sp)
	sw	$a0,($t0)
	lw	$a0,8($sp)
	lw	$a1,4($t0)
	jal	cons
	lw	$t0,4($sp)
	sw	$a0,4($t0)
	lw	$ra,12($sp)
	addi	$sp,$sp,16
4:
	la	$v0,SYM(ok)
	jr	$ra


### Reader and symbols

	.globl	read
read:
	addi	$sp,$sp,-16
	sw	$ra,12($sp)
	sw	$s0,8($sp)
	sw	$zero,4($sp)
	sw	$zero,($sp)
	move	$s0,$a0
Lwhitespace:
	move	$a0,$s0
	jal	readchar
	li	$t1,' '
	beq	$a0,$t1,Lwhitespace
	li	$t1,'\n'
	beq	$a0,$t1,Lwhitespace
	li	$t1,'\t'
	beq	$a0,$t1,Lwhitespace
	li	$t1,'\f'
	beq	$a0,$t1,Lwhitespace
	li	$t1,'0'
	blt	$a0,$t1,1f
	li	$t1,'9'
	li	$t2,0
	ble	$a0,$t1,Lread_num
1:
	li	$t1,'+'
	bne	$a0,$t1,2f
	move	$t0,$a0
	sw	$t0,4($sp)
	move	$a0,$s0
	jal	peekchar
	lw	$t0,4($sp)
	move	$t1,$a0
	move	$a0,$t0
	li	$t2,'0'
	blt	$t1,$t2,2f
	li	$t2,'9'
	bgt	$t1,$t2,Lread_symbol
	move	$a0,$s0
	jal	readchar
	li	$t2,0
	j	Lread_num
2:
	li	$t1,'-'
	bne	$a0,$t1,3f
	move	$t0,$a0
	sw	$t0,4($sp)
	move	$a0,$s0
	jal	peekchar
	lw	$t0,4($sp)
	move	$t1,$a0
	move	$a0,$t0
	li	$t2,'0'
	blt	$t1,$t2,3f
	li	$t2,'9'
	bgt	$t1,$t2,Lread_symbol
	move	$a0,$s0
	jal	readchar
	li	$t2,1
	j	Lread_num
3:
	sw	$a0,4($sp)
	jal	is_nondigit_symbol_char
	bnez	$a0,Lread_symbol
	lw	$a0,4($sp)
7:
	li	$t1,'('
	beq	$a0,$t1,Lread_list
	li	$t1,'\''
	beq	$a0,$t1,Lread_quote
	li	$t1,'\"'
	beq	$a0,$t1,Lread_string
	li	$t1,'#'
	beq	$a0,$t1,Lread_hash
	li	$t1,';'
	beq	$a0,$t1,Lread_comment
	li	$t1,-1
	bne	$a0,$t1,Lunexpected_char
	la	$a0,SYM(Eof)
	lw	$s0,8($sp)
	lw	$ra,12($sp)
	addi	$sp,$sp,16
	jr	$ra
Lunexpected_char:
	la	$a0,str_bad_read
	li	$a1,0
	j	error

Lread_num:
	addi	$t0,$a0,-'0'
	sw	$t0,4($sp)
	sw	$t2,($sp)
1:
	move	$a0,$s0
	jal	peekchar
	li	$t1,'0'
	blt	$a0,$t1,2f
	li	$t1,'9'
	bgt	$a0,$t1,2f
	move	$a0,$s0
	jal	readchar
	lw	$t0,4($sp)
	addi	$a0,$a0,-'0'
	li	$t1,10
	mul	$t0,$t0,$t1
	add	$t0,$t0,$a0
	sw	$t0,4($sp)
	j	1b
2:
	lw	$t0,4($sp)
	lw	$t2,($sp)
	move	$a0,$t0
	beqz	$t2,3f
	neg	$a0,$a0
3:
	sll	$a0,$a0,3
	ori	$a0,$a0,TAG_FIXNUM
	lw	$s0,8($sp)
	lw	$ra,12($sp)
	addi	$sp,$sp,16
	jr	$ra

Lread_symbol:
	lw	$a0,4($sp)
	li	$t1,'A'
	blt	$a0,$t1,1f
	li	$t1,'Z'
	bgt	$a0,$t1,1f
	addi	$a0,$a0,32
1:
	addi	$sp,$sp,-16
	sb	$a0,($sp)
	addi	$t0,$sp,1
2:
	sw	$t0,20($sp)
	move	$a0,$s0
	jal	peekchar
	jal	is_nondigit_symbol_char
	bnez	$a0,Lconsume
	move	$a0,$s0
	jal	peekchar	# XXX
	li	$t1,'0'
	blt	$a0,$t1,4f
	li	$t1,'9'
	bgt	$a0,$t1,4f
Lconsume:
	move	$a0,$s0
	jal	readchar
	li	$t1,'A'
	blt	$a0,$t1,3f
	li	$t1,'Z'
	bgt	$a0,$t1,3f
	addi	$a0,$a0,32
3:
	lw	$t0,20($sp)
	sb	$a0,($t0)
	addi	$t0,$t0,1
	j	2b
4:
	lw	$t0,20($sp)
	sb	$zero,($t0)
	move	$a0,$sp
	jal	intern
	lw	$s0,24($sp)
	lw	$ra,28($sp)
	addi	$sp,$sp,32
	jr	$ra

Lread_list:
	li	$t0,0
1:
	sw	$t0,4($sp)
	move	$a0,$s0
	jal	peekchar
	li	$t1,')'
	beq	$a0,$t1,2f
	move	$a0,$s0
	jal	read
	lw	$a1,4($sp)
	jal	cons
	move	$t0,$a0
	j	1b
2:
	move	$a0,$s0
	jal	readchar
	lw	$a0,4($sp)
	lw	$s0,8($sp)
	lw	$ra,12($sp)
	addi	$sp,$sp,16
	j	nreverse

Lread_quote:
	move	$a0,$s0
	jal	read
	li	$a1,0
	jal	cons
	move	$a1,$a0
	la	$a0,SYM(quote)
	lw	$s0,8($sp)
	lw	$ra,12($sp)
	addi	$sp,$sp,16
	j	cons

Lread_string:
	addi	$sp,$sp,-32
	sw	$sp,36($sp)
1:
	move	$a0,$s0
	jal	readchar
	li	$t0,'\"'
	lw	$t1,36($sp)
	beq	$a0,$t0,2f
	sb	$a0,($t1)
	addi	$t1,$t1,1
	sw	$t1,36($sp)
	j	1b
2:
	sb	$zero,($t1)
	move	$a1,$sp
	sub	$a0,$t1,$a1
	jal	alloc_string
	lw	$s0,40($sp)
	lw	$ra,44($sp)
	addi	$sp,$sp,48
	jr	$ra

Lread_hash:
	move	$a0,$s0
	jal	readchar
	li	$t0,'t'
	bne	$a0,$t0,1f
	li	$a0,TRUE
	j	2f
1:
	li	$t0,'f'
	bne	$a0,$t0,Lunexpected_char
	li	$a0,FALSE
2:
	lw	$s0,8($sp)
	lw	$ra,12($sp)
	addi	$sp,$sp,16
	jr	$ra

Lread_comment:
	move	$a0,$s0
	jal	readchar
	li	$t0,'\n'
	beq	$a0,$t0,1f
	li	$t0,-1
	beq	$a0,$t0,1f
	j	Lread_comment
1:
	j	Lwhitespace

is_nondigit_symbol_char:
	li	$t0,'a'
	blt	$a0,$t0,1f
	li	$t0,'z'
	bgt	$a0,$t0,5f
	j	4f
1:
	li	$t0,'A'
	blt	$a0,$t0,2f
	li	$t0,'Z'
	ble	$a0,$t0,4f
2:
	la	$t0,ext_alph_chars
3:
	lbu	$t1,($t0)
	beqz	$t1,5f
	beq	$a0,$t1,4f
	addi	$t0,$t0,1
	j	3b
4:
	li	$a0,1
	jr	$ra
5:
	li	$a0,0
	jr	$ra

	.globl	intern
intern:
	move	$a1,$a0
	addi	$sp,$sp,-16
	ZEROFRAME
	sw	$ra,12($sp)
	la	$a0,obarray
1:
	lw	$t0,($a0)
	beqz	$t0,3f
	sw	$a0,8($sp)
	sw	$a1,4($sp)
	jal	str_eql
	bnez	$a0,2f
	lw	$a0,8($sp)
	lw	$a1,4($sp)
	addi	$a0,$a0,SYMBOL_LENGTH
	j	1b
2:
	lw	$a0,8($sp)
	ori	$a0,$a0,TAG_SYMBOL
	lw	$ra,12($sp)
	addi	$sp,$sp,16
	jr	$ra
3:
	sw	$a0,8($sp)
	jal	str_cpy
	lw	$a0,8($sp)
	ori	$a0,$a0,TAG_SYMBOL
	lw	$ra,12($sp)
	addi	$sp,$sp,16
	jr	$ra

str_eql:
	lbu	$t0,($a0)
	lbu	$t1,($a1)
	bne	$t0,$t1,2f
	beqz	$t0,1f
	addi	$a0,$a0,1
	addi	$a1,$a1,1
	j	str_eql
1:
	li	$a0,1
	jr	$ra
2:
	li	$a0,0
	jr	$ra

str_cpy:
	lbu	$t0,($a1)
	beqz	$t0,1f
	sb	$t0,($a0)
	addi	$a0,$a0,1
	addi	$a1,$a1,1
	j	str_cpy
1:
	sb	$zero,($a0)
	jr	$ra


### Printer

	.bss
printer_display_flag:	.skip 4
	.text

	.globl	write
write:
	addi	$sp,$sp,-16
	sw	$ra,12($sp)
	andi	$t0,$a0,7
	bnez	$t0,1f
	beqz	$a0,Lwrite_empty_list
	j	Lwrite_pair
1:
	li	$t1,TAG_FIXNUM
	beq	$t0,$t1,Lwrite_fixnum
	li	$t1,TAG_PROCEDURE
	beq	$t0,$t1,Lwrite_procedure
	li	$t1,TAG_STRING
	beq	$t0,$t1,Lwrite_string
	li	$t0,TRUE
	beq	$a0,$t0,Lwrite_true
	li	$t0,FALSE
	beq	$a0,$t0,Lwrite_false
	j	Lwrite_symbol
Lwrite_empty_list:
	li	$a0,'('
	jal	writechar
	li	$a0,')'
	lw	$ra,12($sp)
	addi	$sp,$sp,16
	j	writechar
Lwrite_true:
	li	$a0,'#'
	jal	writechar
	li	$a0,'t'
	lw	$ra,12($sp)
	addi	$sp,$sp,16
	j	writechar
Lwrite_false:
	li	$a0,'#'
	jal	writechar
	li	$a0,'f'
	lw	$ra,12($sp)
	addi	$sp,$sp,16
	j	writechar
Lwrite_pair:
	lw	$t0,($a0)
	sw	$a0,8($sp)
	li	$a0,'('
	jal	writechar
	lw	$a0,8($sp)
Lnext_element:
	lw	$t0,($a0)
	lw	$t1,4($a0)
	move	$a0,$t0
	sw	$t1,8($sp)
	jal	write
	lw	$t1,8($sp)
	beqz	$t1,Lend_of_list
	li	$a0,' '
	jal	writechar
	lw	$a0,8($sp)
	andi	$t0,$a0,7
	beqz	$t0,Lnext_element
	sw	$a0,8($sp)
	li	$a0,'.'
	jal	writechar
	li	$a0,' '
	jal	writechar
	lw	$a0,8($sp)
	jal	write
Lend_of_list:
	li	$a0,')'
	lw	$ra,12($sp)
	addi	$sp,$sp,16
	j	writechar
Lwrite_fixnum:
	sra	$a0,$a0,3
	addi	$sp,$sp,16
	j	writenum
Lwrite_procedure:
	xori	$a0,$a0,TAG_PROCEDURE
	la	$t0,PAIR_MEM
	blt	$a0,$t0,Lwrite_primitive
	la	$t0,PAIR_MEM + 2*SPACE_SIZE
	bgt	$a0,$t0,Lwrite_primitive
	sw	$a0,8($sp)
	la	$a0,str_proc
	jal	writestr
	lw	$t0,8($sp)
	lw	$t0,4($t0)
	lw	$a0,($t0)
	jal	write
	li	$a0,']'
	lw	$ra,12($sp)
	addi	$sp,$sp,16
	j	writechar
Lwrite_primitive:
	sw	$a0,8($sp)
	la	$a0,str_prim
	addi	$sp,$sp,16
	j	writestr
Lwrite_symbol:
	xori	$a0,$a0,TAG_SYMBOL
	addi	$sp,$sp,16
	j	writestr
Lwrite_string:
	la	$t0,printer_display_flag
	lw	$t0,($t0)
	bnez	$t0,1f
	sw	$a0,8($sp)
	li	$a0,'\"'
	jal	writechar
	lw	$a0,8($sp)
	xori	$a0,$a0,TAG_STRING
	addi	$a0,$a0,5
	jal	writestr
	li	$a0,'\"'
	jal	writechar
	lw	$ra,12($sp)
	addi	$sp,$sp,16
	jr	$ra
1:
	xori	$a0,$a0,TAG_STRING
	addi	$a0,$a0,5
	addi	$sp,$sp,16
	j	writestr


### Strings
	.globl	alloc_string
alloc_string:
	addi	$sp,$sp,-16
	sw	$ra,12($sp)
	sw	$a1,8($sp)
	addi	$a0,$a0,6
	sw	$a0,4($sp)
	sw	$zero,($sp)
	jal	malloc		## XXX alignment 2^3
	bnez	$v0,1f
	jal	gc
	lw	$a0,4($sp)
	jal	malloc
	bnez	$v0,1f
	la	$a0,str_out_of_mem
	li	$a1,0
	j	error
1:
	#  4    1     n    1
	# next mark string 0
	la	$t0,all_strings
	lw	$t1,($t0)
	sw	$t1,($v0)
	sw	$v0,($t0)
	sb	$zero,4($v0)	## mark
	lw	$a1,8($sp)
	addi	$a0,$v0,5
	jal	str_cpy
	ori	$a0,$v0,TAG_STRING
	lw	$ra,12($sp)
	addi	$sp,$sp,16
	jr	$ra


### Lists

	.globl nreverse
nreverse:
	li	$t0,0
1:
	beqz	$a0,2f
	lw	$t1,4($a0)
	sw	$t0,4($a0)
	move	$t0,$a0
	move	$a0,$t1
	j	1b
2:
	move	$a0,$t0
	jr	$ra


### Allocation and garbage collector

	.globl	cons
cons:
	move	$t0,REG_TOSPACE
	li	$t1,SPACE_SIZE
	add	$t0,$t0,$t1
	beq	REG_FREE,$t0,2f
1:
	move	$t0,REG_FREE
	addi	REG_FREE,REG_FREE,8
	sw	$a0,($t0)
	sw	$a1,4($t0)
	move	$a0,$t0
	jr	$ra
2:
	addi	$sp,$sp,-16
	sw	$ra,12($sp)
	sw	$zero,($sp)
	sw	$a0,8($sp)
	sw	$a1,4($sp)
	jal	gc
	lw	$a1,4($sp)
	lw	$a0,8($sp)
	move	$t0,REG_TOSPACE
	li	$t1,SPACE_SIZE
	add	$t0,$t0,$t1
	beq	REG_FREE,$t0,Lout_of_mem
	lw	$ra,12($sp)
	addi	$sp,$sp,16
	j	1b
Lout_of_mem:
	la	$a0,str_out_of_mem
	li	$a1,0
	j	error

#define GC_ROOT(x)		\
	move	$a0,x;		\
	jal	relocate;	\
	move	x,$a0

gc:
	addi	$sp,$sp,-16
	sw	$ra,12($sp)
	#la	$a0,str_gc
	#jal	writestr
	move	$t0,REG_FROMSPACE
	move	REG_FROMSPACE,REG_TOSPACE
	move	REG_TOSPACE,$t0
	move	REG_FREE,$t0
	GC_ROOT($s1)
	GC_ROOT($s2)
	GC_ROOT($s3)
	GC_ROOT($s4)
	#GC_ROOT($s5)
	#GC_ROOT($s6)
	addi	$t1,$sp,16
	la	$t2,gc_top_of_stack
	la	$t3,PAIR_MEM + 2*SPACE_SIZE
	lw	$t2,($t2)
Ltraverse_stack:
	beq	$t1,$t2,Lgc_loop
	lw	$a0,($t1)
	blt	$a0,REG_FROMSPACE,1f
	bgt	$a0,$t3,1f
	jal	relocate
	sw	$a0,($t1)
1:
	addi	$t1,$t1,4
	j	Ltraverse_stack
Lgc_loop:
	beq	$t0,REG_FREE,1f
	lw	$t1,($t0)
	lw	$t2,4($t0)
	move	$a0,$t1
	jal	relocate
	sw	$a0,($t0)
	move	$a0,$t2
	jal	relocate
	sw	$a0,4($t0)
	addi	$t0,$t0,8
	j	Lgc_loop
1:
	la	$t0,all_strings
	lw	$t0,($t0)
	beqz	$t0,2f
	lw	$t1,($t0)
	# t0 previous pointer
	# XXX first string doesn't get GC'd for now
Lsweep_strings:
	beqz	$t1,2f
	addi	$t2,$t1,4
	lb	$t2,($t2)
	bnez	$t2,1f
	lw	$t2,($t1)
	sw	$t2,($t0)	# unlink
	sw	$t2,8($sp)
	sw	$t0,4($sp)
	move	$a0,$t1
	jal	free
	lw	$t0,4($sp)
	lw	$t1,8($sp)
	j	Lsweep_strings
1:
	sb	$zero,4($t1)
	move	$t0,$t1
	lw	$t1,($t0)
	j	Lsweep_strings
2:
	lw	$ra,12($sp)
	addi	$sp,$sp,16
	jr	$ra

relocate:
	beqz	$a0,1f
	andi	$t5,$a0,7
	beqz	$t5,Lrelocate_pair
	li	$t6,TAG_PROCEDURE
	beq	$t5,$t6,Lrelocate_procedure
	li	$t6,TAG_STRING
	beq	$t5,$t6,Lmark_string
1:
	jr	$ra
Lrelocate_procedure:
	la	$t5,PAIR_MEM
	blt	$a0,$t5,1f
	la	$t5,PAIR_MEM + 2*SPACE_SIZE
	bgt	$a0,$t5,1f
	addi	$sp,$sp,-16
	sw	$ra,12($sp)
	xori	$a0,$a0,TAG_PROCEDURE
	jal	relocate
	ori	$a0,$a0,TAG_PROCEDURE
	lw	$ra,12($sp)
	addi	$sp,$sp,16
1:
	jr	$ra
Lrelocate_pair:
	lw	$t5,($a0)
	lw	$t6,4($a0)
	li	$a1,BROKEN_HEART
	beq	$t5,$a1,Lfound_broken_heart
	sw	$t5,(REG_FREE)
	sw	$t6,4(REG_FREE)
	move	$t5,REG_FREE
	addi	REG_FREE,REG_FREE,8
	sw	$a1,($a0)
	sw	$t5,4($a0)
	move	$a0,$t5
	jr	$ra
Lfound_broken_heart:
	move	$a0,$t6
	jr	$ra
Lmark_string:
	xori	$a0,$a0,TAG_STRING
	li	$t5,1
	sb	$t5,4($a0)
	ori	$a0,$a0,TAG_STRING
	jr	$ra

	.bss
gc_top_of_stack:.skip	4
error_sp:	.skip	4
error_pc:	.skip	4
global_env:	.skip	4
image_env:	.skip	4
image_free:	.skip	4

	.align	3
pair_memory:	.skip	2*SPACE_SIZE
all_strings:	.skip	4

	.section	.rodata
ext_alph_chars:	.string	"!$%&*+-./:<=>?@^_~"
str_msg:	.string	"Scheme interpreter\n"
str_fresh:	.string	"(Not been imaged)\n"
str_prim:	.string	"#[primitive]"
str_proc:	.string "#[procedure "
#str_gc:		.string	"GC cycle\n"
str_bad_read:	.string	"Unexpected character"
str_bad_exp:	.string	"Unknown expression type: "
str_unbound:	.string	"Unbound variable: "
str_not_proc:	.string	"Not a procedure: "
str_out_of_mem:	.string	"Out of memory"
str_type_pair:	.string	"Expected a pair: "
str_type_fixnum:.string	"Expected a fixnum: "
str_type_string:.string	"Expected a string: "

prim_addrs:
	.word	prim_eq
	.word	prim_integerp
	.word	prim_num_eql
	.word	prim_lt
	.word	prim_add
	.word	prim_sub
	.word	prim_mul
	.word	prim_quotient
	.word	prim_remainder
	.word	prim_modulo
	.word	prim_pairp
	.word	prim_cons
	.word	prim_car
	.word	prim_cdr
	.word	prim_set_car
	.word	prim_set_cdr
	.word	prim_list
	.word	prim_symbolp
	#.word	prim_symbol2string
	#.word	prim_string2symbol
	#.word	prim_stringp
	#.word	prim_string_length
	.word	prim_procedurep
	.word	prim_read
	.word	prim_write
	.word	prim_display
	.word	prim_newline
	#.word	prim_image
	.word	prim_load

	.section	.data
obarray:
	NAME_SYM(Eof, "Eof")	# unreadable
	NAME_SYM(quote, "quote")
	NAME_SYM(lambda, "lambda")
	NAME_SYM(if, "if")
	NAME_SYM(set, "set!")
	NAME_SYM(begin, "begin")
	NAME_SYM(cond, "cond")
	NAME_SYM(let, "let")
	NAME_SYM(define, "define")
	NAME_SYM(ok, "ok")
	MAKE_SYM("eq?")
	MAKE_SYM("integer?")
	MAKE_SYM("=")
	MAKE_SYM("<")
	MAKE_SYM("+")
	MAKE_SYM("-")
	MAKE_SYM("*")
	MAKE_SYM("quotient")
	MAKE_SYM("remainder")
	MAKE_SYM("modulo")
	MAKE_SYM("pair?")
	MAKE_SYM("cons")
	MAKE_SYM("car")
	MAKE_SYM("cdr")
	MAKE_SYM("set-car!")
	MAKE_SYM("set-cdr!")
	MAKE_SYM("list")
	MAKE_SYM("symbol?")
	#MAKE_SYM("symbol->string")
	#MAKE_SYM("string->symbol")
	#MAKE_SYM("string?")
	#MAKE_SYM("string-length")
	MAKE_SYM("procedure?")
	MAKE_SYM("read")
	MAKE_SYM("write")
	MAKE_SYM("display")
	MAKE_SYM("newline")
	#MAKE_SYM("image")
	MAKE_SYM("load")
	.skip	3568
