(in-package :strips)
(named-readtables:in-readtable :fare-quasiquote)

;;; open list

;; slow, initial implementation of bucket open list as a placeholder for initial submission

(defstruct bucket-open-list
  "bucket open list with a single key, lifo tiebreaking; initial, slow implementation."
  (min-key most-positive-fixnum :type fixnum) ; initially out-of-bounds
  (buckets (make-array 32 :element-type 'list :initial-element nil :adjustable t)))

;; the state of min-key is either out-of-bounds or actual.

(defun bucket-open-list-insert (open key element)
  (ematch open
    ((bucket-open-list buckets :min-key (place min-key))
     (unless (array-in-bounds-p buckets key)
       (adjust-array buckets (expt 2 (integer-length key)) :initial-element nil))
     (push element (aref buckets key))
     (minf min-key key))))

(defun bucket-open-list-pop (open)
  (ematch open
    ((bucket-open-list buckets :min-key (place min-key))
     (when (= min-key most-positive-fixnum) 
       (error 'no-solution))
     (prog1 (pop (aref buckets min-key))
       (if-let ((pos (position-if #'identity buckets :start min-key)))
         (setf min-key pos)
         (setf min-key most-positive-fixnum))))))

(defun bucket-open-list (evaluator)
  (ematch evaluator
    ((evaluator storage function)
     (make-open-list
      :storage storage
      :constructor 'make-bucket-open-list
      :insert `(lambda (open id state)
                 (bucket-open-list-insert
                  open
                  (funcall ,function state)
                  id))
      :pop 'bucket-open-list-pop))))
