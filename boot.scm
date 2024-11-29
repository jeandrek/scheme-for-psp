(define (null? obj) (eq? obj '()))

(define (reverse lst)
  (define (loop lst acc)
    (if (null? lst)
        acc
        (loop (cdr lst) (cons (car lst) acc))))
  (loop lst '()))

(define (map proc lst)
  (define (loop lst acc)
    (if (null? lst)
        (reverse acc)
        (loop (cdr lst) (cons (proc (car lst)) acc))))
  (loop lst '()))
