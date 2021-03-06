
(in-package :alien)
(named-readtables:in-readtable :fare-quasiquote)

(defvar *memory-limit* 1000 ; 1GB
  "maximum amount of memory in MB")

(defvar *time-limit* 20
  "Search time limit in sec.")

(ftype* max-state-id fixnum)
(defun max-state-id ()
  (unless (or *compile-file-pathname*
              *load-pathname*)
    (log:warn "Slow function: Avoid calling this function in runtime, especially in inner loop!"))
  (floor (* 8 1024 1024 *memory-limit*) ; MB -> bit
         (handler-case
             (max 64 ; for avoiding division-by-zero
                  (eval '(size-of 'state-information)))
           (error ()
             ;; using 64 bit as the lower bound
             64))))

(declaim (fixnum *start-time* *last-milestone*))
(defvar *start-time* 0
  "internal-real-time when the planner has started")
(defvar *last-milestone* 0
  "internal-real-time of the last milestone")

(defun log-milestone (tag)
  (let ((new-milestone (get-internal-real-time)))
    (log:info "[~,3fs] [+~,3fs] ~a"
              (/ (float (- new-milestone *start-time*))
                 internal-time-units-per-second)
              (/ (float (- new-milestone *last-milestone*))
                 internal-time-units-per-second)
              tag)
    (setf *last-milestone* new-milestone)))

(defun recompile-instance-dependent-code ()
  (let ((sb-ext:*inline-expansion-limit* 10))
    (proclaim '(sb-ext:muffle-conditions style-warning sb-ext:compiler-note))
    (asdf:clear-system :alien.instance-dependent)
    (unwind-protect
         (let ((*compile-verbose* nil)
               (*compile-print* nil))
           ;; (asdf:compile-system :alien.instance-dependent :force t)
           (asdf:load-system :alien.instance-dependent :force t :verbose nil))
      ;; ensure the specialised code is removed and does not affect the later debugging
      (asdf:clear-system :alien.instance-dependent))))

(defun output-plan (plan-output-file)
  "write the plan into a file"
  (ensure-directories-exist plan-output-file)
  (with-open-file (s plan-output-file :direction :output
                     :if-exists :supersede
                     :if-does-not-exist :create)
    (print-plan (retrieve-path) s)))

(defvar *optional-features* nil
  "Features added during the full-compilation phase.
Each search specification function should add a corresponding flag to this variable.
See also: function RUN, function SOLVE-COMMON")

;; TODO: solve-many with specifying N

(define-condition no-solution (simple-error)
  ()
  (:report
   (lambda (c s)
     (declare (ignore c)) 
     (format s "Open list exhausted!"))))

(define-condition goal-found (error) ())

(define-condition close-list-full (error) ())

(defun retrieve-path () (invoke-restart (find-restart 'retrieve-path)))

(enumerate status +new+ +open+ +closed+ +dead+)

(defstruct builder storage)

(defstruct (evaluator (:include builder)) function)

(defstruct (open-list (:include builder)) constructor insert pop)

(defstruct (searcher (:include builder)) form)

;; main state information database
(defvar *db*)

;; (ftype* MAKE-STATE-INFORMATION &key (:static *))
;; (ftype* MAKE-STATE-INFORMATION-ARRAY * &key (:static *))
;; (ftype* STATE-INFORMATION-FACTS * &optional *)
;; (ftype* STATE-INFORMATION-GOAL-COUNT *)
;; (ftype* STATE-INFORMATION-OP *)
;; (ftype* STATE-INFORMATION-PARENT *)
;; (ftype* STATE-INFORMATION-STATUS *)
