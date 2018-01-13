
(in-package :strips)
(named-readtables:in-readtable :fare-quasiquote)

(defun goal-count (state)
  (let ((count 0))
    (labels ((rec (axiom)
               (ematch axiom
                 ((effect con)
                  (iter (for c in con)
                        (let ((i (if (minusp c)
                                     (lognot c) c)))
                          (if (< i *fact-size*)
                              ;; is a fact
                              (when (or (and (minusp c) (= 0 (aref state i)))
                                        (= 1 (aref state i)))
                                (incf count))
                              (rec (aref *instantiated-axioms*
                                         (- i *fact-size*))))))))))
      (rec (aref *instantiated-axioms* *instantiated-goal*))
      count)))
