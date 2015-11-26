;;; hie-tests.el --- tests for indentation module -*- lexical-binding: t -*-

;; Copyright (C) 2015 Haskell Ide Engine contributors

;; See LICENSE for details.

;;; Commentary:

;;; Code:

(require 'cl-lib)
(require 'ert)
(require 'hie)

(defun really-sleep-for (sec &optional test)
  "Sleep for SEC seconds or until TEST is not-nil.

Emacs has a bug when `sleep-for' terminates early when a
subprocess ends.  This is a workaround for
http://debbugs.gnu.org/cgi/bugreport.cgi?bug=15990."

  (let ((now (cadr (current-time))))
    (while (and (or (not test) (not (funcall test)))
                (> now (- (cadr (current-time)) sec)))
      (sleep-for (- now (- (cadr (current-time)) sec))))))


(setq hie-command-args
      '("-d" "-l" "/tmp/hie.log"))

(defvar hie-sent-commands ()
  "Recent commands sent to hie, in reverse order.")

(defun hie-push-command (json)
  (setq hie-sent-commands (cons json hie-sent-commands)))

(defvar hie-tests-collected-invalid-input nil)

(defun hie-tests-message-invalid-input (input)
  (setq hie-tests-collected-invalid-input
        (mapconcat 'identity
                   (list hie-tests-collected-invalid-input
                         input) nil)))

(setq hie-process-handle-invalid-input
      #'hie-tests-message-invalid-input)

(ert-deftest hie-can-run-executable ()
  (when nil
    (should (equal 0 (call-process "hie")))))

(defmacro hie-define-test (name &rest body)
  "Define a HIE test isolated and wrapped in nice reporting capabilities."
  `(ert-deftest ,name ()
    (let* (hie-test-success
           hie-sent-commands
           hie-tests-collected-invalid-input)

      (unwind-protect
          (progn

            (add-hook 'hie-post-message-hook
                      'hie-push-command)

            (when (hie-process-live-p)
              (hie-kill-process))

            (condition-case nil
                (delete-file "/tmp/hie.log")

              ;; don't fret out if the log file is not there
              (file-error nil))

            (hie-start-process)

            ,@body

            (setq hie-test-success t))

        (remove-hook 'hie-post-message-hook
                     'hie-push-command)

        (when (hie-process-live-p)
          (hie-kill-process))

        (when hie-tests-collected-invalid-input
          (message "Invalid HIE output:")
          (message "%s\n" hie-tests-collected-invalid-input))

        (unless hie-test-success
          (when hie-sent-commands
            (message "Commands sent to hie during this test:")
            (mapcar (apply-partially #'message "%s") hie-sent-commands))
          (when (file-exists-p "/tmp/hie.log")
            (message "Contents of /tmp/hie.log:")
            (with-current-buffer (find-file-noselect "/tmp/hie.log" t)
              (message "%s\n" (buffer-substring-no-properties (point-min) (point-max)))
              (kill-buffer (current-buffer)))))))))


(hie-define-test
 hie-can-start-stop-process

 ;; first invocation starts the process
 (should (hie-start-process))
 ;; second invocation does nothing but does not fail either
 (should (hie-start-process))

 ;; process is alive and well at this point
 (should (hie-process-live-p))

 ;; lets kill it, twice
 (hie-kill-process)
 (hie-kill-process))

(hie-define-test
 hie-can-get-version-information

 ;; starts the process
 (should (hie-start-process))

 (let ((response))
   (setq hie-process-handle-message
         (lambda (json)
           (setq response json)))
   (hie-post-message
    '(("cmd" . "base:version") ("params" . ())))

   (really-sleep-for 2 (lambda () response))
   (should response)
   (should (assq 'ok response))))

(hie-define-test
 hie-can-list-plugins

 ;; starts the process
 (should (hie-start-process))

 (let ((response))
   (setq hie-process-handle-message
         (lambda (json)
           (setq response json)))
   (hie-post-message
    '(("cmd" . "base:plugins")))

   (really-sleep-for 2 (lambda () response))
   (should response)

   (should (assq 'plugins response))
   (should (assq 'base (assq 'plugins response)))
   (should (cl-find-if (lambda (item) (equal '(name . "version") (assq 'name item)))
                       (cdr (assq 'base (assq 'plugins response)))))))


(ert-deftest hie-can-handle-invalid-input ()

  (let* (response
         hie-tests-collected-invalid-input
         (hie-process-handle-invalid-input
          (lambda (input)
            (setq response input)))
         (hie-buffer
          (get-buffer-create "*hie*")))

    (unwind-protect
        (progn
          (hie-process-filter nil "not a json text\^b")

          (should (equal "not a json text" response)))
      (kill-buffer hie-buffer))))

(hie-define-test
 hie-can-handle-input-in-chunks

 ;; Emacs fetches input from processes in chunks, 400 bytes is one
 ;; number from documentation. Anyway we need to be ready to handle
 ;; input in chunks.
 (let* ((response)
        (hie-process-handle-message
         (lambda (json)
           (setq response json)))

        (hie-process-handle-invalid-input
         (lambda (input)
           (setq response input))))
   (hie-process-filter nil "{")
   (hie-process-filter nil "\"key\":")
   (hie-process-filter nil "\"val\"}")
   (hie-process-filter nil "\^b")

   (should (equal '((key . "val")) response))))






;;; hie-tests.el ends here
