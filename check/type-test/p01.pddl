
(define (problem p)
    (:domain d)
  (:objects o)
  (:init)
  (:goal (goal)))

;; If the solver treats (not (p ?x)) as (and (mytype ?x) (not (p ?x))),
;; then this problem is unsolvable because (mytype o) is not satisfied.

;; Fast downward solves this problem by applying (a o), where (mytype o) is false.
;; This means (not (p ?x)) == (or (not (mytype ?x)) (not (p ?x))).

;; In fact, it is not possible to achieve this.
;; (p ?x) implies (mytype ?x).
;; When (not (p ?x)), it does not imply (mytype ?x), so (mytype ?x) and (not (mytype ?x)) are both ok.

;; ???? still unclear, but FD should be handling this fine...
