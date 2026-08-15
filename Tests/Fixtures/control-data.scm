; Derived control and data fixture.
(define (classify n)
  (case n ((1 2) 'small) (else 'other)))
(define (steps n)
  (do ((i 0 (+ i 1)) (out '() (cons i out)))
      ((= i n) out)))
(define observed '())
(define wind-result
  (dynamic-wind
    (lambda () (set! observed (cons 'before observed)))
    (lambda () (call-with-values (lambda () (values 'left 'right)) list))
    (lambda () (set! observed (cons 'after observed)))))
(write
  (list (classify 2)
        (classify 9)
        (steps 3)
        `(head ,wind-result ,@(list 'tail))
        observed
        (string->list "a")
        (vector->list '#(x y))))
(newline)
