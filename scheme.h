#ifndef _SCHEME_H_
#define _SCHEME_H_

#define TAG_PAIR	0
#define TAG_FIXNUM	1
#define TAG_PROCEDURE	2
#define TAG_SYMBOL	3
#define TAG_STRING	4

#if 0
#define TAG_CHARACTER	5
#define TAG_VECTOR	6
#define TAG_future	7
#endif

#ifdef __ASSEMBLER__

#define CHECK_PAIR(x)			\
	beqz	x,1f;			\
	andi	$t0,x,7;		\
	beqz	$t0,2f;			\
1:					\
	move	$a1,x;			\
	la	$a0,str_type_pair;	\
	j	error;			\
2:

#define CHECK_FIXNUM(x) 		\
	andi	$t0,x,7;		\
	li	$t1,TAG_FIXNUM;		\
	beq	$t0,$t1,1f;		\
	move	$a1,x;			\
	la	$a0,str_type_fixnum;	\
	j	error;			\
1:

#define CHECK_STRING(x) 		\
	andi	$t0,x,7;		\
	li	$t1,TAG_STRING;		\
	beq	$t0,$t1,1f;		\
	move	$a1,x;			\
	la	$a0,str_type_string;	\
	j	error;			\
1:

#define DYADIC_ARGS		\
	lw	$t0,4($a0);	\
	lw	$a1,($t0);	\
	lw	$a0,($a0)

#endif

#ifndef __ASSEMBLER__

/* scheme.S */
void	scheme_main(void);
void	error(char *, void *);
void	*intern(char *);
void	*cons(void *, void *);
void	define_variable(void *, void *, void *);

#define PRIMITIVE	__attribute__ ((aligned (8)))

struct prim_decl {
	char	*name;
	void	*(*addr)(void *);
};

#define CHECK_FIXNUM(x)							\
	do {								\
		if (((uint32_t)(x) & 7) != TAG_FIXNUM)			\
			error("Expected a fixnum: ", (void *)(x));	\
	} while (0)

#endif

#endif /* !_SCHEME_H_ */
