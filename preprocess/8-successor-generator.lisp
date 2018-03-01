
;; Successor generator is originally a structure similar to decision-tree.
;; Its internal nodes are selector nodes which have several children where each child
;; corresponds to a value of a SAS variable.
;; The leaf nodes are generator nodes.

;; Ours does not handle SAS encoding, and rather a binary encoding.
;; each node has then/else/either branches. to generate a list of applicable operators,
;; traverse the tree as follows:
;; When the current value of the variable is true, follow THEN branch and EITHER branch.
;; When the current value of the variable is false, follow ELSE branch and EITHER branch.

(in-package :strips)
(named-readtables:in-readtable :fare-quasiquote)

(defvar *sg*)

(defstruct (sg-node (:constructor sg-node (variable then else either))
                    (:constructor make-sg-node))
  "VARIABLE corresponds to an index of a fact.
THEN/ELSE/EITHER are child nodes correspinding to the condition for variable V being 1,0, or don't care.
A child node is a generator node or a sg node.
A generator node is just a list containing operator indices."
  (variable -1 :type fixnum)
  (then nil :type (or sg-node list))
  (else nil :type (or sg-node list))
  (either nil :type (or sg-node list)))

(defmethod make-load-form ((sg sg-node) &optional env)
  (make-load-form-saving-slots sg :environment env))

(deftype sg () '(or list sg-node))

(defun generate-sg (instantiated-ops)
  (let ((current nil))
    (iter (for op in-vector instantiated-ops with-index i)
          (setf current (extend-sg current op i)))
    current))

(defun extend-sg (current op index)
  ;; current: current sg node, initially the root node
  ;; op: operator to add to the sg
  (match op
    ((op pre)
     (labels ((rec (current con-index)
                (let* ((condition (safe-aref pre con-index most-positive-fixnum))
                       (var (logabs condition)))
                  (cond
                    ((= condition most-positive-fixnum)
                     ;; no more conditions
                     (ematch current
                       ((type list) ; leaf branch
                        (if (member index current)
                            current
                            (cons index current)))
                       ((sg-node variable then else either) ; inner node
                        (sg-node variable then else (rec either (1+ con-index))))))
                    (t
                     (ematch current
                       ((type list)
                        (if (minusp condition)
                            (sg-node var nil (rec nil (1+ con-index)) current)
                            (sg-node var (rec nil (1+ con-index)) nil current)))
                       ((sg-node variable then else either)
                        (cond
                          ((= var variable)
                           (if (minusp condition)
                               (sg-node var then (rec else (1+ con-index)) either)
                               (sg-node var (rec then (1+ con-index)) else either)))
                          ((< var variable)
                           (if (minusp condition)
                               (sg-node var nil (rec nil (1+ con-index)) current)
                               (sg-node var (rec nil (1+ con-index)) nil current)))
                          ((< variable var)
                           (sg-node variable then else (rec either con-index)))))))))))
       (rec current 0)))))

(defparameter *sg-compilation-threashold* 3000
  "threashold for the number of operators, determining whether it should compile the successor generator")

(defmacro do-leaf ((op-id state sg) &body body &environment env)
  (assert (symbolp state))
  (assert (symbolp op-id))
  (assert (symbolp sg))
  (if (< *sg-compilation-threashold* (length *instantiated-ops*))
      (interpret-iteration-over-leaf op-id state (symbol-value sg) body)
      (compile-iteration-over-leaf op-id state (symbol-value sg) body)))

(defun as-form (body)
  "list of forms -> (progn forms), single list of form -> form itself"
  (if (second body)
      `((progn ,@body))
      body))

(defun assemble-bodies (variable state-sym then-body else-body either-body)
  "construct a compact form for three bodies"
  (let ((conditional
         (cond (then-body
                `((if (= 1 (aref ,state-sym ,variable))
                      ,@(as-form then-body)
                      ,@(as-form else-body))))
               (else-body
                `((if (= 0 (aref ,state-sym ,variable))
                      ,@(as-form else-body))))
               (t nil))))
    (if conditional
        `(,@conditional ,@either-body)
        either-body)))

#|
returns one of:

((if (= 1 (aref state var)) then else) either)
((if (= 1 (aref state var)) then) either)
(if (= 1 (aref state var)) then else)
(if (= 1 (aref state var)) then)              * --- starred versions can be fused
((if (= 0 (aref state var)) else) either)
either                                        *
(if (= 0 (aref state var)) else)              *
nil                                           *

