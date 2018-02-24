;;;; Autogenerated ASD file for system "STRIPS"
;;;; In order to regenerate it, run update-asdf
;;;; from shell (see https://github.com/phoe-krk/asd-generator)
;;;; For those who do not have update-asdf,
;;;; run `ros install asd-generator` (if you have roswell installed)
;;;; There are also an interface available from lisp:
;;;; (asd-generator:regen &key im-sure)
(defsystem strips
 :version "0.1"
 :author "Masataro Asai"
 :mailto "guicho2.71828@gmail.com"
 :license "LLGPL"
 :depends-on (:iterate
              :alexandria
              :trivia
              :trivia.quasiquote
              :arrow-macros
              :cl-prolog2.bprolog
              :bordeaux-threads
              :lisp-namespace
              :introspect-environment
              :type-r
              :static-vectors
              :log4cl
              :cffi)
 :serial t
 :components ((:module "lib"
               :components ((:file "package")
                            (:file "equivalence")
                            (:file "indexed-entries")
                            (:file "packed-struct")
                            (:file "struct-of-array")
                            (:file "trie")))
              (:module "preprocess"
               :components ((:file "package")
                            (:file "util")
                            (:file "specials")
                            (:file "2-translate")
                            (:file "4-easy-invariant")
                            (:file "5-grounding-prolog-3")
                            (:file "6-invariant")
                            (:file "7-instantiate")
                            (:file "8-successor-generator")))
              (:module "search"
               :components ((:file "util")
                            (:file "specials")
                            (:file "blind")
                            (:file "bucket-open-list")
                            (:file "delete-relaxation")
                            (:file "run")
                            (:file "timeout")
                            (:module "heuristics"
                             :components ())
                            (:module "searchers"
                             :components ())
                            (:module "open-list"
                             :components ())))
              (:module "validate"
               :components ((:file "validate"))))
 :description "A STRIPS planner"
 :in-order-to ((test-op (test-op :strips.test))))
