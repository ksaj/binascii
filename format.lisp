;;;; format.lisp -- a central repository for encoding formats and accessors

(cl:in-package :binascii)

(defvar *format-descriptors* (make-hash-table))

(defvar *format-state-constructors* (make-hash-table))

(defun unknown-format-error (format)
  (error "Unknown format ~A" format))

(defun find-descriptor-for-format-or-lose (format)
  (or (gethash format *format-descriptors*)
      (unknown-format-error format)))

(defun find-encode-state-constructor-or-lose (format)
  (or (car (gethash format *format-state-constructors*))
      (unknown-format-error format)))

(defun find-decode-state-constructor-or-lose (format)
  (or (cdr (gethash format *format-state-constructors*))
      (unknown-format-error format)))

(defun register-descriptor-and-constructors (format-names
                                             descriptor
                                             encoder-constructor
                                             decoder-constructor)
  (flet ((add-with-specified-format (format)
           (setf (gethash format *format-descriptors*) descriptor)
           (setf (gethash format *format-state-constructors*)
                 (cons encoder-constructor decoder-constructor))))
    (mapc #'add-with-specified-format format-names)
    format-names))

(defmacro define-format (name &key
                         ((:format-descriptor descriptor-fun))
                         ((:encode-state-maker encoder-constructor))
                         ((:decode-state-maker decoder-constructor))
                         encode-length-fun decode-length-fun
                         encoder-fun decoder-fun)
  (flet ((format-docstring (&rest args)
               (declare (optimize (debug 3)))
               (loop with docstring = (apply #'format nil args)
                     for start = 0 then (when pos (1+ pos))
                     while start
                     for pos = (position #\Space docstring :start start)
                     collect (subseq docstring start pos) into words
                     finally (return (format nil "~{~<~%~1,76:;~A~>~^ ~}"
                                             words))))
         (intern-symbol (string &rest args)
           (intern (apply #'format nil string args) "BINASCII")))
    (let ((binascii-name (intern (symbol-name name)))
          (simple-encode-fun (intern-symbol "ENCODE-~A" name))
          (simple-decode-fun (intern-symbol "DECODE-~A" name))
          (octets->octets/encode (intern-symbol "OCTETS->OCTETS/ENCODE/~A" name))
          (octets->string (intern-symbol "OCTETS->STRING/~A" name))
          (octets->octets/decode (intern-symbol "OCTETS->OCTETS/DECODE/~A" name))
          (string->octets (intern-symbol "STRING->OCTETS/~A" name)))
      ;; FORMAT needs a little help to do proper line wrapping.
      `(progn
         (export ',simple-encode-fun)
         (defun ,simple-encode-fun (octets &key (start 0) end
                             (element-type 'base-char))
           ,(format-docstring "Encodes OCTETS using ~(~A~) encoding.  The rest of the arguments are as for ENCODE." name)
           (encode-to-fresh-vector octets (funcall #',encoder-constructor)
                                   start end element-type))
         (export ',simple-decode-fun)
         (defun ,simple-decode-fun (string &key (start 0) end
                             case-fold map01 decoded-length)
           ,(format-docstring "Decodes STRING using ~(~A~) encoding.  The rest of the arguments are as for DECODE." name)
           (decode-to-fresh-vector string (funcall #',decoder-constructor
                                                   case-fold map01)
                                   start end decoded-length))
         (defun ,octets->octets/encode (state output input
                                        output-start output-end
                                        input-start input-end lastp)
           (declare (type simple-octet-vector output))
           (declare (optimize speed))
           (,encoder-fun state output input output-start output-end
                         input-start input-end lastp #'char-code))
         (defun ,octets->string (state output input
                                 output-start output-end
                                 input-start input-end lastp)
           (declare (type simple-string output))
           (,encoder-fun state output input output-start output-end
                         input-start input-end lastp #'identity))
         (defun ,string->octets (state output input
                                 output-index output-end
                                 input-index input-end lastp)
           (declare (type simple-string input))
           (declare (optimize speed))
           (,decoder-fun state output input output-index output-end
                         input-index input-end lastp #'char-code))
         (defun ,octets->octets/decode (state output input
                                        output-index output-end
                                        input-index input-end lastp)
           (declare (type simple-octet-vector input))
           (declare (optimize speed))
           (,decoder-fun state output input output-index output-end
                         input-index input-end lastp #'identity))
         (register-descriptor-and-constructors '(,name ,binascii-name)
                                               (,descriptor-fun)
                                               (function ,encoder-constructor)
                                               (function ,decoder-constructor))))))

(defun make-encoder (format)
  "Return an ENCODE-STATE for FORMAT.  Error if FORMAT is not a known
encoding format."
  (let ((constructor (find-encode-state-constructor-or-lose format)))
    (funcall (the function constructor))))

(defun find-encoder (format)
  (etypecase format
    (symbol (make-encoder format))
    (encode-state format)))

(defun make-decoder (format case-fold map01)
  "Return a DECODE-STATE for FORMAT.  Use CASE-FOLD and MAP01 to
parameterize the returned decoder.  Error if FORMAT is not a known
decoding format."
  (let ((constructor (find-decode-state-constructor-or-lose format)))
    (funcall (the function constructor) case-fold map01)))

(defun find-decoder (format case-fold map01)
  (etypecase format
    (symbol (make-decoder format case-fold map01))
    (decode-state format)))