|#

(defun compile-iteration-over-leaf (op-id-sym state-sym sg body)
  "Returns a program that iterates over the leaf of sg, inlining constants, and execute BODY on each loop."
  (with-gensyms (fn)
    (labels ((rec (sg)
               (ematch sg
                 ((sg-node variable then else either)
                  (assemble-bodies variable
                                   state-sym
                                   (rec then)
                                   (rec else)
                                   (rec either)))
                 ((list* op-ids)
                  (if (< (length op-ids) 4)
                      (iter (for id in op-ids)
                            (appending
                             (subst id op-id-sym body))) 
                      (with-gensyms (i)
                        `((dotimes (,i ,(length op-ids))
                            (let ((,op-id-sym (aref ,(make-array (length op-ids)
                                                                 :element-type 'op-id
                                                                 :initial-contents op-ids)
                                                    ,i)))
                              ,@body)))))))))
      (postprocess-iteration-over-leaf `(progn ,@(rec sg))))))

(defvar *packed-conditions*)

(defun postprocess-iteration-over-leaf (body)
  (labels ((r (body)
             (ematch body
               ;; assemble-bodies returns one of these forms:
               (`(progn ,@body)
                 ;; no optimization
                 `(progn ,@(mapcar #'r body)))

               (`(if ,cond ,then ,else)
                 ;; no optimization
                 `(if ,cond ,(r then) ,(r else)))
               
               (`(if (= ,val (aref ,state ,var)) ,then)
                 ;; optimize
                 (r2 then state (- var (mod var 64)) (list (cons var val))))
               
               (_ body)))
           (r2 (body state start vars)
             "start: 64bit aligned variable name"
             (ematch body
               (`(if (= ,val (aref ,state ,var)) ,then)
                 (if (< var (+ start 64))
                     ;; continue to optimize in this iteration
                     (r2 then state start (cons (cons var val) vars))
                     (pack-conditions-and-continue body state start vars)))
               (_
                (ematch vars
                  ((list (cons var val)) ; if length is 1
                   `(if (= ,val (aref ,state ,var)) ,(r body)))
                  (_
                   (pack-conditions-and-continue body state start vars))))))
           (pack-conditions-and-continue (body state start vars)
             (let ((mask 0)
                   (compare 0)
                   (width (- (min *state-size* (+ start 64))
                             start)))
               (iter (for (var . val) in vars)
                     (for offset = (- var start))
                     (setf (ldb (byte 1 offset) mask) 1)
                     (incf *packed-conditions*)
                     (when (= 1 val)
                       (setf (ldb (byte 1 offset) compare) 1)))
               `(if (= 0 (logand ,mask
                                 (logxor ,compare
                                         (strips.lib::%packed-accessor-int ,state ,width ,start))))
                    ,(r body)))))
    (let ((*packed-conditions* 0))
      (prog1 (r body)
        (log:info "packed ~a preconditions" *packed-conditions*)))))

#+(or)
(progn
  (print
   (postprocess-iteration-over-leaf
    '(progn (if (= 1 (aref state var)) then else) either)))

  (print
   (let ((*state-size* 64))
     (postprocess-iteration-over-leaf
      `(if (= 1 (aref state 0))
           (if (= 1 (aref state 1))
               then)))))

  (print
   (let ((*state-size* 5))
     (postprocess-iteration-over-leaf
      `(if (= 1 (aref state 0))
           (if (= 1 (aref state 1))
               then)))))

  (print
   (let ((*state-size* 128))
     (postprocess-iteration-over-leaf
      `(if (= 1 (aref state 0))
           (if (= 1 (aref state 1))
               (if (= 1 (aref state 64))
                   (if (= 1 (aref state 65))
                       then))))))))

(defun interpret-iteration-over-leaf (op-id-sym state-sym sg body)
  (log:warn "falling back to the interpretation based successor generation")
  `(labels ((rec (node)
              (ematch node
                ((type list)
                 (dolist (,op-id-sym node)
                   ,@body))
                ((sg-node variable then else either)
                 (if (= 1 (aref ,state-sym variable))
                     (rec then)
                     (rec else))
                 (rec either)))))
     (rec ,sg)))
