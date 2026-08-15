; SICP-style algorithms and macro use.
(define (fib n)
  (let loop ((a 0) (b 1) (n n))
    (if (= n 0) a (loop b (+ a b) (- n 1)))))

(define (quicksort xs)
  (if (null? xs)
      '()
      (let ((pivot (car xs)))
        (define (partition pred xs)
          (cond ((null? xs) '())
                ((pred (car xs)) (cons (car xs) (partition pred (cdr xs))))
                (else (partition pred (cdr xs)))))
        (append (quicksort (partition (lambda (x) (< x pivot)) (cdr xs)))
                (list pivot)
                (quicksort (partition (lambda (x) (>= x pivot)) (cdr xs)))))))

(define-syntax unless
  (syntax-rules ()
    ((unless test body ...) (if (not test) (begin body ...)))))

(write (list (fib 35)
             (quicksort '(9 1 8 2 7 3 6 4 5))
             (call-with-values (lambda () (values 'a 'b 'c)) list)
             (let ((x 'ok)) (unless #f x))))
(newline)
