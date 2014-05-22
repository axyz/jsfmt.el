;; jsfmt.el -- Interface to jsfmt command for javascript files
;; https://rdio.github.io/jsfmt

;; Version 0.1.0

;; this is basically a copy of the necessary parts from
;; go-mode version 20131222, so all credit goes to
;; The Go Authors

(defcustom jsfmt-command "jsfmt"
  "The 'jsfmt' command. https://rdio.github.io/jsfmt"
  :type 'string
  :group 'js)

(defun js--goto-line (line)
  (goto-char (point-min))
  (forward-line (1- line)))

(defalias 'js--kill-whole-line
  (if (fboundp 'kill-whole-line)
      #'kill-whole-line
    #'kill-entire-line))

;; Delete the current line without putting it in the kill-ring.
(defun js--delete-whole-line (&optional arg)
  ;; Emacs uses both kill-region and kill-new, Xemacs only uses
  ;; kill-region. In both cases we turn them into operations that do
  ;; not modify the kill ring. This solution does depend on the
  ;; implementation of kill-line, but it's the only viable solution
  ;; that does not require to write kill-line from scratch.
  (flet ((kill-region (beg end)
                      (delete-region beg end))
         (kill-new (s) ()))
    (js--kill-whole-line arg)))

(defun js--apply-rcs-patch (patch-buffer)
  "Apply an RCS-formatted diff from PATCH-BUFFER to the current
buffer."
  (let ((target-buffer (current-buffer))
        ;; Relative offset between buffer line numbers and line numbers
        ;; in patch.
        ;;
        ;; Line numbers in the patch are based on the source file, so
        ;; we have to keep an offset when making changes to the
        ;; buffer.
        ;;
        ;; Appending lines decrements the offset (possibly making it
        ;; negative), deleting lines increments it. This order
        ;; simplifies the forward-line invocations.
        (line-offset 0))
    (save-excursion
      (with-current-buffer patch-buffer
        (goto-char (point-min))
        (while (not (eobp))
          (unless (looking-at "^\\([ad]\\)\\([0-9]+\\) \\([0-9]+\\)")
            (error "invalid rcs patch or internal error in js--apply-rcs-patch"))
          (forward-line)
          (let ((action (match-string 1))
                (from (string-to-number (match-string 2)))
                (len  (string-to-number (match-string 3))))
            (cond
             ((equal action "a")
              (let ((start (point)))
                (forward-line len)
                (let ((text (buffer-substring start (point))))
                  (with-current-buffer target-buffer
                    (decf line-offset len)
                    (goto-char (point-min))
                    (forward-line (- from len line-offset))
                    (insert text)))))
             ((equal action "d")
              (with-current-buffer target-buffer
                (js--goto-line (- from line-offset))
                (incf line-offset len)
                (js--delete-whole-line len)))
             (t
              (error "invalid rcs patch or internal error in js--apply-rcs-patch")))))))))

(defun jsfmt ()
  "Formats the current buffer according to the jsfmt tool."

  (interactive)
  (let ((tmpfile (make-temp-file "jsfmt" nil ".js"))
        (patchbuf (get-buffer-create "*Jsfmt patch*"))
        (errbuf (get-buffer-create "*Jsfmt Errors*"))
        (coding-system-for-read 'utf-8)
        (coding-system-for-write 'utf-8))

    (with-current-buffer errbuf
      (setq buffer-read-only nil)
      (erase-buffer))
    (with-current-buffer patchbuf
      (erase-buffer))

    (write-region nil nil tmpfile)

    ;; We're using errbuf for the mixed stdout and stderr output. This
    ;; is not an issue because jsfmt -w does not produce any stdout
    ;; output in case of success.
    (if (zerop (call-process jsfmt-command nil errbuf nil "-w" tmpfile))
        (if (zerop (call-process-region (point-min) (point-max) "diff" nil patchbuf nil "-n" "-" tmpfile))
            (progn
              (kill-buffer errbuf)
              (message "Buffer is already jsfmted"))
          (js--apply-rcs-patch patchbuf)
          (kill-buffer errbuf)
          (message "Applied jsfmt"))
      (message "Could not apply jsfmt. Check errors for details")
      (jsfmt--process-errors (buffer-file-name) tmpfile errbuf))

    (kill-buffer patchbuf)
    (delete-file tmpfile)))

(defun jsfmt--process-errors (filename tmpfile errbuf)
  ;; Convert the jsfmt stderr to something understood by the compilation mode.
  (with-current-buffer errbuf
    (goto-char (point-min))
    (insert "jsfmt errors:\n")
    (while (search-forward-regexp (concat "^\\(" (regexp-quote tmpfile) "\\):") nil t)
      (replace-match (file-name-nondirectory filename) t t nil 1))
    (compilation-mode)
    (display-buffer errbuf)))

(defun jsfmt-before-save ()
  "Add this to .emacs to run jsfmt on the current buffer when saving:
 (add-hook 'before-save-hook 'jsfmt-before-save).

Note that this will cause js-mode to get loaded the first time
you save any file, kind of defeating the point of autoloading."

  (interactive)
  (when (eq major-mode 'js-mode) (jsfmt)))

(provide 'jsfmt)