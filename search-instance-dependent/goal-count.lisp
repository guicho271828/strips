
(in-package :strips)

#+strips::phase/packed-structs
(strips.lib:define-packed-struct goal-count ()
  (goal-count 0 (runtime integer 0 *state-size*)))

#+strips::phase/full-compilation
(ftype* goal-count-heuristics state+axioms (runtime integer 0 *state-size*))
#+strips::phase/full-compilation
(defun goal-count-heuristics (state)
  (let ((count 0))
    (labels ((find-axiom (id)
               (iter (for v in-vector *instantiated-axiom-layers*)
                     (iter (for e in-vector v)
                           (when (= (effect-eff e) id)
                             (return-from find-axiom e)))))
             (rec (axiom)
               (ematch axiom
                 ((effect con)
                  (iter (for c in-vector con)
                        (let ((i (if (minusp c)
                                     (lognot c) c)))
                          (if (< i *fact-size*)
                              ;; is a fact
                              (when (or (and (minusp c) (= 1 (aref state i)))
                                        (= 0 (aref state i)))
                                (incf count))
                              (rec (find-axiom i)))))))))
      (rec (find-axiom *instantiated-goal*))
      count)))

#-(or strips::phase/packed-structs strips::phase/full-compilation)
(defun goal-count ()
  (make-evaluator
   :storage 'goal-count
   :function 'goal-count-heuristics))
