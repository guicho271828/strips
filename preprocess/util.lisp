
(in-package :alien.pddl)

(cl:defmacro define (name cl:&body body)
  (cl:declare (cl:ignore name body))
  (cl:error "This is a dummy macro for editor integration"))

(cl:in-package :alien)

(defmacro defun* (name args &body body)
  (match name
    ((or (and (symbol) name       (<> return-type '*))
         (and (list 'setf _) name (<> return-type '*))
         (and (list name return-type))
         (and (list (and (list 'setf _) name) return-type)))
     (let ((required (or (position-if (lambda (elem) (member elem '(&optional &key &rest &aux))) args)
                         (length args))))
       (iter (for (arg . rest) on args)
             (repeat required)
             (match arg
               ((list arg type)
                (collecting arg into argsyms)
                (collecting type into types))
               (_
                (collecting arg into argsyms)
                (collecting '* into types)))
             (finally
              (let* ((rest-args (nthcdr required args))
                     (rest-types (iter (for elem in rest-args)
                                       (collecting
                                        (if (member elem '(&optional &key &rest &aux))
                                            elem
                                            '*)))))
                (return
                  `(progn
                     (declaim (ftype (function (,@types ,@rest-types) ,return-type) ,name))
                     (defun ,name ,(append argsyms rest-args)
                       ,@body))))))))))

#+(or)
(progn
  (defun* fn (a b c &rest rest)
    (list (+ a b c) rest))
  (defun* (fn list) (a b c &rest rest)
    (list (+ a b c) rest))
  (defun* (fn list) ((a fixnum) b c &rest rest)
    (list (+ a b c) rest)))

(defun %rel (pathname)
  (asdf:system-relative-pathname :alien pathname))

(defmacro print-values (&body form)
  `(multiple-value-call (lambda (&rest args) (values-list (mapcar #'println args)))
     ,@form))

(defmacro print* (&body forms)
  `(progn ,@(mapcar (lambda (x) `(print-values ,x)) forms)))

(defmacro errors (&body form)
  `(handler-case
       (progn ,@form)
     (error (c)
       (format t "~&this is an error:~% ~a~%" c))))

(defmacro with-parsed-information (info &body body)
  "Binds the special variables using INFO, which is a parsed & flattened result of pddl files (see 2-translate.lisp).
   *types* *objects* *predicates* *init* *goal* *axioms* *actions* "
  `(match ,info
     ((plist :type *types*
             :objects *objects*
             :predicates *predicates*
             :init *init*
             :goal *goal*
             :axioms *axioms*
             :actions *actions*)
      ,@body)))

(defmacro with-parsed-information2 (info &body body)
  "Binds the special variables using INFO, which is a parsed & flattened result of pddl files (see 2-translate.lisp).
   *types* *objects* *predicates* *init* *goal* *axioms* *actions* "
  `(match ,info
     ((plist :monotonicity *monotonicity*
             :type *types*
             :objects *objects*
             :predicates *predicates*
             :init *init*
             :goal *goal*
             :axioms *axioms*
             :actions *actions*)
      ,@body)))

(defmacro with-parsed-information3 (info &body body)
  "Binds the special variables using INFO, which is a parsed & flattened result of pddl files (see 2-translate.lisp).
   *types* *objects* *predicates* *init* *goal* *axioms* *actions* "
  `(match ,info
     ((plist :facts *facts*
             :ops *ops*
             :ground-axioms *ground-axioms*
             :monotonicity *monotonicity*
             :type *types*
             :objects *objects*
             :predicates *predicates*
             :init *init*
             :goal *goal*
             :axioms *axioms*
             :actions *actions*)
      ,@body)))

(defmacro with-parsed-information4 (info &body body)
  "Binds the special variables using INFO, which is a parsed & flattened result of pddl files (see 2-translate.lisp).
   *types* *objects* *predicates* *init* *goal* *axioms* *actions* "
  `(match ,info
     ((plist :axiom-layers *axiom-layers*
             :facts *facts*
             :ops *ops*
             :ground-axioms *ground-axioms*
             :monotonicity *monotonicity*
             :type *types*
             :objects *objects*
             :predicates *predicates*
             :init *init*
             :goal *goal*
             :axioms *axioms*
             :actions *actions*)
      ,@body)))

(defmacro with-parsed-information5 (info &body body)
  "Binds the special variables using INFO, which is a parsed & flattened result of pddl files (see 2-translate.lisp).
   *types* *objects* *predicates* *init* *goal* *axioms* *actions* "
  (once-only (info)
    `(let ((*fact-index* (getf ,info :fact-index))
           (*fact-size* (getf ,info :fact-size))
           (*fact-trie* (getf ,info :fact-trie))
           (*state-size* (getf ,info :state-size))
           (*op-sexp-index* (getf ,info :op-sexp-index))
           (*instantiated-ops* (getf ,info :instantiated-ops))
           (*op-size* (length (getf ,info :instantiated-ops)))
           (*sg* (getf ,info :successor-generator))
           (*instantiated-axiom-layers* (getf ,info :instantiated-axiom-layers))
           (*instantiated-init* (getf ,info :instantiated-init))
           (*instantiated-goal* (getf ,info :instantiated-goal))

           (*axiom-layers* (getf ,info :axiom-layers))
           (*facts* (getf ,info :facts))
           (*ops* (getf ,info :ops))
           
           (*ground-axioms* (getf ,info :ground-axioms))
           (*monotonicity* (getf ,info :monotonicity))
           (*types* (getf ,info :type))
           (*objects* (getf ,info :objects))
           (*predicates* (getf ,info :predicates))
           (*init* (getf ,info :init))
           (*goal* (getf ,info :goal))
           (*axioms* (getf ,info :axioms))
           (*actions* (getf ,info :actions))

           *delete-relaxed-sg*
           *delete-relaxed-ops*
           *delete-relaxed-op-size*
           *delete-only-sg*
           *delete-only-ops*
           *delete-only-op-size*)
       ,@body)))

(defun positive (form)
  ;; (declare (optimize (speed 3) (safety 0)))
  (not (member (car form) '(not increase)))
  ;; (ematch form
  ;;   ((list* (or 'not 'increase) _)
  ;;    nil)
  ;;   (_
  ;;    ;; (list* name  _)
  ;;    ;; (assert (member name *predicates* :key #'first))
  ;;    t))
  )

(defun negative (form)
  (ematch form
    ((list* 'not _)
     t)
    ((list* _)
     nil)))

(defun ensure-zeroary-to-atom (f)
  "convert a nullary predicate to a prolog atom, e.g. (goal) -> goal"
  (match f
    ((list x) x)
    (_ f)))

(defun ensure-zeroary-to-list (f)
  "convert a nullary predicate to a prolog list, e.g. (goal) -> (list goal)"
  (match f
    ((list x) `(list ,x))
    (_ f)))

(declaim (inline make-bit-vector))
(defun make-bit-vector (length)
  (make-array length :element-type 'bit :initial-element 0))

(declaim (inline make-a-array))
(defun make-a-array (dimensions &key (element-type t) (initial-element 0))
  (make-array dimensions
              :element-type element-type
              :adjustable t
              :fill-pointer 0
              :initial-element initial-element))

(declaim (inline linear-extend))
(defun linear-extend (vector element &optional (initial-element nil initial-element-supplied-p))
  (if-let ((result (vector-push element vector)))
    result
    (progn
      (log:trace "extending array: ~a -> ~a" (array-total-size vector) (* 2 (array-total-size vector)))
      (if initial-element-supplied-p
          (adjust-array vector (* 2 (array-total-size vector)) :initial-element initial-element)
          (adjust-array vector (* 2 (array-total-size vector))))
      (vector-push element vector))))


(defun safe-aref (vector i &optional (initial-element nil initial-element-supplied-p))
  (if (not (array-in-bounds-p vector i))
      (if (adjustable-array-p vector)
          (let ((old-size (array-total-size vector))
                (new-size (expt 2 (integer-length i))))
            (if initial-element-supplied-p
                (adjust-array vector new-size :initial-element initial-element)
                (adjust-array vector new-size))
            (aref vector i))
          initial-element)
      (aref vector i)))

#+(or)
(defmacro safe-aref (vector i &optional (initial-element nil initial-element-supplied-p))
  (once-only (vector i)
    `(if (not (array-in-bounds-p ,vector ,i))
         (if (adjustable-array-p ,vector)
             (let ((old-size (array-total-size ,vector))
                   (new-size (expt 2 (integer-length ,i))))
               (adjust-array ,vector new-size)
               ,@(when initial-element-supplied-p
                   `((dotimes (offset (- new-size old-size))
                       (setf (aref ,vector (+ old-size offset)) ,initial-element))))
               (aref ,vector ,i))
             ,initial-element)
         (aref ,vector ,i))))

;; (defun safe-aref (vector i &optional (initial-element nil initial-element-supplied-p))
;;   (if (not (array-in-bounds-p vector i))
;;       (progn
;;         (when (adjustable-array-p vector)
;;           (log:trace "extending array: ~a -> ~a" (array-total-size vector) (* 2 (array-total-size vector)))
;;           (if initial-element-supplied-p
;;               (adjust-array vector (* 2 (array-total-size vector)) :initial-element initial-element)
;;               (adjust-array vector (* 2 (array-total-size vector)))))
;;         initial-element)
;;       (aref vector i)))
;; 
;; (defun (setf safe-aref) (newval vector i &optional (initial-element nil initial-element-supplied-p))
;;   (when (not (array-in-bounds-p vector i))
;;     (log:trace "extending array: ~a -> ~a" (array-total-size vector) (* 2 (array-total-size vector)))
;;     (if initial-element-supplied-p
;;         (adjust-array vector (* 2 (array-total-size vector)) :initial-element initial-element)
;;         (adjust-array vector (* 2 (array-total-size vector)))))
;;   (setf (aref vector i) newval))

(defmacro in-compile-time ((environment) &body body &environment env)
  (check-type environment symbol)
  (eval `(let ((,environment ,env)) (progn ,@body))))

(defmacro ftype* (name &rest types)
  `(declaim (ftype (function ,(butlast types) ,(lastcar types)) ,name)))

(defmacro runtime-type (form)
  `(handler-case
       ,form
     (unbound-variable ()
       (simple-style-warning "form ~a failed during type computation, defaulting to *" ',form)
       '*)))

(deftype runtime (typename &rest args)
  `(,typename ,@(mapcar (lambda (form)
                          (handler-case (eval form)
                            (error (c)
                              (log:warn "caught ~a:  ~a" (type-of c) c)
                              (log:warn "Runtime type expansion failed at type ~a, using * instead" form)
                              '*)))
                        args)))

(defun println (x)
  (write x :escape nil) (terpri))

(defmacro break+ (&rest args)
  (let* ((last-form (lastcar args))
         (last last-form)
         (butlast (butlast args)))
    (once-only (last)
      `(progn
         (break "~@{~a~2%~<;;~@; result:~4i~:@_~a~;~:>~2%~}"
                ,@(iter (for arg in butlast)
                        (collect `',arg)
                        (collect `(list ,arg)))
                ',last-form (list ,last))
         ,last))))

(defun bell ()
  "This is a function I use for 'ringing a bell' from the shell,
so that I am noticed when a long computation finishes."
  (uiop:run-program "bell"))

(define-symbol-macro bell (bell))

(defun package< (a b)
  (match* (a b)
    (((package :name n1) (package :name n2))
     (when (string< n1 n2) t))))
(defun package= (a b)
  (eq a b))

(defun symbol< (a b)
  (match* (a b)
    (((symbol :package p1) (symbol :package p2))
     (cond
       ((and (not p1) (not p2))
        (when (string< a b) t))
       ((and (not p1) p2)
        t)
       ((and p1 (not p2))
        nil)
       ((and p1 p2)
        (or (package< p1 p2)
            (and (package= p1 p2)
                 (when (string< a b) t))))))))
(defun symbol= (a b)
  (eq a b))

(defun fact< (arg1 arg2)
  (match* (arg1 arg2)
    (((cons car1 cdr1) (cons car2 cdr2))
     (or (fact< car1 car2)
         (and (equalp car1 car2)
              (fact< cdr1 cdr2))))
    ((nil (cons _ _))
     t)
    (((cons _ _) nil)
     nil)
    ((nil nil)
     nil)
    (((symbol) (symbol))
     (symbol< arg1 arg2))))
(defun fact= (arg1 arg2)
  (equalp arg1 arg2))
