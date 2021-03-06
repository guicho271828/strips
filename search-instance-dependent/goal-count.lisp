
(in-package :alien)

(in-compilation-phase ((not (or phase/packed-structs phase/full-compilation)))
(defun goal-count ()
  (push 'goal-count *optional-features*)
  (make-evaluator
   :storage '(list 'goal-count)
   :function '(function goal-count-heuristics)))
)

(in-compilation-phase ((and goal-count phase/packed-structs))
(alien.lib:define-packed-struct goal-count ()
  (value 0 (runtime integer 0 *fact-size*)))
)

(in-compilation-phase ((and goal-count phase/full-compilation))
(ftype* goal-count-heuristics state+axioms (runtime integer 0 *fact-size*))
(defun goal-count-heuristics (state)
  (- (load-time-value (count 1 (non-axiom-goals)))
     (count 1 (bit-and (load-time-value (non-axiom-goals))
                       state
                       (load-time-value (make-state+axioms))))))
)


