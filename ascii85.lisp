;;;; ascii85.lisp -- The ascii85 encoding, as used in PDF and btoa/atob.

(cl:in-package :binascii)

(defvar *ascii85-encode-table*
  #.(coerce "!\"#$%&'()*+,-./0123456789:;<=>?@ABCDEFGHIJKLMNOPQRSTUVWXYZ[\\]^_`abcdefghijklmnopqrstu" 'simple-base-string))

(defun encoded-length-ascii85 (count)
  "Return the number of characters required to encode COUNT octets in Ascii85."
  (multiple-value-bind (q r) (truncate count 4)
    (let ((complete (* q 5)))
      (if (zerop r)
          complete
          (+ complete r 1)))))

(defun encode-octets-ascii85 (octets start end table writer)
  (declare (type (simple-array (unsigned-byte 8) (*)) octets))
  (declare (type index start end))
  (declare (type function writer))
  (declare (ignore table))
  (flet ((output (buffer group count)
           (if (zerop group)
               (funcall writer #\z)
               (loop for i from 4 downto 0
                 do (multiple-value-bind (g b) (truncate group 85)
                      (setf group g
                            (aref buffer i) (code-char (+ #.(char-code #\!) b))))
                  finally (dotimes (i (1+ count))
                            (funcall writer (aref buffer i)))))))
    (loop with length = (- end start)
       with buffer = (make-string 5)
       with group of-type (unsigned-byte 32) = 0
       with count of-type fixnum = 0
       with shift of-type fixnum = 24
       until (zerop length)
       do (setf group (logior group (ash (aref octets start) shift)))
         (incf start)
         (decf length)
         (decf shift 8)
         (when (= (incf count) 4)
           (output buffer group count)
           (setf group 0 count 0 shift 24))
       finally (unless (zerop count)
                 (output buffer group count)))))

(defmethod encoding-tools ((format (eql :ascii85)))
  (values #'encode-octets-ascii85 #'encoded-length-ascii85
          *ascii85-encode-table*))

(defvar *ascii85-decode-table* (make-decode-table *ascii85-encode-table*))
(declaim (type decode-type *ascii85-decode-table*))

(defun decoded-length-ascii85 (length)
  ;; FIXME: There's nothing smart we can do without scanning the string.
  ;; We have to assume the worst case, that all the characters in the
  ;; string are #\z.
  (* length 5))

(defun decode-octets-ascii85 (string start end length table writer)
  (declare (type index start end))
  (declare (type function writer))
  (declare (type decode-table table))
  (flet ((do-decode (transform)
           (do ((i 0)
                (acc 0))
               ((>= start end)
                (unless (zerop i)
                  (when (= i 1)
                    (error "corrupt ascii85 group"))
                  (dotimes (j (- 5 i))
                    (setf acc (+ (* acc 85) 84)))
                  (dotimes (j (1- i))
                    (funcall writer (ldb (byte 8 (* (- 3 j) 8)) acc)))))
             (cond
               ((>= i 5)
                (unless (< acc (ash 1 32))
                  (error "invalid ascii85 sequence"))
                (dotimes (i 4)
                  (funcall writer (ldb (byte 8 (* (- 3 i) 8)) acc)))
                (setf i 0
                      acc 0))
               (t
                (let* ((b (funcall transform (aref string start)))
                       (d (dtref table b)))
                  (incf start)
                  (cond
                    ((= b #.(char-code #\z))
                     (unless (zerop i)
                       (error "z found in the middle of an ascii85 group"))
                     (dotimes (i 4)
                       (funcall writer 0)))
                    ((= d +dt-invalid+)
                     (error "invalid ascii85 character ~X" b))
                    (t
                     (incf i)
                     (setf acc (+ (* acc 85) d))))))))))
    (declare (inline do-decode))
    (decode-dispatch string #'do-decode)))

(defmethod decoding-tools ((format (eql :ascii85)) &key case-fold map01)
  (declare (ignorable case-fold map01))
  (values #'decode-octets-ascii85 #'decoded-length-ascii85
          *ascii85-decode-table*))
