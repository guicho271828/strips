;;;; Autogenerated ASD file for system "STRIPS.INSTANCE-DEPENDENT"
;;;; In order to regenerate it, run update-asdf
;;;; from shell (see https://github.com/phoe-krk/asd-generator)
;;;; For those who do not have update-asdf,
;;;; run `ros install asd-generator` (if you have roswell installed)
;;;; There are also an interface available from lisp:
;;;; (asd-generator:regen &key im-sure)
(defsystem strips.instance-dependent
 :version "0.1"
 :author "Masataro Asai"
 :mailto "guicho2.71828@gmail.com"
 :license "LLGPL"
 :depends-on (:strips)
 :serial t
 :components ((:module "search-instance-dependent"
               :components ((:file "close-list")
                            (:file "search-common")
                            (:file "eager")
                            (:file "ff")
                            (:file "goal-count")
                            (:module "heuristics"
                             :components ())
                            (:module "searchers"
                             :components ())
                            (:module "open-list"
                             :components ()))))
 :description "Instance-dependent component of STRIPS")
