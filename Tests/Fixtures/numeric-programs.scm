; Exact arithmetic and complex-number fixture derived from portable Project Euler patterns.
(define (factorial n)
  (let loop ((n n) (acc 1))
    (if (= n 0) acc (loop (- n 1) (* acc n)))))

(define (integer-sqrt-check n)
  (= (sqrt (* n n)) n))

(define huge (factorial 100))
(define ratio (+ 1/2 1/3 1/7))
(define z (* 12345678901234567890/7+9/11i 7-11i))

(write
  (list huge
        ratio
        z
        (integer-sqrt-check 123456789012345678901234567890)
        (= huge (string->number (number->string huge)))
        (= z (string->number (number->string z)))
        (magnitude 300000000000000000000+400000000000000000000i)
        (rationalize 0.3 1/10)))
(newline)
