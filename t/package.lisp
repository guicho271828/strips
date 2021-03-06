#|
  This file is a part of alien project.
  Copyright (c) 2017 Masataro Asai (guicho2.71828@gmail.com)
|#

(in-package :cl-user)
(defpackage :alien.test
  (:use :cl
        :alien :pddl
        :fiveam
        :iterate :alexandria :trivia
        :lparallel
        :arrow-macros
        :cl-prolog2)
  (:shadowing-import-from :trivia :<>)
  (:shadowing-import-from :fiveam :run))
(in-package :alien.test)

(named-readtables:in-readtable :fare-quasiquote)


(def-suite :alien)
(in-suite :alien)

(def-suite translate :in :alien)
(in-suite translate)

;; run test with (run! test-name) 

(defun test-condition (c objects predicates)
  (ematch c
    ((or `(not (,name ,@args))
         `(,name ,@args))
     (is (every #'atom args))
     (is (not (member '- args)))
     (dolist (a args)
       (is-true (or (variablep a)
                    (member a objects :key #'car))
                "~a is not a variable nor an object in ~a" a objects))
     (is (not (member name `(and or imply forall exists))))
     (let ((found (assoc name predicates)))
       (is-true found "predicate = ~a not found in predicates: ~%~a" name predicates)
       (is (= (1+ (length args)) (length found)))))
    (_ (let ((*package* (find-package :pddl)))
         (fail "Condition does not follow the expected form: ~%~s" c)))))

(test translate
  (finishes
    (let ((*package* (find-package :cl-user)))
      (parse (asdf:system-relative-pathname :alien "axiom-domains/opttel-adl-derived/p01.pddl"))))

  (for-all ((p (lambda () (random-elt *small-files*))))
    (let (parsed)
      (finishes
        (setf parsed (parse p)))
      (match parsed
        ((list :type types
               :objects objects
               :predicates predicates
               :init _
               :goal goal
               :axioms axioms
               :actions actions)
         (iter (for (type . super) in types)
               (is (atom type))
               (is (atom super)))
         (iter (for (name . type) in objects)
               (is (atom type))
               (is (atom name)))
         (is-false (member '- objects))
         (dolist (p predicates)
           (is-false (member '- p)))
         (let ((list (flatten goal)))
           (is-false (member 'or list))
           (is-false (member 'imply list))
           (is-false (member 'exists list))
           (is-false (member 'forall list))
           (is-false (member '- list)))
         (let ((list (flatten axioms)))
           (is-false (member 'or list))
           (is-false (member 'imply list))
           (is-false (member 'exists list))
           (is-false (member 'forall list))
           (is-false (member '- list)))
         (dolist (a actions)
           (match a
             (`(:action ,_
                        :parameters ,p
                        :original-parameters ,op
                        :precondition (and ,@conditions)
                        :effect (and ,@effects))
               (is-true (every #'variablep p) "~a" p)
               (is-true (every #'variablep op) "~a" op)
               (dolist (c conditions)
                 (test-condition c objects predicates))
               (dolist (e effects)
                 (ematch e
                   (`(forall ,args (when (and ,@conditions) (increase (total-cost) ,_)))
                     (dolist (c conditions)
                       (test-condition c objects predicates))
                     (is-true (every #'variablep args) "non-variables in forall args ~a" args)
                     (is-false (member '- args) "forall args not untyped: ~a" args))
                   (`(forall ,args (when (and ,@conditions) ,c))
                     (dolist (c conditions)
                       (test-condition c objects predicates))
                     (is-true (every #'variablep args) "non-variables in forall args ~a" args)
                     (is-false (member '- args) "forall args not untyped: ~a" args)
                     (test-condition c objects predicates))
                   (_ (let ((*package* (find-package :pddl)))
                        (fail "Effect does not follow the expected form: ~%~s" a))))))
             (_ (let ((*package* (find-package :pddl)))
                  (fail "Action does not follow the expected form: ~%~s" a)))))
         (dolist (a axioms)
           (match a
             (`(:derived ,p (and ,@conditions))
               (is-false (member '- p))
               (dolist (c conditions)
                 (test-condition c objects predicates)))
             (_ (let ((*package* (find-package :pddl)))
                  (fail "Axiom does not follow the expected form: ~%~s" a))))))))))

(defun set= (a b)
  (set-equal a b :test 'equalp))

(test translate2
  (is (set=
       `((hand . object)
         (level . object)
         (beverage . object) 
         (dispenser . object)
         (container . object)
         (ingredient . beverage)
         (cocktail . beverage)
         (shot . container)
         (shaker . container))
       (alien::parse-typed-def '(hand level beverage dispenser container - object
                                  ingredient cocktail - beverage
                                  shot shaker - container))))
  (is (set= '(object location truck)
            (let ((*types* '((truck . location)
                             (location . truck)
                             (truck . object))))
              (alien::flatten-type 'truck))))
  
  (signals error
    (let (*types*)
      (alien::grovel-types '((:types truck - location location - truck)))))
  
  (is (set= '((location ?truck) (truck ?truck))
            (let ((*types* '((truck . location)
                             (location . object))))
              (alien::flatten-types/argument '?truck 'truck))))
  
  (is (set= '((IN ?TRUCK ?THING) (TRUCK ?TRUCK))
            (let ((*types* '((truck . location)
                             (location . object)))
                  (*predicate-types* '((truck location)
                                       (location object)
                                       (in truck object))))
              (alien::flatten-types/predicate `(in ?truck ?thing)))))

  (signals error
    (let ((*types* '((truck . location)
                     (location . object)))
          (*predicate-types* '()))
      (alien::flatten-types/predicate `(in ?truck ?thing))))

  (let ((*types* '((truck . location)
                   (location . object)))
        (*predicate-types* '((truck location)
                             (location object)
                             (in truck object))))
    (multiple-value-bind (w/o-type predicates parsed)
        (alien::flatten-typed-def `(?truck - truck ?thing - object))
      (is (set= '(?truck ?thing) w/o-type))
      (is (set= '((truck ?truck)) predicates))
      (is (set= '((?truck . truck) (?thing . object)) parsed))))

  (let ((*types* '((agent . object)
                   (unit . object)))
        (*predicate-types* '((clean agent object))))
    (is (equal
         '(forall (?u) (imply (and (unit ?u)) (and (and (clean ?v ?u) (agent ?v)))))
         (alien::flatten-types/condition `(forall (?u - unit) (and (clean ?v ?u))))))
    (is (equal
         '(not (and (clean ?v ?u) (agent ?v)))
         (alien::flatten-types/condition `(not (clean ?v ?u))))))

  (let ((*types* '((a . object) (b . object)))
        *predicate-types* *predicates*)
    (alien::grovel-predicates `((:predicates (pred ?x - a ?y - b))))
    (is (set= '((pred ?x ?y)) *predicates*))
    (is (set= '((pred a b)) *predicate-types*))))

(defun collect-results (cps)
  (let (acc)
    (funcall cps
             (lambda (result)
               (push result acc)))
    acc))

(defun nnf-dnf (condition)
  (collect-results (alien::&nnf-dnf condition)))

(defun nnf-dnf/effect (condition)
  (collect-results (alien::&nnf-dnf/effect condition)))

(defun gen-bool ()
  (lambda () (zerop (random 2))))

(defmacro test-dnf (formula)
  (let* ((vars (set-difference (flatten formula) '(or and when)))
         (generators    (mapcar (lambda (v) `(,v (gen-bool))) vars)))
    `(progn
       (print (nnf-dnf ',formula))
       (for-all ,generators
         (is (eq (eval (list 'let
                             (list ,@(mapcar (lambda (v) `(list ',v ,v)) vars))
                             `(or ,@(nnf-dnf ',formula))))
                 ,formula))))))

(test nnf-dnf
  (test-dnf a)
  (test-dnf (or a b))
  (test-dnf (or a b c (or d e)))
  (test-dnf (and x (or a b)))
  (test-dnf (and (or x y) (or a b)))
  (test-dnf (and (or x y) c (or a b)))
  (test-dnf (and (or (and x z) y) c (or a b)))
  (test-dnf (or (and x (or w z)) y))
  (test-dnf (when (or a b)
              (and c d (or e f)))))

(test simplify-effect
  (is (equal '(and (forall nil (when (and) (clear))))
             (alien::simplify-effect `(clear))))

  (ematch (alien::simplify-effect `(when (and) (and (a) (b))))
    (`(and ,@rest)
      (is (set= `((forall nil (when (and) (b)))
                  (forall nil (when (and) (a))))
                rest))))

  (ematch (alien::simplify-effect `(when (and) (forall () (and (a) (b)))))
    (`(and ,@rest)
      (is (set= `((forall nil (when (and) (b)))
                  (forall nil (when (and) (a))))
                rest)))))

(test move-exists/condition
  
  (ematch (alien::move-exists/condition `(exists (a b c) (three a b c)))
    (`(exists ,args ,form)
      (let ((fn (eval `(lambda ,args
                         (flet ((three (a b c) (xor a b c)))
                           ,form)))))
        (for-all ((list (gen-list :length (constantly 3) :elements (gen-bool))))
          (is (eq (apply fn list)
                  (eval `(xor ,@list)))))))
    (_ (fail)))
  ;; (EXISTS (#:A54970 #:B54971 #:C54972) (AND (THREE #:A54970 #:B54971 #:C54972)))

  (finishes
    (print (alien::move-exists/condition `(and
                                            (p1)
                                            (exists (a) (p2 a))
                                            (exists (a) (p3 a)))))
    ;; (EXISTS (#:A54873 #:A54874) (AND (P3 #:A54874) (P2 #:A54873) (P1)))
    
    (print (alien::move-exists/condition `(and
                                            (p1)
                                            (exists (a)
                                                    (and (and (p3 a)
                                                              (p4 a))
                                                         (exists (b) (p2 a b)))))))
    ;; (EXISTS (#:A54875 #:B54876) (AND (P2 #:A54875 #:B54876) (P4 #:A54875) (P3 #:A54875) (P1)))
    
    (print (alien::move-exists/effect `(and (p1)
                                             (and (p1) (p1))
                                             (when (exists (a) (clear a))
                                               (and (p2) (and (p2) (and (p2) (p2))))))))
    ;; (AND (FORALL (#:A54877) (WHEN (AND (CLEAR #:A54877)) (AND (P2) (P2) (P2) (P2)))) (P1) (P1) (P1)) 
    ))

(def-suite grounding :in :alien)
(in-suite grounding)

#+obsolete
(test join-ordering
  (let ((*predicates* '((in-city ?l1 ?c)
                        (in-city ?l2 ?c)
                        (at ?t ?l1)))) 
    (multiple-value-match
        (alien::all-relaxed-reachable2
         (shuffle
          (copy-list
           '((in-city ?l1 ?c)
             (in-city ?l2 ?c)
             (at ?t ?l1)))))
      ((_ `(:- ,_ ,@rest))
       (is (or (set= rest '((REACHABLE-FACT (AT ?T ?L1)) (REACHABLE-FACT (IN-CITY ?L1 ?C))))
               (set= rest '((REACHABLE-FACT (IN-CITY ?L2 ?C)) (REACHABLE-FACT (IN-CITY ?L1 ?C)))))))))
             
  (let ((*predicates* '((LOCATABLE ?V) (VEHICLE ?V) (LOCATION ?L1) (LOCATION ?L2) (AT ?V ?L1) (ROAD ?L1 ?L2))))
    (multiple-value-bind (decomposed temporary)
        (alien::all-relaxed-reachable2
         (shuffle
          (copy-list
           '((LOCATABLE ?V) (VEHICLE ?V) (LOCATION ?L1) (LOCATION ?L2) (AT ?V ?L1) (ROAD ?L1 ?L2)))))
      (print decomposed)
      (print temporary)
      (is (= 2 (length decomposed)))
      (is (<= 4 (length temporary) 8))))

  (is-true (alien::tmp-p '(tmp111)))
  (is-false (alien::tmp-p '(a))))

(defun call-test-ground (info fn)
  (with-parsed-information4 (mutex-invariant (ground (easy-invariant info) *package*))
    (funcall fn)))

(defmacro with-test-ground (info &body body)
  `(call-test-ground ,info (lambda () ,@body)))

(defun mem (elem list)
  (member elem list :test 'equal))

(def-suite relaxed-reachability :in grounding)
(in-suite relaxed-reachability)

(test relaxed-reachability1
  (with-test-ground (alien::parse1 '(define (domain d)
                              (:requirements :alien :typing)
                              (:predicates (d ?x) (p ?x) (goal))
                              (:action a :parameters (?x) :precondition (and) :effect (p ?x))
                              (:derived (d ?x) (p ?x)))
                            '(define (problem p)
                              (:domain d)
                              (:objects o1 o2)
                              (:init )
                              (:goal (goal))))
    (print *monotonicity*)
    (is-true *monotonicity*)
    (is-true (alien::axiom-p '(d ?x)))
    (is-true (alien::added-p '(p ?x)))
    (is-true (alien::monotonic+p '(p ?x)))
    (is-true (alien::static-p '(goal)))
    (print *facts*)
    (print *ground-axioms*)
    (print *ops*)
    (is-true (mem '(d o1) *ground-axioms*))
    (is-true (mem '(p o1) *facts*))
    (is-true (mem '(d o2) *ground-axioms*))
    (is-true (mem '(p o2) *facts*))
    (is-true (mem '((a0 o1) (0)) *ops*))
    (is-true (mem '((a0 o2) (0)) *ops*))))

(test relaxed-reachability2
  ;; parameter ?x is not referenced in the axiom body
  (with-test-ground (alien::parse1 '(define (domain d)
                                      (:requirements :alien :typing)
                                      (:predicates (d ?x) (p) (goal))
                                      (:action a :parameters (?x) :precondition (and) :effect (p))
                                      (:derived (d ?x) (p)))
                                    '(define (problem p)
                                      (:domain d)
                                      (:objects o1 o2)
                                      (:init )
                                      (:goal (goal))))
    (is-true (alien::axiom-p '(d ?x)))
    (is-true (alien::added-p '(p)))
    (is-true (alien::monotonic+p '(p)))
    (is-true (alien::static-p '(goal)))
    (print *facts*)
    (is-true (mem '(p) *facts*))
    (is-true (mem '(d o1) *ground-axioms*))
    (is-true (mem '(d o2) *ground-axioms*))
    (is-true (mem '((a0 o1) (0)) *ops*))
    (is-true (mem '((a0 o2) (0)) *ops*))))

(test relaxed-reachability3
  ;; parameter ?x is a free variable in the axiom body
  (with-test-ground (alien::parse1 '(define (domain d)
                              (:requirements :alien :typing)
                              (:predicates (d) (p ?x) (goal))
                              (:action a :parameters (?x) :precondition (and) :effect (p ?x))
                              (:derived (d) (p ?x)))
                            '(define (problem p)
                              (:domain d)
                              (:objects o1 o2)
                              (:init )
                              (:goal (goal))))
    (is-true (alien::axiom-p '(d)))
    (is-true (alien::added-p '(p ?x)))
    (is-true (alien::monotonic+p '(p ?x)))
    (is-true (alien::static-p '(goal)))
    
    (is-true (mem '(p o1) *facts*))
    (is-true (mem '(p o2) *facts*))
    (is-true (mem '(d) *ground-axioms*))
    (is-true (= 1 (count '(d) *ground-axioms* :test 'equal)))
    (is-true (mem '((a0 o1) (0)) *ops*))
    (is-true (mem '((a0 o2) (0)) *ops*))
    (is-true (mem '((a0 o2) (0)) *ops*))))

(test relaxed-reachability4
  (with-test-ground (alien::parse1 '(define (domain d)
                              (:requirements :alien :typing)
                              (:predicates (d ?x) (p ?x) (p2 ?x) (goal))
                              (:action a :parameters (?x) :precondition (and) :effect (p ?x))
                              (:derived (d) (p2 ?x)))
                            '(define (problem p)
                              (:domain d)
                              (:objects o1 o2)
                              (:init )
                              (:goal (goal))))
    (is-true (mem '(p o1) *facts*))
    (is-true (mem '(p o2) *facts*))
    (is-true (not (mem '(p2 o1) *facts*)))
    (is-true (not (mem '(p2 o2) *facts*)))
    (is-true (not (mem '(d) *ground-axioms*)))
    (is-true (mem '((a0 o1) (0)) *ops*))
    (is-true (mem '((a0 o2) (0)) *ops*))))

#+(or)
(test relaxed-reachability5
  (let (ops-with ops-without)
    (let ((*enable-no-op-pruning* nil))
      (with-test-ground (parse (%rel "axiom-domains/opttel-adl-derived/p01.pddl"))
        (is (= 286 (length *ops*)))
        (setf ops-without *ops*)))
    (let ((*enable-no-op-pruning* t))
      (with-test-ground (parse (%rel "axiom-domains/opttel-adl-derived/p01.pddl"))
        ;; (is (= 286 (length *ops*)))
        (setf ops-with *ops*)))
    (is-true (set-equal ops-without ops-with :test 'equal))))

#+(or)
(test relaxed-reachability6
  (let (ops-with ops-without)
    (let ((*enable-no-op-pruning* nil))
      (with-test-ground (parse (%rel "ipc2011-opt/transport-opt11/p01.pddl"))
        (is (= 616 (length *ops*)))
        (setf ops-without *ops*)))
    (let ((*enable-no-op-pruning* t))
      (with-test-ground (parse (%rel "ipc2011-opt/transport-opt11/p01.pddl"))
        ;; (is (= 286 (length *ops*)))
        (setf ops-with *ops*)))
    (is-true (set-equal ops-without ops-with :test 'equal))))

#+(or)
(test relaxed-reachability-noop
  (let (ops-fd ops-with ops-without)
    (setf ops-fd (num-operator-fd (%rel "check/rovers-noop/p01.pddl")))
    (let ((*enable-no-op-pruning* nil))
      (with-test-ground (parse (%rel "check/rovers-noop/p01.pddl"))
        ;; (print *ops*)
        (is (/= ops-fd (length *ops*)))
        (setf ops-without *ops*)))
    (let ((*enable-no-op-pruning* t))
      (with-test-ground (parse (%rel "check/rovers-noop/p01.pddl"))
        (is (= ops-fd (length *ops*)))
        (setf ops-with *ops*)))))

(test relaxed-reachability7 ; initially true vs false predicates which are never deleted
  (let ((*enable-negative-precondition-pruning-for-fluents* t))
    (with-test-ground (alien::parse1
                       '(define (domain d)
                         (:requirements :alien :typing)
                         (:predicates (p ?x) (q ?x))
                         (:action a :parameters (?x) :precondition (and (not (p ?x))) :effect (q ?x)))
                       '(define (problem p)
                         (:domain d)
                         (:objects a b)
                         (:init (p a))
                         (:goal (and))))
      (is-true (not (mem '(q a) *facts*)))
      (is-true (mem '(q b) *facts*)))))

(test relaxed-reachability8 ; initially true predicates which can be deleted vs which is never deleted
  (let ((*enable-negative-precondition-pruning-for-fluents* t))
    (with-test-ground (alien::parse1
                       '(define (domain d)
                         (:requirements :alien :typing)
                         (:predicates (p ?x) (q ?x) (r ?x))
                         (:action a :parameters (?x) :precondition (not (p ?x)) :effect (q ?x))
                         (:action a :parameters (?x) :precondition (r ?x)       :effect (not (p ?x))))
                       '(define (problem p)
                         (:domain d)
                         (:objects a b)
                         (:init (p a) (p b) (r b))
                         (:goal (and))))
      (is-true (not (mem '(q a) *facts*)))
      (is-true (mem '(q b) *facts*)))))

(test relaxed-reachability9 ; axioms that can become true vs cannot become true
  (let ((*enable-negative-precondition-pruning-for-axioms* t)
        (*enable-negative-precondition-pruning-for-fluents* t))
    (with-test-ground (alien::parse1
                       '(define (domain d)
                         (:requirements :alien :typing)
                         (:predicates (p ?x) (q ?x) (axiom ?x))
                         (:action a :parameters (?x) :precondition (and (not (axiom ?x))) :effect (q ?x))
                         (:derived (axiom ?x) (p ?x)))
                       ;; if (p ?x) can be negative, then (axiom ?x) can also be negative
                       '(define (problem p)
                         (:domain d)
                         (:objects a b)
                         (:init (p a))
                         (:goal (and))))
      (is-true (not (mem '(q a) *facts*)))  ; (p a) is initially true, never deleted, thus (axiom ?x) is always true
      (is-true (mem '(q b) *facts*)))))     ; (p b) is initially false, thus (axiom ?x) can become true

(test relaxed-reachability10 ; axioms that can become true vs cannot become true
  (let ((*enable-negative-precondition-pruning-for-axioms* t)
        (*enable-negative-precondition-pruning-for-fluents* t))
    (with-test-ground (alien::parse1
                       '(define (domain d)
                         (:requirements :alien :typing)
                         (:predicates (p ?x) (q ?x) (axiom ?x) (r ?x))
                         (:action a :parameters (?x) :precondition (and (not (axiom ?x))) :effect (q ?x))
                         (:action a :parameters (?x) :precondition (r ?x)                 :effect (not (p ?x)))
                         (:derived (axiom ?x) (p ?x)))
                       '(define (problem p)
                         (:domain d)
                         (:objects a b)
                         (:init (p a) (p b) (r b))
                         (:goal (and))))
      (is-true (not (mem '(q a) *facts*)))
      (is-true (mem '(q b) *facts*)))))


(test axiom-layer
  (is-true
   (let ((*axioms* `((:derived (reachable ?x) (and (at ?x)))
                     (:derived (reachable ?x) (and (next ?x ?y) (reachable ?y)))))
         (*ground-axioms* `((reachable 0) (reachable 1) (reachable 2)))
         (*facts* `((at 2)))
         (*init* `((next 0 1) (next 1 2)))
         (*predicates* `((next ?x ?y)
                         (reachable ?x)
                         (at ?x)))
         (*axiom-layer-prolog* :swi))
     (set= '(((next 1 2) 0)
             ((next 0 1) 0)
             ((at 2) 0)
             ((reachable 0) 3)
             ((reachable 1) 2)
             ((reachable 2) 1))
           (read-from-string (alien::%axiom-layers)))))
  
  (is-true
   (let ((*axioms* `((:derived (reachable ?x) (and (at ?x)))
                     (:derived (reachable ?x) (and (next ?x ?y) (reachable ?y)))))
         (*ground-axioms* `((reachable 0) (reachable 1) (reachable 2)))
         (*facts* `((at 2)))
         (*init* `((next 0 1) (next 1 2)))
         (*predicates* `((next ?x ?y)
                         (reachable ?x)
                         (at ?x)))
         (*axiom-layer-prolog* :bprolog))
     (set= '(((next 1 2) 0)
             ((next 0 1) 0)
             ((at 2) 0)
             ((reachable 0) 3)
             ((reachable 1) 2)
             ((reachable 2) 1))
           (read-from-string (alien::%axiom-layers)))))


  (with-parsed-information3 (-> "axiom-domains/opttel-adl-derived/p01.pddl"
                              alien::%rel
                              parse
                              easy-invariant
                              ground)
    (finishes (print (axiom-layers))))

  (finishes
    (-> "axiom-domains/opttel-adl-derived/p01.pddl"
      alien::%rel
      parse
      easy-invariant
      ground
      mutex-invariant)))

(in-suite grounding)

(defmacro with-timing (&body forms)
  (with-gensyms (start results)
    `(let ((,start (get-internal-real-time)))
       (let ((,results (multiple-value-list (progn ,@forms))))
         (values-list
          (list*
           (/ (float (- (get-internal-real-time) ,start))
              internal-time-units-per-second)
           ,results))))))

(defparameter *timeout* 600)

(defun num-operator-fd (p &optional (d (alien::find-domain p)))
  (format t "~&Testing FD grounding, without invariant synthesis~%")
  (with-timing
    (handler-case
      (bt:with-timeout (*timeout*)
        (let ((command (format nil "~a --invariant-generation-max-time 0 ~a ~a | grep 'Translator operators' | cut -d' ' -f 3"
                               (alien::%rel "downward/src/translate/translate.py") d p)))
          (write-string command *trace-output*)
          (terpri *trace-output*)
          (read-from-string
           (uiop:run-program `("sh" "-c" ,command)
                             :output :string))))
      (bt:timeout ()
        nil))))

(defun num-operator-ours (p &optional (d (alien::find-domain p)))
  (format t "~&Testing prolog-based grounding, without invariant synthesis~%")
  (with-timing
    (handler-case
        (bt:with-timeout (*timeout*)
          (let ((*package* (find-package :pddl)))
            (with-test-ground (parse p d)
              (format t "~&~a added facts (generic + monotonic+)~%" (length *facts*))
              (format t "~&~a reachable axioms~%" (length *ground-axioms*))
              (values (length *ops*)
                      (member *goal* *ground-axioms* :test 'equal)))))
      (bt:timeout ()
        nil)
      (error (c)
        (let ((r (find-restart 'transfer-error c)))
          (when r
            (invoke-restart 'transfer-error c)))))))

(defparameter *small-files*
  '("researchers-domain/p07.pddl"
    "axiom-domains/opttel-adl-derived/p01.pddl"
    #+(or) "axiom-domains/opttel-alien-derived/p01.pddl"       ; FD is too slow
    "axiom-domains/philosophers-adl-derived/p01.pddl"
    #+(or) "axiom-domains/philosophers-alien-derived/p01.pddl" ; FD is too slow
    "axiom-domains/psr-middle-adl-derived/p01.pddl"             ; ours < fd with negative preconditions
    #+(or) "axiom-domains/psr-middle-alien-derived/p01.pddl"   ; FD is too slow
    "ipc2006-optsat/openstacks/p01.pddl"
    "ipc2006-optsat/pathways/p01.pddl"
    "ipc2006-optsat/pipesworld/p01.pddl"
    "ipc2006-optsat/rovers/p01.pddl"
    ;; "ipc2006-optsat/storage/p01.pddl" ; EITHER type
    "ipc2006-optsat/tpp/p01.pddl"
    "ipc2006-optsat/trucks/p01.pddl"

    "ipc2008-opt/elevators-opt08/p01.pddl"
    "ipc2008-opt/openstacks-opt08/p01.pddl"
    "ipc2008-opt/parcprinter-opt08/p01.pddl"
    "ipc2008-opt/pegsol-opt08/p01.pddl"
    "ipc2008-opt/scanalyzer-opt08/p01.pddl"
    "ipc2008-opt/sokoban-opt08/p01.pddl"
    "ipc2008-opt/transport-opt08/p01.pddl"
    "ipc2008-opt/woodworking-opt08/p01.pddl"

    "ipc2011-opt/barman-opt11/p01.pddl"
    "ipc2011-opt/elevators-opt11/p01.pddl"
    "ipc2011-opt/floortile-opt11/p01.pddl"
    "ipc2011-opt/nomystery-opt11/p01.pddl"
    "ipc2011-opt/openstacks-opt11/p01.pddl"
    "ipc2011-opt/parcprinter-opt11/p01.pddl"
    "ipc2011-opt/parking-opt11/p01.pddl"
    "ipc2011-opt/pegsol-opt11/p01.pddl"
    "ipc2011-opt/scanalyzer-opt11/p01.pddl"
    "ipc2011-opt/sokoban-opt11/p01.pddl"
    "ipc2011-opt/tidybot-opt11/p01.pddl" ; ours < fd with negative preconditions
    "ipc2011-opt/transport-opt11/p01.pddl"
    "ipc2011-opt/visitall-opt11/p01.pddl"
    "ipc2011-opt/woodworking-opt11/p01.pddl"
    "ipc2014-agl/barman-agl14/p01.pddl"
    "ipc2014-agl/cavediving-agl14/p01.pddl"
    "ipc2014-agl/childsnack-agl14/p01.pddl"
    "ipc2014-agl/citycar-agl14/p01.pddl"
    "ipc2014-agl/floortile-agl14/p01.pddl"
    "ipc2014-agl/ged-agl14/p01.pddl"
    "ipc2014-agl/hiking-agl14/p01.pddl"
    "ipc2014-agl/maintenance-agl14/p01.pddl"
    "ipc2014-agl/openstacks-agl14/p01.pddl"
    "ipc2014-agl/parking-agl14/p01.pddl"
    "ipc2014-agl/tetris-agl14/p01.pddl"
    "ipc2014-agl/thoughtful-agl14/p01.pddl"
    "ipc2014-agl/transport-agl14/p01.pddl"
    "ipc2014-agl/visitall-agl14/p01.pddl"))

(defparameter *middle-files*
  '("researchers-domain/p10.pddl"
    "axiom-domains/opttel-adl-derived/p10.pddl"
    #+(or) "axiom-domains/opttel-alien-derived/p10.pddl"       ; FD is too slow
    "axiom-domains/philosophers-adl-derived/p10.pddl"
    #+(or) "axiom-domains/philosophers-alien-derived/p10.pddl" ; FD is too slow
    "axiom-domains/psr-middle-adl-derived/p10.pddl"             ; ours < fd with negative preconditions
    #+(or) "axiom-domains/psr-middle-alien-derived/p10.pddl"   ; FD is too slow
    "ipc2006-optsat/openstacks/p10.pddl"
    "ipc2006-optsat/pathways/p10.pddl"
    "ipc2006-optsat/pipesworld/p10.pddl"
    "ipc2006-optsat/rovers/p10.pddl"
    ;; "ipc2006-optsat/storage/p10.pddl" ; EITHER type
    "ipc2006-optsat/tpp/p10.pddl"
    "ipc2006-optsat/trucks/p10.pddl"

    "ipc2008-opt/elevators-opt08/p10.pddl"
    "ipc2008-opt/openstacks-opt08/p10.pddl"
    "ipc2008-opt/parcprinter-opt08/p10.pddl"
    "ipc2008-opt/pegsol-opt08/p10.pddl"
    "ipc2008-opt/scanalyzer-opt08/p10.pddl"
    "ipc2008-opt/sokoban-opt08/p10.pddl"
    "ipc2008-opt/transport-opt08/p10.pddl"
    "ipc2008-opt/woodworking-opt08/p10.pddl"

    "ipc2011-opt/barman-opt11/p10.pddl"
    "ipc2011-opt/elevators-opt11/p10.pddl"
    "ipc2011-opt/floortile-opt11/p10.pddl"
    "ipc2011-opt/nomystery-opt11/p10.pddl"
    "ipc2011-opt/openstacks-opt11/p10.pddl"
    "ipc2011-opt/parcprinter-opt11/p10.pddl"
    "ipc2011-opt/parking-opt11/p10.pddl"
    "ipc2011-opt/pegsol-opt11/p10.pddl"
    "ipc2011-opt/scanalyzer-opt11/p10.pddl"
    "ipc2011-opt/sokoban-opt11/p10.pddl"
    "ipc2011-opt/tidybot-opt11/p10.pddl" ; ours < fd with negative preconditions
    "ipc2011-opt/transport-opt11/p10.pddl"
    "ipc2011-opt/visitall-opt11/p10.pddl"
    "ipc2011-opt/woodworking-opt11/p10.pddl"
    "ipc2014-agl/barman-agl14/p10.pddl"
    "ipc2014-agl/cavediving-agl14/p10.pddl"
    "ipc2014-agl/childsnack-agl14/p10.pddl"
    "ipc2014-agl/citycar-agl14/p10.pddl"
    "ipc2014-agl/floortile-agl14/p10.pddl"
    "ipc2014-agl/ged-agl14/p10.pddl"
    "ipc2014-agl/hiking-agl14/p10.pddl"
    "ipc2014-agl/maintenance-agl14/p10.pddl"
    "ipc2014-agl/openstacks-agl14/p10.pddl"
    "ipc2014-agl/parking-agl14/p10.pddl"
    "ipc2014-agl/tetris-agl14/p10.pddl"
    "ipc2014-agl/thoughtful-agl14/p10.pddl"
    "ipc2014-agl/transport-agl14/p10.pddl"
    "ipc2014-agl/visitall-agl14/p10.pddl"))

(defparameter *large-files*
  '("researchers-domain/p12.pddl"
    "axiom-domains/opttel-adl-derived/p48.pddl"
    "axiom-domains/opttel-alien-derived/p19.pddl"
    "axiom-domains/philosophers-adl-derived/p48.pddl"
    "axiom-domains/philosophers-alien-derived/p48.pddl"
    "axiom-domains/psr-middle-adl-derived/p50.pddl"
    "axiom-domains/psr-middle-alien-derived/p50.pddl"
    "ipc2011-opt/barman-opt11/p20.pddl"
    "ipc2011-opt/elevators-opt11/p20.pddl"
    "ipc2011-opt/floortile-opt11/p20.pddl"
    "ipc2011-opt/nomystery-opt11/p20.pddl"
    "ipc2011-opt/openstacks-opt11/p20.pddl"
    "ipc2011-opt/parcprinter-opt11/p20.pddl"
    "ipc2011-opt/parking-opt11/p20.pddl"
    "ipc2011-opt/pegsol-opt11/p20.pddl"
    "ipc2011-opt/scanalyzer-opt11/p20.pddl"
    "ipc2011-opt/sokoban-opt11/p20.pddl"
    "ipc2011-opt/tidybot-opt11/p20.pddl"
    "ipc2011-opt/transport-opt11/p20.pddl"
    "ipc2011-opt/visitall-opt11/p20.pddl"
    "ipc2011-opt/woodworking-opt11/p20.pddl"
    "ipc2014-agl/barman-agl14/p20.pddl"
    "ipc2014-agl/cavediving-agl14/p20.pddl"
    "ipc2014-agl/childsnack-agl14/p20.pddl"
    "ipc2014-agl/citycar-agl14/p20.pddl"
    "ipc2014-agl/floortile-agl14/p20.pddl"
    "ipc2014-agl/ged-agl14/p20.pddl"
    "ipc2014-agl/hiking-agl14/p20.pddl"
    "ipc2014-agl/maintenance-agl14/p20.pddl"
    "ipc2014-agl/openstacks-agl14/p20.pddl"
    "ipc2014-agl/parking-agl14/p20.pddl"
    "ipc2014-agl/tetris-agl14/p20.pddl"
    "ipc2014-agl/thoughtful-agl14/p20.pddl"
    "ipc2014-agl/transport-agl14/p20.pddl"
    "ipc2014-agl/visitall-agl14/p20.pddl"))

(defun print-result-table (array x-titles y-titles)
  (format t "~&~{~{~13a~}~%~}"
          `((------- ,@x-titles sum)
            ,@(iter (for y-title in y-titles)
                    (for y from 0)
                    (collecting
                     (cons y-title
                           (iter (for x-title in x-titles)
                                 (for x from 0)
                                 (collecting (aref array x y) into list)
                                 (summing (aref array x y)    into sum)
                                 (finally
                                  (return (append list (list sum))))))))
            (sum ,@(iter (for x-title in x-titles)
                         (for x from 0)
                         (collecting
                          (iter (for y-title in y-titles)
                                (for y from 0)
                                (summing (aref array x y)))))
                 ,(iter (for x-title in x-titles)
                        (for x from 0)
                        (summing
                         (iter (for y-title in y-titles)
                               (for y from 0)
                               (summing (aref array x y)))))))))

(defun test-num-operators (files)
  (setf (cl-rlimit:rlimit cl-rlimit:+rlimit-address-space+) 8000000000)
  (setf *kernel* (make-kernel (cpus:get-number-of-processors)
                              :bindings `((*standard-output* . ,*standard-output*)
                                          (*error-output* . ,*error-output*)
                                          (*trace-output* . ,*trace-output*))))
  (let ((fd-total 0)
        (ours-total 0)
        (times nil)
        (result (make-array '(3 3) :initial-element 0)))
    (dolist (p files)
      (format t "~&~%##### Testing ~a" p)
      (plet (((time-fd fd) (num-operator-fd p))
             ((time-ours ours goal-achieved) (num-operator-ours p)))
        (is-true goal-achieved "On ~a, goal axiom was not achieved" p)
        (incf fd-total time-fd)
        (incf ours-total time-ours)
        (push (list p time-ours (not (not goal-achieved)) time-fd) times)
        (match* (fd ours)
          (((number) (number))
           ;; Additional pruning with negative precondition
           ;; (is (<= fd ours) "On problem ~a, (<= fd ours) evaluated to (<= ~a ~a) = ~a" p fd ours (<= fd ours))
           (format t "~&Instantiated Operator, FD: ~a vs OURS: ~a" fd ours)
           (format t "~&Runtime, FD: ~a vs OURS: ~a" time-fd time-ours)
           (incf (aref result
                       (cond
                         ((< (abs (- time-fd time-ours)) 1) 2)
                         ((< time-fd time-ours) 0)
                         (t 1))
                       (cond
                         ((= fd ours) 0)
                         ((< fd ours) 1)
                         ((> fd ours) 2))))
           (format t "~&Runtime total: FD: ~a OURS: ~a" fd-total ours-total)
           (print-result-table result '(fd-wins ours-wins diff<1) '(same-op more-op less-op)))
          (((number) _)
           (fail "On problem ~a, fd returned ~a ops in ~a sec, ours failed" p fd time-fd))
          ((_ (number))
           (pass "On problem ~a, ours returned ~a ops in ~a sec, fd failed" p ours time-ours)))))
    (format t "~&Runtime statistics:~%~{~{~50a ~10a ~10a ~10a~}~%~}"
            (list* '(problem ours goal? fd)
                   (sort times #'> :key #'second)))))

(test num-operator-small
  (test-num-operators *small-files*))

(def-suite :alien.more)
(in-suite :alien.more)

(test num-operator-middle
  (test-num-operators *middle-files*))

(test num-operator-large
  (test-num-operators *large-files*))

(test num-operator-problematic
  (let ((*time-parser* t))
    (test-num-operators
     '(;; very large grounded domains
       "axiom-domains/psr-middle-alien-derived/p50.pddl" ; 106sec @ 94 facts, 7451 axioms, 5214 ops
       "axiom-domains/opttel-alien-derived/p19.pddl"  ; 10sec @ 2320 facts, 1601 axioms, 2860 ops
       "ipc2011-opt/tidybot-opt11/p20.pddl"            ; 55sec @ 386 facts, 1 axioms, 203873 ops (vs FD: 30488 ops)
       ))))

(test num-operator-too-many-ops
  ;; fast downward too many ops, or is mine wrong?
  ;; maybe fd is not considering (not (= x y)) ? not really...
  (test-num-operators '("ipc2014-agl/hiking-agl14/p20.pddl")))
