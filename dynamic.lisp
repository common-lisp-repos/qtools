#|
 This file is a part of Qtools
 (c) 2015 Shirakumo http://tymoon.eu (shinmera@tymoon.eu)
 Author: Nicolas Hafner <shinmera@tymoon.eu>
|#

(in-package #:org.shirakumo.qtools)

(defun to-readtable-case (string &optional (readtable *readtable*))
  (ecase (readtable-case readtable)
    (:upcase (string-upcase string))
    (:downcase (string-downcase string))
    (:preserve string)
    (:invert (with-output-to-string (stream)
               (loop for char across string
                     do (cond ((upper-case-p char) (write-char (char-downcase char) stream))
                              ((lower-case-p char) (write-char (char-upcase char) stream))
                              (T (write-char char stream))))))))

(defun ensure-q+-method (function)
  (handler-bind ((style-warning #'muffle-warning))
    (let ((symbol (find-symbol (string function) *target-package*)))
      (unless (and symbol (fboundp symbol))
        (ensure-methods-processed)
        (funcall
         (compile NIL `(lambda () ,(compile-wrapper symbol)))))
      symbol)))

(defmacro q+ (function &rest args)
  (let ((symbol (ensure-q+-method function)))
    `(progn
       (load-time-value (ensure-q+-method ',function))
       (,symbol ,@args))))

;;;;;
;; SETF

(defun process-q+-setter (place value)
  (when (eql (first place) 'q+)
    (setf place (rest place)))
  (let ((name (first place))
        (name-args (rest place))
        (value-args (if (and (listp value) (eql (first value) 'values))
                        (rest value)
                        (list value))))
    `(q+ ,(to-readtable-case (format NIL "SET-~a" (string name))) ,@name-args ,@value-args)))

(defmacro cl+qt:setf (&rest args)
  (assert (evenp (length args))
          () "Must supply balanced pairs of places and values.")
  `(progn
     ,@(loop for (place value) on args by #'cddr
             if (and (listp place)
                     (or (eql (first place)
                              'q+)
                         (eql (symbol-package (first place))
                              *target-package*)))
             collect (process-q+-setter place value)
             else
             collect `(cl:setf ,place ,value))))

;;;;;
;; Reader

(defun read-list-until (char stream &optional (recursive-p T))
  (let ((char-macro (get-macro-character char)))
    (assert char-macro)
    (loop with read
          for next-char = (peek-char T stream T NIL recursive-p)
          when (let ((macro (get-macro-character next-char)))
                 (cond ((eq char-macro macro)
                        (loop-finish))
                       ((not macro)
                        (setf read (read stream T NIL recursive-p))
                        T)
                       (T
                        (setf read
                              (multiple-value-list
                               (funcall macro stream
                                        (read-char stream T NIL recursive-p))))
                        (when read
                          (setf read (car read))
                          T))))
          collect read)))

(defun read-name (stream)
  (with-output-to-string (output)
    (loop for char = (peek-char NIL stream T NIL T)
          do (if (or (char= char #\Space)
                     (not (graphic-char-p char))
                     (get-macro-character char))
                 (loop-finish)
                 (write-char (read-char stream T NIL T) output)))))

(defun q+-symbol-p (stream)
  (let ((buffer ()))
    (prog1
        (loop for char across "q+:"
              for read = (read-char stream)
              do (push read buffer)
              always (char-equal char read))
      (dolist (char buffer)
        (unread-char char stream)))))

(defun q+-symbol-name (string)
  (cond ((string-starts-with-p "q+::" string)
         (subseq string (length "q+::")))
        ((string-starts-with-p "q+:" string)
         (subseq string (length "q+:")))
        (T (error "~s is not a Q+ symbol string!" string))))

(defvar *standard-paren-reader* (get-macro-character #\())
(progn
  (defun read-paren (stream char)
    (if (q+-symbol-p stream)
        (let* ((name (to-readtable-case (q+-symbol-name (read-name stream))))
               (contents (read-list-until #\) stream)))
          (read-char stream) ;consume closing ).
          `(q+ ,name ,@contents))
        (funcall *standard-paren-reader* stream char)))

  (set-macro-character #\( #'read-paren NIL (named-readtables:find-readtable :qtools)))
