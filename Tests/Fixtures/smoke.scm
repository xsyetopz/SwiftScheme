; SwiftScheme CLI smoke fixture
(define (sum xs)
  (let loop ((xs xs) (acc 0))
    (if (null? xs) acc (loop (cdr xs) (+ acc (car xs))))))
(display "sum=")
(write (sum (map (lambda (x) (* x x)) '(1 2 3 4))))
(newline)
