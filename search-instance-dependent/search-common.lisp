
;; common search-related functions
;; TODO: applicable ops and apply-axioms are suboptimal.

(in-package :strips)

#-(or strips::phase/packed-structs strips::phase/full-compilation)
(progn
  (ftype* initial-state+axioms *)
  (ftype* report-if-goal * * *)
  (ftype* applicable-ops * * *)
  (ftype* apply-axioms * *)
  (ftype* apply-axiom-layer * * *)
  (ftype* apply-op * * * *)
  (ftype* apply-effect * * * *))

#+strips::phase/packed-structs
(deftype op-id ()
  "maximum range (length *instantiated-ops*) is an invalid op for the initial state"
  `(runtime integer 0 (length *instantiated-ops*)))

#+strips::phase/full-compilation
(progn

(ftype* initial-state+axioms state+axioms)
(defun initial-state+axioms ()
  (let ((state (make-state+axioms)))
    (iter (for f in-vector *instantiated-init*)
          (setf (aref state f) 1))
    (apply-axioms state)
    state))

(ftype* report-if-goal state+axioms (function (&rest *) *) boolean)
(defun report-if-goal (state callback)
  (if (= 1 (aref state *instantiated-goal*))
      (progn (restart-bind ((retrieve-path callback))
               (cerror "continue searching" 'goal-found))
             t)
      nil))

(ftype* applicable-ops sg state+axioms (array op-id))
(defun applicable-ops (sg state)
  "Parse the successor generator. slow version"
  (let ((results (load-time-value
                  (make-a-array (length *instantiated-ops*) :element-type 'op-id))))
    (setf (fill-pointer results) 0) 
    (labels ((rec (node)
               (ematch node
                 ((type list)
                  (dolist (op-id node)
                    (vector-push op-id results)))
                 ((sg-node variable then else either)
                  (case (aref state variable)
                    (0 (rec else))
                    (1 (rec then)))
                  (rec either)))))
      (rec sg)
      results)))

;; these functions are all destructive.

(ftype* apply-axioms state+axioms state+axioms)
(defun apply-axioms (state)
  #+(or)
  (map nil
       (lambda (layer)
         (apply-axiom-layer layer state))
       *instantiated-axiom-layers*)
  (iter (for layer in-vector *instantiated-axiom-layers*)
        (apply-axiom-layer layer state))
  state)

(ftype* apply-axiom-layer axiom-layer state+axioms state+axioms)
(defun apply-axiom-layer (axioms state) 
  (let* ((len (length axioms))
         (counters (make-array len :element-type 'fixnum)))
    ;; considered axioms get the counter value of -1
    ;; TODO: make it a load-time-value vector or make it dynamic-extent
    ;; (declare (dynamic-extent counters))
    (flet ((decrement (v counter)
             (if (if (minusp v)
                     (= 0 (aref state (lognot v)))
                     (= 1 (aref state v)))
                 (1- counter)
                 counter)))
      
      (dotimes (i len)
        (ematch (aref axioms i)
          ((effect con)
           (loop
              with counter fixnum = (length con)
              for v fixnum across con
              do
                (setf counter (decrement v counter))
              finally
                (setf (aref counters i) counter)))))

      (let ((open nil))
        (loop ; initialize
           for i below len
           for c fixnum across counters
           do
             (when (zerop c) (push i open)))

        (do ((j (pop open) (pop open)))
            ((null j))
          (when (zerop (aref counters j)) ; re-evaluate, since it could be -1
            (decf (aref counters j))      ; -1
            (setf (aref state (effect-eff (aref axioms j))) 1)       ; achieve the axiom
            (loop
               for i below len
               for c fixnum across counters
               do
                 (when (plusp c)
                   (ematch (aref axioms i)
                     ((effect con)
                      (when (find j con) ; TODO: make it O(1)
                        (setf c (decrement j c))
                        (when (zerop c)
                          (push i open))
                        (setf (aref counters i) c)))))))))))
  state)

(ftype* apply-op op state+axioms state+axioms state+axioms)
(defun apply-op (op state child)
  (ematch op
    ((op eff)
     #+(or)
     (map nil (lambda (e) (apply-effect e state child)) eff) ; somehow consing
     (iter (for e in-vector eff)
           (apply-effect e state child))
     child)))

(ftype* apply-effect effect state+axioms state+axioms state+axioms)
(defun apply-effect (effect state child)
  (ematch effect
    ((effect con eff)
     (when (every (lambda (i) (or (and (minusp i)
                                       (= 0 (aref state (lognot i))))
                                  (= 1 (aref state i))))
                  con)
       (if (minusp eff)
           (setf (aref child (lognot eff)) 0)
           (setf (aref child eff) 1)))))
  child)
)


#+strips::phase/packed-structs
(progn
(ftype* applicable-ops/fast state+axioms (array op-id))
(defun applicable-ops/fast (state)
  #+(or)
  (in-compile-time (env)
    ;; checking macroexpansion (disabled)
    (print
     (macroexpand
      '(do-leaf (op-id state #.*sg*)
        (vector-push op-id results))))
    nil)
  (let ((results (load-time-value
                  (make-a-array (length *instantiated-ops*) :element-type 'op-id))))
    (setf (fill-pointer results) 0)
    (do-leaf (op-id state #.*sg*)
      (vector-push op-id results))
    results))

(print-function-size #'applicable-ops/fast)

)
