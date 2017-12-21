
(in-package :strips)
(named-readtables:in-readtable :fare-quasiquote)

(defun ground (info)
  (with-parsed-information info
    (let ((result (%ground)))
      (destructuring-bind (&key facts ops fluents)
          (let ((*package* (find-package :pddl)))
            (read-from-string result))
        (list* :facts facts
               :ops ops
               :fluents fluents
               info)))))

(defun all-terms ()
  `((:- (all-terms (/ ?head ?arity) ?list)
        (functor ?term ?head ?arity)
        (findall ?term ?term ?list))
    (all-terms (list) (list))
    (:- (all-terms (list* ?first ?rest) ?list)
        (all-terms ?first ?list2)
        (all-terms ?rest ?list3)
        (append ?list2 ?list3 ?list))))

(defun relaxed-reachability ()
  (let (arities
        (op-arities (remove-duplicates (mapcar (lambda (a) (length (getf a :parameters))) *actions*))))
    (let ((results
           (sort-clauses
            (append
             (iter (for proposition in *init*)
                   (pushnew (length proposition) arities)
                   (collect `(reachable-fact ,@proposition)))
             (iter (for a in *actions*)
                   (ematch a
                     ((plist :action name
                             :parameters params
                             :precondition `(and ,@precond)
                             :effect effects)
                      (collecting
                       `(:- (reachable-op ,name ,@params)
                            ,@(iter (for pre in precond)
                                    (collect `(reachable-fact ,@pre)))))
                      (dolist (e effects)
                        (match e
                          (`(forall ,_ (when ,_ (not ,_)))       nil)
                          (`(forall ,_ (when ,_ (increase ,@_))) nil)
                          (`(forall ,_ (when (and ,@conditions) ,atom))
                            (pushnew (length atom) arities)
                            (collecting
                             `(:- (reachable-fact ,@atom)
                                  ,@(iter (for c in conditions)
                                          (collect `(reachable-fact ,@c)))
                                  (reachable-op ,name ,@params)))))))))
             (iter (for a in *axioms*)
                   (ematch a
                     ((list :derived predicate `(and ,@body))
                      (pushnew (length predicate) arities)
                      (collecting
                       `(:- (reachable-fact ,@predicate)
                            ,@(iter (for c in body)
                                    (collecting
                                     `(reachable-fact ,@c))))))))))))
      (append
       (iter (for len in arities)
             (collecting
              `(:- (table (/ reachable-fact ,len)))))
       (iter (for len in op-arities)
             (collecting
              `(:- (table (/ reachable-op ,(1+ len))))))
       results
       ;; output facts/ops
       `((:- relaxed-reachability-fact
             ,@(iter (for len in arities)
                     (collecting
                      `(and (findall ?term (functor ?term reachable-fact ,len) ?l)
                            (print-sexp ?l)))))
         (:- relaxed-reachability-op
             ,@(iter (for len in op-arities)
                     (collecting
                      `(and (findall ?term (functor ?term reachable-op ,(1+ len)) ?l)
                            (print-sexp ?l)))))
         (:- relaxed-reachability
             (write ":facts\\n")
             relaxed-reachability-fact
             (write ":ops\\n")
             relaxed-reachability-op))))))

(defun fluent-facts ()
  (let (arities)
    (let ((results
           (iter (for a in *actions*)
                 (ematch a
                   ((plist :action name
                           :parameters params
                           :effect effects)
                    (dolist (e effects)
                      (match e
                        (`(forall ,_ (when ,_ (increase ,@_)))
                          nil)
                        (`(forall ,_ (when (and ,@conditions) (not ,atom)))
                          (pushnew (length atom) arities)
                          (collecting
                           `(:- (fluent-fact ,@atom)
                                ,@(iter (for c in conditions)
                                        (collect `(reachable-fact ,@c)))
                                (reachable-op ,name ,@params))))
                        (`(forall ,_ (when (and ,@conditions) ,atom))
                          (pushnew (length atom) arities)
                          (collecting
                           `(:- (fluent-fact ,@atom)
                                ,@(iter (for c in conditions)
                                        (collect `(reachable-fact ,@c)))
                                (reachable-op ,name ,@params)))))))))))
      (append (iter (for len in arities)
                    (for args = (make-gensym-list len "?"))
                    (appending
                     `((:- (table (/ fluent-fact ,len)))
                       (:- (table (/ static-fact ,len)))
                       (:- (static-fact ,@args)
                           (reachable-fact ,@args)
                           (not (fluent-fact ,@args))))))
              results
              `((:- fluent-facts-aux
                    ,@(iter (for len in arities)
                            (collecting
                             `(and (findall ?term (functor ?term fluent-fact ,len) ?l)
                                   (print-sexp ?l)))))
                (:- fluent-facts
                    (write ":fluents (\\n")
                    (or fluent-facts-aux true)
                    (write ")\\n")))))))

(defun %ground ()
  (run-prolog
   (append (relaxed-reachability)
           (fluent-facts)
           (print-sexp)
           (all-terms)
           `((:- main
                 (write "(") 
                 relaxed-reachability
                 fluent-facts
                 (write ")")
                 halt)))
   :bprolog :args '("-g" "main") :debug t))

(with-parsed-information (parse (%rel "ipc2011-opt/transport-opt11/p01.pddl"))
  (print (%ground)))

(defun subst-by-alist (alist tree)
  (setf tree (copy-tree tree))
  (iter (for (new . old) in alist)
        (setf tree (nsubst new old tree)))
  tree)

(defun instantiate-action-body (info)
  (with-parsed-information info
    (match info
      ((plist :facts facts :ops ops)
       (list*
        :ground-actions
        (iter (for (name . args) in ops)
              (for a = (find name *actions* :key #'second))
              (assert a)
              (ematch a
                ((plist :parameters params
                        :precondition precond
                        :effect effects)
                 (let ((alist (mapcar #'cons args params)))
                   (collecting
                    (list :action name
                          :parameters args
                          :precondition (subst-by-alist alist precond)
                          :effect (subst-by-alist alist effects)))))))
        :ground-axioms
        (iter (for (name . args) in facts)
              (for a = (find name *axioms* :key #'caadr))
              (ematch a
                (nil nil)
                ((list :derived (list* _ params) condition)
                 (let ((alist (mapcar #'cons args params)))
                   (collecting
                    (list :derived (list* name args) (subst-by-alist alist condition)))))))
        info)))))

;; (print (-> "ipc2011-opt/transport-opt11/p01.pddl"
;;          (%rel)
;;          (parse)
;;          (ground)
;;          (instantiate-action-body)))

;; (defun axiom-layers ()
;;   (let ((arities (remove-duplicates (mapcar (compose #'length #'second) *axioms*))))
;;     (append
;;      (iter (for len in arities)
;;            (collecting
;;             `(:- (table (/ axiom-layer ,(1+ len))))))
;;      (iter (for len in arities)
;;            (for args = (make-gensym-list len "?"))
;;            (collecting
;;             `(:- (axiom-layer 0 ,@args)
;;                  (fluent-fact ,@args))))
;;      (iter (for a in *axioms*)
;;            (ematch a
;;              ((list :derived predicate `(and ,@body))
;;               (collecting
;;                `(:- (axiom-layer ?n ,@predicate)
;;                     (>= ?n 1)
;;                     (not (axiom-layer (- ?n 1) ,@predicate))
;;                     ,@(iter (for c in body)
;;                             (for i from 0)
;;                             (for ?n = (symbolicate '?n (princ-to-string i)))
;;                             (collecting
;;                              `(axiom-layer ,?n ,@c))
;;                             (collecting
;;                              `(< ,?n ?n))))))))
;;      (iter (for len in arities)
;;            (for args = (make-gensym-list len "?"))
;;            (collecting
;;             `(:- (axiom-layers-aux ?n)
;;                  (findall (list ,@args) (axiom-layer ?n ,@args) ?l)
;;                  (-> (!= ?l (list))
;;                    (and (print-list ?l)
;;                         )))
;;      `((:- fluent-facts-aux
;;                     ,@(iter (for len in arities)
;;                             (collecting
;;                              `(and (findall ?term (functor ?term fluent-fact ,len) ?l)
;;                                    (print-sexp ?l)))))
;;        (:- axiom-layers
;;            (write ":axiom-layer (")
;;            axiom-layers-aux
;;            (write ")\\n"))))))


;; (write "(")
;; ,@(iter (for e in (list* '?n args))
;;         (unless (first-iteration-p)
;;           (collect `(write " ")))
;;         (collect `(write ,e)))
;; (write ")\\n")
