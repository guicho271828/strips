;; instantiate EFFECT and OP instance as well as some lookup table for the facts.
;; EFFECT and OP are primitive representation of operators and its effects.

(in-package :alien)
(named-readtables:in-readtable :fare-quasiquote)

(defvar *fact-index*)
(defvar *fact-size*)
(defvar *fact-trie*)
(defvar *state-size*)
(defvar *op-sexp-index*)
(defvar *instantiated-ops*)
(defvar *op-size*)
(defvar *instantiated-axiom-layers*)
(defvar *instantiated-init*)
(defvar *instantiated-goal*)

;; conditions and effects are represented by a fixnum index to a fact.
;; however, the fixnum can be negative, in which case it represent a negative condition or a delete effect.

(eval-when (:compile-toplevel :load-toplevel :execute)
  (flet ((con () (make-a-array 16 :element-type 'fixnum :initial-element most-positive-fixnum)))
    (defstruct effect
      (con (con) :type (array fixnum))
      (eff most-positive-fixnum :type fixnum))
    
    (defstruct op
      (pre (con) :type (array fixnum))
      (eff (make-a-array 16
                         :element-type 'effect
                         :initial-element +uninitialized-effect+)
           :type (array effect)))))

(defvar +uninitialized-effect+ (make-effect))

(deftype axiom-layer ()
  '(array effect))

(declaim (alien.lib:index *fact-index*))
(declaim (hash-table *op-sexp-index*))
(declaim (fixnum *fact-size* *state-size* *op-size*))
(declaim (cons *fact-trie*))
(declaim ((array op) *instantiated-ops*))
(declaim ((array axiom-layer) *instantiated-axiom-layers*))
(declaim ((array fixnum) *instantiated-init*))
(declaim (fixnum *instantiated-goal*))

(defun instantiate (info)
  (with-parsed-information4 info
    (multiple-value-bind (fact-index fact-size fact-trie) (index-facts)
      (multiple-value-bind (op-sexp-index instantiated-ops) (instantiate-ops fact-index fact-trie)
        (list* :fact-index fact-index
               :fact-size fact-size
               :fact-trie fact-trie
               :state-size (alien.lib:index-size fact-index)
               :op-sexp-index op-sexp-index
               :instantiated-ops instantiated-ops
               :successor-generator (generate-sg instantiated-ops)
               :instantiated-axiom-layers (instantiate-axiom-layers fact-index fact-trie)
               :instantiated-init (instantiate-init fact-index fact-size)
               :instantiated-goal (instantiate-goal fact-index)
               info)))))

(defun index-facts ()
  (let ((i (alien.lib:make-index :test 'equal))
        (trie (alien.lib:make-trie))
        (fact-size 0))
    ;; indexing init
    (dolist (f *init*)
      ;; index contains only fluent facts; however, trie contains all facts,
      ;; including static facts, because it is used for looking up the
      ;; candidates for free variables.  static facts are never added to the
      ;; preconditions nor effect conditions.
      (unless (static-p f)
        (alien.lib:index-insert i f))
      (alien.lib:trie-insert trie f))
    ;; indexing fluents
    (dolist (f *facts*)
      (alien.lib:index-insert i f)
      (alien.lib:trie-insert trie f))
    (setf fact-size (alien.lib:index-size i))
    ;; indexing axioms
    (dolist (f *ground-axioms*)
      (alien.lib:index-insert i f)
      (alien.lib:trie-insert trie f))
    (values i fact-size trie)))

(defun instantiate-ops (index trie)
  (log:info "Instantiating operator objects")
  (let ((op-sexp-index (make-hash-table :test 'equal)) ; HACK! abusing a single hash table
        (op-index      (alien.lib:make-index :test 'equalp)))
    (log:info "Making an operator index")
    (dolist (op-sexp *ops*)
      (catch 'contradiction
        ;; op with conflicting precond should be pruned
        (let ((op (instantiate-op op-sexp index trie)))
          (multiple-value-bind (id inserted) (alien.lib:index-insert op-index op)
            ;; op-sexp is a list of action representation (e.g. (pickup
            ;; block)) and its reachable effects.  However, we only store the
            ;; action representation into the op-sexp-index for the later
            ;; cross-retrieval of the action <-> op-id mapping.
            
            ;; using a single hash table as a bidirectional map.
            ;; id -> sexp is a multi mapping that stores a list.
            (ensure-gethash id op-sexp-index)
            (push (first op-sexp) (gethash id op-sexp-index))
            ;; sexp -> id is a single mapping.
            (setf (gethash (first op-sexp) op-sexp-index) id)))))

    (log:info "Removed duplicated operators: ~a -> ~a" (length *ops*) (alien.lib:index-size op-index))

    (values op-sexp-index
            (make-array (alien.lib:index-size op-index)
                        :element-type 'op
                        :initial-contents (alien.lib:index-array op-index)))))

(defun original-action-name (name)
  (getf (find name *actions* :key #'second) :original-action))

(defun decode-op (op)
  (ematch op
    ((integer)
     ;; Due to the duplicated action pruning, there are several
     ;; candidates. However, it does not matter which action is selected because
     ;; they all have the same precondition / effects.
     (match (first (gethash op *op-sexp-index*))
       ((list* name args)
        (list* (original-action-name name) args))))
    ((op)
     (decode-op (position op *instantiated-ops*)))))

(defun encode-op (op)
  "map the action signature (as used in the original pddl) to the internal operator id"
  (ematch op
    ((list* name args)
     ;; since a disjunctinve condition duplicates the action for each disjunctive branch,
     ;; we should search which branch this action corresponds to.
     (iter (for candidate-definition in (remove-if-not (curry #'equal name) *actions* :key #'fourth))
           (for internal-name = (getf candidate-definition :action))
           ;; by specifying the arguments,
           (for id = (gethash (list* internal-name args) *op-sexp-index*))
           (when id
             (collect id))))))

(defun opposite-effect-p (a b)
  (match* (a b)
    (((effect :con con1 :eff eff1)
      (effect :con (equalp con1) :eff (= (lognot eff1))))
     t)))

(declaim (inline logabs))
(defun logabs (number)
  (if (minusp number)
      (lognot number)
      number))

(defun instantiate-op (op index trie)
  (ematch op
    (`((,name ,@args) ,reachable-effects)
      (ematch (find name *actions* :key #'second)
        ((plist :parameters params
                :precondition `(and ,@precond)
                :effect `(and ,@effects))
         (let* ((gpre (copy-tree precond))
                (geff (copy-tree effects))
                (op (make-op)))
           (iter (for a in args)
                 (for p in params)
                 (setf gpre (nsubst a p gpre))
                 (setf geff (nsubst a p geff)))

           (match op
             ((op pre :eff (place eff))
              (let ((gpre (remove-duplicates gpre :test 'equal)))
                (dolist (c gpre)
                  (if (positive c)
                      (unless (static-p c)
                        (linear-extend pre (alien.lib:index-id index c) most-positive-fixnum))
                      (if (member (second c) gpre :test 'equal)
                          ;; Note: the precondition contains a contradiction, i.e. X and (not X).
                          ;; This cannot be checked during grounding because
                          ;; it ignores all negative preconditions.
                          (throw 'contradiction nil)
                          (let ((i (alien.lib:index-id index (second c))))
                            (when i ; otherwise unreachable
                              (linear-extend pre (lognot i) most-positive-fixnum)))))))
              (sort pre #'<)
              (iter (for e in geff)
                    (for i from 0)
                    (unless (member i reachable-effects)
                      (log:trace "op ~a:~%unreachable effect condition: ~a" `(,name ,@args) e))
                    (instantiate-effect e eff index trie))
              (setf eff (sort eff #'< :key #'effect-eff))
              (setf eff (delete-duplicates eff :test 'equalp)) ; there are no duplicates below here.
              ;; postprocessing: when the effect-conditions are equivalent for the
              ;; positive and negative effect of the same literal, the effect should
              ;; be removed.
              (setf eff
                    (iter (for e1 in-vector eff with-index i)
                          (if (iter (for e2 in-vector eff with-index j)
                                    (thereis (opposite-effect-p e1 e2)))
                              (log:trace "op ~a:~%cancelling effects: ~a" `(,name ,@args)
                                         (alien.lib:index-ref index (logabs (effect-eff e1))))
                              (collect e1 result-type vector))))
              #+(or)
              (iter (with blacklist = nil)
                    (for e1 in-vector eff with-index i)
                    (generate j from 0)
                    (when (member i blacklist)
                      (next-iteration))
                    (iter (for e2 in-vector eff with-index k from (1+ i))
                          (with noop-found = nil)
                          (when (opposite-effect-p e1 e2)
                            (pushnew i blacklist)
                            (pushnew k blacklist)
                            (log:trace "op ~a:~%cancelling effects: ~a" `(,name ,@args)
                                       (alien.lib:index-ref index (logabs (effect-eff e1))))
                            (setf noop-found t))
                          (finally
                           (unless noop-found
                             (next j)
                             (setf (aref eff j) e1))))
                    (finally
                     (setf (fill-pointer eff) (1+ j))))))
           op))))))

(defun instantiate-effect (e effects index trie)
  (match e
    (`(forall ,_ (when (and ,@conditions) ,atom))
      (instantiate-effect-aux conditions nil atom effects index trie))))

(defun instantiate-effect-aux (conditions ground-conditions atom effects index trie)
  "recurse into each possibility of universally quantified condition"
  (if conditions
      (ematch conditions
        ((list* first rest)
         (let* ((negative (negative first))
                (c (if negative (second first) first)))
           (alien.lib:query-trie
            (lambda (gc)
              (let ((rest (copy-tree rest))
                    (atom (copy-tree atom)))
                (iter (for a in (rest gc))
                      (for p in (rest c))
                      (when (variablep p)
                        (setf rest (nsubst a p rest))
                        (setf atom (nsubst a p atom))))
                (instantiate-effect-aux rest (cons (if negative `(not ,gc) gc) ground-conditions)
                                        atom effects index trie)))
            trie c))))
      (instantiate-effect-aux2 ground-conditions atom effects index trie)))

(defun instantiate-effect-aux2 (ground-conditions atom effects index trie)
  (let ((e (make-effect)))
    (ematch e
      ((effect con :eff (place eff))
       
       (let ((gcon (remove-duplicates ground-conditions :test 'equal)))
         (dolist (c gcon)
           (if (positive c)
               (unless (static-p c)
                 (linear-extend con (alien.lib:index-id index c) most-positive-fixnum))
               (if (member (second c) gcon :test 'equal)
                   ;; Note: this precondition contains a contradiction, i.e. X and (not X).
                   ;; This cannot be checked during grounding because
                   ;; it ignores all negative preconditions.
                   (return-from instantiate-effect-aux2)
                   (let ((i (alien.lib:index-id index (second c))))
                     (when i ; otherwise unreachable
                       (linear-extend con (lognot i) most-positive-fixnum)))))))
       
       (sort con #'<)
       (when (positive atom)
         (assert (notany #'variablep atom))
         (setf eff (alien.lib:index-id index atom)))
       (when (negative atom)            ; e.g. (NOT (PDDL::Z93))
         (assert (notany #'variablep (second atom)))
         (let ((i (alien.lib:index-id index (second atom))))
           (if i
               (setf eff (lognot i))
               ;; The ATOM = (PDDL::Z93) is unreachable.
               ;; It is important to skip the linear-extend operation three lines below
               ;; because the EFF slot of the new effect E is uninitialized --
               ;; this makes the later successor generation phase confused!
               ;; So it should return from the function immediately.
               (return-from instantiate-effect-aux2))))
       ;; note: ignoring action cost at the moment
       (assert (/= most-positive-fixnum eff))))
    (linear-extend effects e)))

(defun instantiate-axiom-layers (index trie)
  (let ((all-results (make-a-array (length *axiom-layers*)
                                   :element-type 'axiom-layer
                                   :initial-element (make-a-array 0
                                                                  :element-type 'effect
                                                                  :initial-element +uninitialized-effect+))))
    (iter (for layer in-sequence *axiom-layers*)
          (when layer ; skip the empty layers
            (let ((results (make-a-array (length layer)
                                         :element-type 'effect
                                         :initial-element +uninitialized-effect+)))
              (dolist (axiom layer)
                (instantiate-axiom axiom index trie results))
              (linear-extend all-results results))))
    all-results))

(defun instantiate-axiom (axiom index trie results)
  (ematch axiom
    ((list* name args)
     (iter (for lifted in (remove-if-not (lambda-match ((list :derived `(,(eq name) ,@_) _) t)) *axioms*))
           (ematch lifted
             ((list :derived `(,(eq name) ,@params) `(and ,@body))
              (let ((gbody (copy-tree body)))
                (iter (for a in args)
                      (for p in params)
                      (setf gbody (nsubst a p gbody)))
                ;; need to instantiate each free variable
                (instantiate-effect-aux gbody nil axiom results index trie))))))))

(defun instantiate-init (fact-index fact-size)
  (let ((results (make-a-array fact-size :element-type 'fixnum)))
    (iter (for p in *init*)
          (unless (static-p p)
            (linear-extend results (alien.lib:index-id fact-index p))))
    results))

(defun instantiate-goal (fact-index)
  (alien.lib:index-id fact-index *goal*))

