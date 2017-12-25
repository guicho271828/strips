#|
  This file is a part of strips project.
  Copyright (c) 2017 Masataro Asai (guicho2.71828@gmail.com)
|#

(in-package :cl-user)
(defpackage :strips.test
  (:use :cl
        :strips :pddl
        :fiveam
        :iterate :alexandria :trivia
        :lparallel))
(in-package :strips.test)

(named-readtables:in-readtable :fare-quasiquote)


(def-suite :strips)
(in-suite :strips)

;; run test with (run! test-name) 

(defvar *problems*
  (iter (for p in (directory (asdf:system-relative-pathname :strips #p"*/*/*.pddl")))
        (match p
          ((pathname :name (guard name (not (search "domain" name :from-end t))))
           (collecting p result-type vector)))))

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
      (parse (asdf:system-relative-pathname :strips "axiom-domains/opttel-adl-derived/p01.pddl"))))

  (for-all ((p (lambda () (random-elt *problems*))))
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
  (set-equal a b :test 'equal))

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
       (strips::parse-typed-def '(hand level beverage dispenser container - object
                                  ingredient cocktail - beverage
                                  shot shaker - container))))
  (is (set= '(object location truck)
            (let ((*types* '((truck . location)
                             (location . truck)
                             (truck . object))))
              (strips::flatten-type 'truck))))
  
  (signals error
    (let (*types*)
      (strips::grovel-types '((:types truck - location location - truck)))))
  
  (is (set= '((location ?truck) (truck ?truck))
            (let ((*types* '((truck . location)
                             (location . object))))
              (strips::flatten-types/argument '?truck 'truck))))
  
  (is (set= '((IN ?TRUCK ?THING) (LOCATION ?TRUCK) (TRUCK ?TRUCK))
            (let ((*types* '((truck . location)
                             (location . object)))
                  (*predicate-types* '((truck location)
                                       (location object)
                                       (in truck object))))
              (strips::flatten-types/predicate `(in ?truck ?thing)))))

  (signals error
    (let ((*types* '((truck . location)
                     (location . object)))
          (*predicate-types* '()))
      (strips::flatten-types/predicate `(in ?truck ?thing))))

  (let ((*types* '((truck . location)
                   (location . object)))
        (*predicate-types* '((truck location)
                             (location object)
                             (in truck object))))
    (multiple-value-bind (w/o-type predicates parsed)
        (strips::flatten-typed-def `(?truck - truck ?thing - object))
      (is (set= '(?truck ?thing) w/o-type))
      (is (set= '((location ?truck) (truck ?truck)) predicates))
      (is (set= '((?truck . truck) (?thing . object)) parsed))))

  (let ((*types* '((agent . object)
                   (unit . object)))
        (*predicate-types* '((clean agent object))))
    (is (equal
         '(forall (?u) (imply (and (unit ?u)) (and (and (clean ?v ?u) (agent ?v)))))
         (strips::flatten-types/condition `(forall (?u - unit) (and (clean ?v ?u))))))
    (is (equal
         '(not (and (clean ?v ?u) (agent ?v)))
         (strips::flatten-types/condition `(not (clean ?v ?u))))))

  (let ((*types* '((a . object) (b . object)))
        *predicate-types* *predicates*)
    (strips::grovel-predicates `((:predicates (pred ?x - a ?y - b))))
    (is (set= '((pred ?x ?y)) *predicates*))
    (is (set= '((pred a b)) *predicate-types*))))

(defun collect-results (cps)
  (let (acc)
    (funcall cps
             (lambda (result)
               (push result acc)))
    acc))

(defun nnf-dnf (condition)
  (collect-results (strips::&nnf-dnf condition)))

(defun nnf-dnf/effect (condition)
  (collect-results (strips::&nnf-dnf/effect condition)))

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
             (strips::simplify-effect `(clear))))

  (ematch (strips::simplify-effect `(when (and) (and (a) (b))))
    (`(and ,@rest)
      (is (set= `((forall nil (when (and) (b)))
                  (forall nil (when (and) (a))))
                rest))))

  (ematch (strips::simplify-effect `(when (and) (forall () (and (a) (b)))))
    (`(and ,@rest)
      (is (set= `((forall nil (when (and) (b)))
                  (forall nil (when (and) (a))))
                rest)))))

(test move-exists/condition
  
  (ematch (strips::move-exists/condition `(exists (a b c) (three a b c)))
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
    (print (strips::move-exists/condition `(and
                                            (p1)
                                            (exists (a) (p2 a))
                                            (exists (a) (p3 a)))))
    ;; (EXISTS (#:A54873 #:A54874) (AND (P3 #:A54874) (P2 #:A54873) (P1)))
    
    (print (strips::move-exists/condition `(and
                                            (p1)
                                            (exists (a)
                                                    (and (and (p3 a)
                                                              (p4 a))
                                                         (exists (b) (p2 a b)))))))
    ;; (EXISTS (#:A54875 #:B54876) (AND (P2 #:A54875 #:B54876) (P4 #:A54875) (P3 #:A54875) (P1)))
    
    (print (strips::move-exists/effect `(and (p1)
                                             (and (p1) (p1))
                                             (when (exists (a) (clear a))
                                               (and (p2) (and (p2) (and (p2) (p2))))))))
    ;; (AND (FORALL (#:A54877) (WHEN (AND (CLEAR #:A54877)) (AND (P2) (P2) (P2) (P2)))) (P1) (P1) (P1)) 
    ))

(test join-ordering
  (multiple-value-match
      (strips::all-relaxed-reachable2
       (shuffle
        (copy-list
         '((in-city ?l1 ?c)
           (in-city ?l2 ?c)
           (at ?t ?l1)))))
    ((_ `(:- ,_ ,@rest))
     (is (or (set= rest '((REACHABLE-FACT (AT ?T ?L1)) (REACHABLE-FACT (IN-CITY ?L1 ?C))))
             (set= rest '((REACHABLE-FACT (IN-CITY ?L2 ?C)) (REACHABLE-FACT (IN-CITY ?L1 ?C))))))))
             
  
  (multiple-value-bind (decomposed temporary)
      (strips::all-relaxed-reachable2
       (shuffle
        (copy-list
         '((LOCATABLE ?V) (VEHICLE ?V) (LOCATION ?L1) (LOCATION ?L2) (AT ?V ?L1) (ROAD ?L1 ?L2)))))
    (is (= 2 (length decomposed)))
    (is (< 3 (length temporary) 7)))

  (is-true (strips::tmp-p '(tmp111)))
  (is-false (strips::tmp-p '(a))))

(defun call-test-ground (info fn)
  (with-parsed-information info
    (let ((result (strips::%ground)))
      ;; (print result)
      (apply fn (read-from-string result)))))

(defmacro with-test-ground (info &body body)
  `(call-test-ground ,info
                     (lambda (&key facts ops fluents axioms)
                       (declare (ignorable facts ops fluents axioms))
                       ,@body)))

(defun mem (elem list)
  (member elem list :test 'equal))

(test relaxed-reachability
  (with-test-ground (strips::parse1 '(define (domain d)
                              (:requirements :strips :typing)
                              (:predicates (d ?x) (p ?x) (goal))
                              (:action a :parameters (?x) :precondition (and) :effect (p ?x))
                              (:derived (d ?x) (p ?x)))
                            '(define (problem p)
                              (:domain d)
                              (:objects o1 o2)
                              (:init )
                              (:goal (goal))))
    (is-true (mem '(d o1) facts))
    (is-true (mem '(p o1) facts))
    (is-true (mem '(d o2) facts))
    (is-true (mem '(p o2) facts))
    (is-true (mem '(a o1) ops))
    (is-true (mem '(a o2) ops)))

  ;; parameter ?x is not referenced in the axiom body
  (with-test-ground (strips::parse1 '(define (domain d)
                              (:requirements :strips :typing)
                              (:predicates (d ?x) (p) (goal))
                              (:action a :parameters (?x) :precondition (and) :effect (p))
                              (:derived (d ?x) (p)))
                            '(define (problem p)
                              (:domain d)
                              (:objects o1 o2)
                              (:init )
                              (:goal (goal))))
    (is-true (mem '(p) facts))
    (is-true (mem '(d o1) facts))
    (is-true (mem '(d o2) facts))
    (is-true (mem '(a o1) ops))
    (is-true (mem '(a o2) ops)))

  ;; parameter ?x is a free variable in the axiom body
  (with-test-ground (strips::parse1 '(define (domain d)
                              (:requirements :strips :typing)
                              (:predicates (d ?x) (p ?x) (goal))
                              (:action a :parameters (?x) :precondition (and) :effect (p ?x))
                              (:derived (d) (p ?x)))
                            '(define (problem p)
                              (:domain d)
                              (:objects o1 o2)
                              (:init )
                              (:goal (goal))))
    (is-true (mem '(p o1) facts))
    (is-true (mem '(p o2) facts))
    (is-true (mem '(d) facts))
    (is-true (= 1 (count '(d) facts :test 'equal)))
    (is-true (mem '(a o1) ops))
    (is-true (mem '(a o2) ops)))

  (with-test-ground (strips::parse1 '(define (domain d)
                              (:requirements :strips :typing)
                              (:predicates (d ?x) (p ?x) (p2 ?x) (goal))
                              (:action a :parameters (?x) :precondition (and) :effect (p ?x))
                              (:derived (d) (p2 ?x)))
                            '(define (problem p)
                              (:domain d)
                              (:objects o1 o2)
                              (:init )
                              (:goal (goal))))
    (is-true (mem '(p o1) facts))
    (is-true (mem '(p o2) facts))
    (is-true (not (mem '(p2 o1) facts)))
    (is-true (not (mem '(p2 o2) facts)))
    (is-true (not (mem '(d) facts)))
    (is-true (mem '(a o1) ops))
    (is-true (mem '(a o2) ops)))

  (with-test-ground (parse (%rel "axiom-domains/opttel-adl-derived/p01.pddl"))
    (assert (= 286 (length ops))))

  (with-test-ground (parse (%rel "ipc2011-opt/transport-opt11/p01.pddl"))
    (print (length facts))
    (print (length ops))
    (print (length axioms))
    (assert (= 616 (length ops)))))

(test num-operator
  (for-all ((p (lambda () (random-elt *problems*))))
    (let ((d (strips::find-domain p)))
      (is (= (time
              (read-from-string
               (uiop:run-program `("sh" "-c"
                                        ,(format nil "~a ~a ~a | grep 'Translator operators' | cut -d' ' -f 3"
                                                 (strips::%rel "downward/src/translate/translate.py") d p))
                                 :output :string)))
             (time
              (with-test-ground (parse p d)
                (length ops))))))))

#+(or)
(test num-operator
  (setf *kernel* (make-kernel 2)) ; :bindings
  (for-all ((p (lambda () (random-elt *problems*))))
    (let ((d (strips::find-domain p)))
      (plet ((fd (time
                  (read-from-string
                   (uiop:run-program `("sh" "-c"
                                            ,(format nil "~a ~a ~a | grep 'Translator operators' | cut -d' ' -f 3"
                                                     (strips::%rel "downward/src/translate/translate.py") d p))
                                     :output :string))))
             (ours (time
                    (with-test-ground (parse p d)
                      (length ops)))))
        (is (= fd ours))))))

(defparameter *large-files*
  '("axiom-domains/opttel-adl-derived/p48.pddl"
    "axiom-domains/opttel-strips-derived/p19.pddl"
    "axiom-domains/philosophers-adl-derived/p48.pddl"
    "axiom-domains/philosophers-strips-derived/p48.pddl"
    "axiom-domains/psr-middle-adl-derived/p50.pddl"
    "axiom-domains/psr-middle-strips-derived/p50.pddl"
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

(defparameter *timeout* 60)

(test can-load-large-file
  (iter (for file in *large-files*)
        (handler-case
            (bt:with-timeout (*timeout*)
              (strips::ground (strips::parse (strips::%rel file)))
              (pass))
          (error (c)
            (fail "Failure while parsing ~a, Reason:~% ~a" file c))
          (bt:timeout ()
            (fail "Grounding/parsing ~a did not finish in ~a sec." file *timeout*)))))


