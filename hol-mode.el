;;; -*- emacs-lisp -*-
;;; to use this mode, you will need to do something along the lines of
;;; the following and have it in your .emacs file:
;;;    (setq hol-executable "<fullpath to HOL executable>")
;;;    (load "<fullpath to this file>")

;;; The fullpath to this file can be just the name of the file, if
;;; your elisp variable load-path includes the directory where it
;;; lives.

(require 'thingatpt)
(require 'cl)


(defgroup hol nil
  "Customising the Emacs interface to the HOL4 proof assistant."
  :group 'external)

(define-prefix-command 'hol-map)
(define-prefix-command 'hol-d-map)
(make-variable-buffer-local 'hol-buffer-name)
(make-variable-buffer-local 'hol-buffer-ready)
(set-default 'hol-buffer-ready nil)
(set-default 'hol-buffer-name "*HOL*")

(set-default 'hol-default-buffer nil)

(defcustom hol-executable 
  "/home/syshen/hol-kananaskis-10/bin/hol"
  "Path-name for the HOL executable."
  :group 'hol
  :type '(file :must-match t))

(defcustom holmake-executable 
  "/home/syshen/hol-kananaskis-10/bin/Holmake"
  "Path-name for the Holmake executable."
  :group 'hol
  :type '(file :must-match t))

(defun hol-set-executable (filename)
  "*Set hol executable variable to be NAME."
  (interactive "fHOL executable: ")
  (setq hol-executable filename))

(defun holmake-set-executable (filename)
  "*Set holmake executable variable to be NAME."
  (interactive "fHOL executable: ")
  (setq holmake-executable filename))

(defvar hol-mode-sml-init-command
   "use (Globals.HOLDIR ^ \"/tools/hol-mode.sml\")"
  "*The command to send to HOL to load the ML-part of hol-mode.")


(defcustom hol-echo-commands-p nil
  "Whether or not to echo the text of commands originating elsewhere."
  :group 'hol
  :type 'boolean)

(defcustom hol-raise-on-recentre nil
  "Controls if hol-recentre (\\[hol-recentre]) also raises the HOL frame."
  :group 'hol
  :type 'boolean)

(defcustom hol-unicode-print-font-filename
  "/usr/share/fonts/truetype/ttf-dejavu/DejaVuSans.ttf"
  "File name of font to use when printing HOL output to a PDF file."
  :group 'hol
  :type '(file :must-match t))



(defvar hol-generate-locpragma-p t
  "*Whether or not to generate (*#loc row col *) pragmas for HOL.")

(defvar hol-emit-time-elapsed-p nil
  "*Whether or not to print time elapsed messages after causing HOL
evaluations.")

(defvar hol-auto-load-p t
  "*Do automatic loading?")

;;; For compatability between both Emacs and XEmacs, please use the following
;;; two functions to determine if the mark is active, or to set it active.

(defun is-region-active ()
  (or
    (and (fboundp 'region-active-p) (region-active-p)
         (fboundp 'region-exists-p) (region-exists-p))
    (and transient-mark-mode (boundp 'mark-active) mark-active)))

(defun set-region-active ()
  (or
    (and (fboundp 'zmacs-activate-region) (zmacs-activate-region))
    (and (boundp 'mark-active) (setq mark-active t))))

(put 'hol-term 'end-op
     (function (lambda () (skip-chars-forward "^`"))))
(defvar hol-beg-pos nil) ; ugh, global, but easiest this way
(put 'hol-term 'beginning-op
     (function (lambda () (skip-chars-backward "^`") (setq hol-beg-pos (point)))))
(defun hol-term-at-point ()
  (let ((s (thing-at-point 'hol-term)))
    (with-hol-locpragma hol-beg-pos s)))

;;; makes buffer hol aware.  Currently this consists of no more than
;;; altering the syntax table if its major is sml-mode.
(defun make-buffer-hol-ready ()
  (if (eq major-mode 'sml-mode)
      (progn
        (modify-syntax-entry ?` "$")
        (modify-syntax-entry ?\\ "\\"))))

(defun hol-buffer-ok (string)
  "Checks a string to see if it is the name of a good HOL buffer.
In reality this comes down to checking that a buffer-name has a live
process in it."
  (and string (get-buffer-process string)
       (eq 'run
           (process-status
            (get-buffer-process string)))))

(defun ensure-hol-buffer-ok ()
  "Ensures by prompting that a HOL buffer name is OK, and returns it."
  (if (not hol-buffer-ready)
      (progn (make-buffer-hol-ready) (setq hol-buffer-ready t)))
  (if (hol-buffer-ok hol-buffer-name) hol-buffer-name
    (message
     (cond (hol-buffer-name (concat hol-buffer-name " not valid anymore."))
           (t "Please choose a HOL to attach this buffer to.")))
    (sleep-for 1)
    (setq hol-buffer-name (read-buffer "HOL buffer: " hol-default-buffer t))
    (while (not (hol-buffer-ok hol-buffer-name))
      (ding)
      (message "Not a valid HOL process")
      (sleep-for 1)
      (setq hol-buffer-name
            (read-buffer "HOL buffer: " hol-default-buffer t)))
    (setq hol-default-buffer hol-buffer-name)
    hol-buffer-name))


(defun is-a-then (s)
  (and s (or (string-equal s "THEN") (string-equal s "THENL"))))

(defun next-hol-lexeme-terminates-tactic ()
  (skip-syntax-forward " ")
  (or (eobp)
      (char-equal (following-char) ?,)
      ;; (char-equal (following-char) ?=)
      (char-equal (following-char) ?\;)
      (is-a-then (word-at-point))
      (string= (word-at-point) "val")))

(defun previous-hol-lexeme-terminates-tactic ()
  (save-excursion
    (skip-chars-backward " \n\t\r")
    (or (bobp)
        (char-equal (preceding-char) ?,)
        (char-equal (preceding-char) ?=)
        (char-equal (preceding-char) ?\;)
        (and (condition-case nil
                 (progn (backward-char 1) t)
                 (error nil))
             (or (is-a-then (word-at-point))
                 (string= (word-at-point) "val"))))))

;;; returns true and moves forward a sexp if this is possible, returns nil
;;; and stays where it is otherwise
(defun my-forward-sexp ()
  (condition-case nil
      (progn (forward-sexp 1) t)
    (error nil)))
(defun my-backward-sexp()
  (condition-case nil
      (progn (backward-sexp 1) t)
    (error nil)))

(defun skip-hol-tactic-punctuation-forward ()
  (let ((last-point (point)))
    (while (progn (if (is-a-then (word-at-point)) (forward-word 1))
                  (skip-chars-forward ", \n\t\r")
                  (not (= last-point (point))))
      (setq last-point (point)))))

(defun word-before-point ()
  (save-excursion
    (condition-case nil
        (progn (backward-char 1) (word-at-point))
      (error nil))))

(defun skip-hol-tactic-punctuation-backward ()
  (let ((last-point (point)))
    (while (progn (if (is-a-then (word-before-point)) (forward-word -1))
                  (skip-chars-backward ", \n\t")
                  (not (= last-point (point))))
      (setq last-point (point)))))

(defun forward-hol-tactic (n)
  (interactive "p")
  ;; to start you have to get off "tactic" punctuation, i.e. whitespace,
  ;; commas and the words THEN and THENL.
  (let ((count (or n 1)))
    (cond ((> count 0)
           (while (> count 0)
             (let (moved)
               (skip-hol-tactic-punctuation-forward)
               (while (and (not (next-hol-lexeme-terminates-tactic))
                           (my-forward-sexp))
                 (setq moved t))
               (skip-chars-backward " \n\t\r")
               (setq count (- count 1))
               (if (not moved)
                   (error "No more HOL tactics at this level")))))
          ((< count 0)
           (while (< count 0)
             (let (moved)
               (skip-hol-tactic-punctuation-backward)
               (while (and (not (previous-hol-lexeme-terminates-tactic))
                           (my-backward-sexp))
                 (setq moved t))
               (skip-chars-forward " \n\t\r")
               (setq count (+ count 1))
               (if (not moved)
                   (error "No more HOL tactics at this level"))))))))

(defun backward-hol-tactic (n)
  (interactive "p")
  (forward-hol-tactic (if n (- n) -1)))

(defun prim-mark-hol-tactic ()
  (let ((bounds (bounds-of-thing-at-point 'hol-tactic)))
    (if bounds
        (progn
          (goto-char (cdr bounds))
          (push-mark (car bounds) t t)
          (set-region-active))
      (error "No tactic at point"))))

(defun mark-hol-tactic ()
  (interactive)
  (let ((initial-point (point)))
    (condition-case nil
        (prim-mark-hol-tactic)
      (error
       ;; otherwise, skip white-space forward to see if this would move us
       ;; onto a tactic.  If so, great, otherwise, go backwards and look for
       ;; one there.  Only if all this fails signal an error.
       (condition-case nil
           (progn
             (skip-chars-forward " \n\t\r")
             (prim-mark-hol-tactic))
         (error
          (condition-case e
              (progn
                (if (skip-chars-backward " \n\t\r")
                    (progn
                      (backward-char 1)
                      (prim-mark-hol-tactic))
                  (prim-mark-hol-tactic)))
            (error
             (goto-char initial-point)
             (signal (car e) (cdr e))))))))))


(defun with-hol-locpragma (pos s)
  (if hol-generate-locpragma-p
      (concat (hol-locpragma-of-position pos) s)
      s))

(defun hol-locpragma-of-position (pos)
  "Convert Elisp position into HOL location pragma.  Not for interactive use."
  (let ((initial-point (point)))
    (goto-char pos)
    (let* ((rowstart (point-at-bol))  ;; (line-beginning-position)
           (row      (+ (count-lines 1 pos)
                      (if (= rowstart pos) 1 0)))
           (col      (+ (current-column) 1)))
      (goto-char initial-point)
      (format " (*#loc %d %d *)" row col))))

(defun send-timed-string-to-hol (string echo-p)
  "Send STRING to HOL (with send-string-to-hol), and emit information about
how long this took."
  (interactive)
  (send-raw-string-to-hol
   "val hol_mode_time0 = #usr (Timer.checkCPUTimer Globals.hol_clock);" nil nil)
  (send-string-to-hol string echo-p)
  (send-raw-string-to-hol
       "val _ = let val t = #usr (Timer.checkCPUTimer Globals.hol_clock)
                      val elapsed = Time.-(t, hol_mode_time0)
                in
                      print (\"\\n*** Time taken: \"^
                             Time.toString elapsed^\"s\\n\")
                  end" nil nil))

(defvar tactic-connective-regexp
  "[[:space:]]*\\(THEN1\\|THENL\\|THEN\\|>>\\|>|\\|>-\\|\\\\\\\\\\)[[:space:]]*[[(]?"
  "Regular expression for strings used to put tactics together.")

(defun tactic-cleanup (string)
  "Remove trailing and leading instances of tactic connectives from a string.
A tactic connective is any one of \"THEN\", \"THENL\", \"THEN1\", \">>\", \">|\"
or \">-\"."
  (let* ((case-fold-search nil)
         (s0 (replace-regexp-in-string (concat "\\`" tactic-connective-regexp)
                                      ""
                                      string)))
    (replace-regexp-in-string (concat tactic-connective-regexp "\\'") "" s0)))

(defun copy-region-as-hol-tactic (start end arg)
  "Send selected region to HOL process as tactic."
  (interactive "r\nP")
  (let*
      ((region-string0 (with-hol-locpragma start (buffer-substring start end)))
       (ste "\"show_typecheck_errors\"")
       (region-string1 (tactic-cleanup region-string0))
       (region-string (concat "let val old = Feedback.current_trace "
                              ste
                              " val _ = Feedback.set_trace "
                              ste
                              " 0 in ("
                              region-string1
                              ") before "
                              "Feedback.set_trace " ste " old end"))
       (e-string (concat "proofManagerLib." (if arg "expandf" "e")))
       (tactic-string (format "%s (%s)" e-string region-string))
       (sender (if hol-emit-time-elapsed-p
                   'send-timed-string-to-hol
                 'send-string-to-hol)))
    (funcall sender tactic-string hol-echo-commands-p)))

;;; For goaltrees
(defun copy-region-as-goaltree-tactic (start end)
  "Send selected region to HOL process as goaltree tactic."
  (interactive "r\nP")
  (let* ((region-string (with-hol-locpragma start
                          (buffer-substring-no-properties start end)))
         (tactic-string
           (format "proofManagerLib.expandv (%S,%s) handle e => Raise e"
                   region-string region-string))
         (sender (if hol-emit-time-elapsed-p
                     'send-timed-string-to-hol
                   'send-string-to-hol)))
    (funcall sender tactic-string hol-echo-commands-p)))

(defun send-string-as-hol-goal (s)
  (let ((goal-string (format  "proofManagerLib.g `%s`" s)))
    (send-raw-string-to-hol goal-string hol-echo-commands-p t)
    (send-raw-string-to-hol "proofManagerLib.set_backup 100;" nil nil)))

(defun hol-do-goal (arg)
  "Send term around point to HOL process as goal.
If prefix ARG is true, or if in transient mark mode, region is active and
the region contains no backquotes, then send region instead."
  (interactive "P")
  (let ((txt (condition-case nil
                 (with-hol-locpragma (region-beginning)
                    (buffer-substring (region-beginning) (region-end)))
               (error nil))))
    (if (or (and (is-region-active) (= (count ?\` txt) 0))
            arg)
      (send-string-as-hol-goal txt)
    (send-string-as-hol-goal (hol-term-at-point)))))


(defun send-string-as-hol-goaltree (s)
  (let ((goal-string
         (format  "proofManagerLib.gt `%s` handle e => Raise e" s)))
    (send-raw-string-to-hol goal-string hol-echo-commands-p t)
    (send-raw-string-to-hol "proofManagerLib.set_backup 100;" nil nil)))


(defun hol-do-goaltree (arg)
  "Send term around point to HOL process as goaltree.
If prefix ARG is true, or if in transient mark mode, region is active and
the region contains no backquotes, then send region instead."
  (interactive "P")
  (let ((txt (condition-case nil
                 (with-hol-locpragma (region-beginning)
                    (buffer-substring (region-beginning) (region-end)))
               (error nil))))
    (if (or (and (is-region-active) (= (count ?\` txt) 0))
            arg)
      (send-string-as-hol-goaltree txt)
    (send-string-as-hol-goaltree (hol-term-at-point)))))

(defun copy-region-as-hol-definition (start end arg)
  "Send selected region to HOL process as definition/expression.  With a
prefix arg of 4 (hit control-u once), wrap what is sent so that it becomes
( .. ) handle e => Raise e, allowing HOL_ERRs to be displayed cleanly.
With a prefix arg of 16 (hit control-u twice), toggle Moscow ML's quiet-dec
variable before and after the region is sent."
  (interactive "r\np")
  (let* ((buffer-string
            (with-hol-locpragma start (buffer-substring start end)))
         (send-string
          (if (= arg 4)
              (concat "(" buffer-string ") handle e => Raise e")
            buffer-string))
         (sender (if hol-emit-time-elapsed-p
                     'send-timed-string-to-hol
                   'send-string-to-hol)))
    (if (= arg 16) (hol-toggle-quietdec))
    (funcall sender send-string hol-echo-commands-p)
    (if (> (length send-string) 300)
        (send-string-to-hol
         "val _ = print \"\\n*** Emacs/HOL command completed ***\\n\\n\""))
    (if (= (prefix-numeric-value arg) 16) (hol-toggle-quietdec))))



(defun copy-region-as-hol-definition-quitely (start end arg)
   (interactive "r\np")
   (hol-toggle-quiet-quietdec)
   (copy-region-as-hol-definition start end arg)
   (hol-toggle-quiet-quietdec))


(defun hol-name-top-theorem (string arg)
  "Name the top theorem of the proofManagerLib.
With prefix argument, drop the goal afterwards."
  (interactive "sName for top theorem: \nP")
  (if (not (string= string ""))
      (send-raw-string-to-hol
       (format "val %s = top_thm()" string)
       hol-echo-commands-p t))
  (if arg (send-raw-string-to-hol "proofManagerLib.drop()" hol-echo-commands-p nil)))

(defun hol-start-termination-proof (arg)
  "Send definition around point to HOL process as Defn.tgoal.
If prefix ARG is true, or if in transient mark mode, region is active and
the region contains no backquotes, then send region instead."
  (interactive "P")
  (let ((txt (condition-case nil
                 (with-hol-locpragma (region-beginning)
                    (buffer-substring (region-beginning) (region-end)))
               (error nil))))
    (if (or (and (is-region-active) (= (count ?\` txt) 0))
            arg)
      (hol-send-string-as-termination-proof txt)
    (hol-send-string-as-termination-proof (hol-term-at-point)))))

(defun hol-send-string-as-termination-proof (str)
  (send-raw-string-to-hol
   (concat
    "Defn.tgoal (Defn.Hol_defn \"HOLmode_defn\" `" str "`) handle e => Raise e") nil t))

(defun remove-sml-comments (end)
  (let (done (start (point)))
    (while (and (not done) (re-search-forward "(\\*\\|\\*)" end t))
        (if (string= (match-string 0) "*)")
            (progn
              (delete-region (- start 2) (point))
              (setq done t))
          ;; found a comment beginning
          (if (not (remove-sml-comments end)) (setq done t))))
      (if (not done) (message "Incomplete comment in region given"))
      done))

(defun remove-hol-term (end-marker)
  (let ((start (point)))
    (if (re-search-forward "`" end-marker t)
        (delete-region (- start 1) (point))
      (error
       "Incomplete HOL quotation in region given; starts >`%s<"
       (buffer-substring (point) (+ (point) 10))))))

(defun remove-dq-hol-term (end-marker)
  (let ((start (point)))
    (if (re-search-forward "``" end-marker t)
        (delete-region (- start 2) (point))
      (error
       "Incomplete (``-quoted) HOL term in region given; starts >``%s<"
       (buffer-substring (point) (+ (point) 10))))))

(defun remove-hol-string (end-marker)
  (let ((start (point)))
    (if (re-search-forward "\n\\|[^\\]?\"" end-marker t)
        (if (string= (match-string 0) "\n")
            (message "String literal terminated by newline - not allowed!")
          (delete-region (- start 1) (point))))))


(defun remove-sml-junk (start end)
  "Removes all sml comments, HOL terms and strings in the given region."
  (interactive "r")
  (let ((m (make-marker)))
    (set-marker m end)
    (save-excursion
      (goto-char start)
      (while (re-search-forward "(\\*\\|`\\|\"" m t)
        (cond ((string= (match-string 0) "(*") (remove-sml-comments m))
              ((string= (match-string 0) "\"") (remove-hol-string m))
              (t ; must be a back-tick
               (if (not (looking-at "`"))
                   (remove-hol-term m)
                 (forward-char 1)
                 (remove-dq-hol-term m)))))
      (set-marker m nil))))

(defun remove-sml-lets-locals
  (start end &optional looking-for-end &optional recursing)
  "Removes all local-in-ends and let-in-ends from a region.  We assume
that the buffer has already had HOL terms, comments and strings removed."
  (interactive "r")
  (let ((m (if (not recursing) (set-marker (make-marker) end) end))
        retval)
    (if (not recursing) (goto-char start))
    (if (re-search-forward "\\blet\\b\\|\\blocal\\b\\|\\bend\\b" m t)
        (let ((declstring (match-string 0)))
          (if (or (string= declstring "let") (string= declstring "local"))
              (and
               (remove-sml-lets-locals (- (point) (length declstring)) m t t)
               (remove-sml-lets-locals start m looking-for-end t)
               (setq retval t))
            ;; found an "end"
            (if (not looking-for-end)
                (message "End without corresponding let/local")
              (delete-region start (point))
              (setq retval t))))
      ;; didn't find anything
      (if looking-for-end
          (message "Let/local without corresponding end")
        (setq retval t)))
    (if (not recursing) (set-marker m nil))
    retval))

(defun word-list-to-regexp (words)
  (mapconcat (lambda (s) (concat "\\b" s "\\b")) words "\\|"))

(setq hol-open-terminator-regexp
      (concat ";\\|"
              (word-list-to-regexp
               '("val" "fun" "in" "infix[lr]?" "open" "local" "type"
                 "datatype" "nonfix" "exception" "end" "structure"))))

(setq sml-struct-id-regexp "[A-Za-z][A-Za-z0-9_]*")

(defun send-string-to-hol (string &optional echoit)
  "Send a string to HOL process."
  (let ((buf (ensure-hol-buffer-ok))
        (hol-ok hol-buffer-ready)
        (tmpbuf (generate-new-buffer "*HOL temporary*"))
        (old-mark-active (is-region-active)))
    (unwind-protect
        (save-excursion
          (set-buffer tmpbuf)
          (modify-syntax-entry ?_ "w")
          (setq hol-buffer-name buf) ; version of this variable in tmpbuf
          (setq hol-buffer-ready hol-ok) ; version of this variable in tmpbuf
          (setq case-fold-search nil) ; buffer-local version
          (insert string)
          (goto-char (point-min))
          (remove-sml-junk (point-min) (point-max))
          (goto-char (point-min))
          ;; first thing to do is to search through buffer looking for
          ;; identifiers of form id.id.  When spotted such identifiers need
          ;; to have the first component of the name loaded.
          (if hol-auto-load-p
             (while (re-search-forward (concat "\\(" sml-struct-id-regexp
                                            "\\)\\.\\w+")
                                       (point-max) t)
               (hol-load-string (match-string 1)))
             t)
          ;; next thing to do is to look for open declarations
          (goto-char (point-min))
          ;; search through buffer for open declarations
          (while (re-search-forward "\\s-open\\s-" (point-max) t)
            ;; point now after an open, now search forward to end of
            ;; buffer or a semi-colon, or an infix declaration or a
            ;; val or a fun or another open  (as per the regexp defined just
            ;; before this function definition
            (let ((start (point))
                  (end
                   (save-excursion
                     (if (re-search-forward hol-open-terminator-regexp
                                            (point-max) t)
                         (- (point) (length (match-string 0)))
                       (point-max)))))
              (hol-load-modules-in-region start end)))
          ;; send the string
          (delete-region (point-min) (point-max))
          (insert string)
          (send-buffer-to-hol-maybe-via-file echoit))
      (kill-buffer tmpbuf)) ; kill buffer always
    ;; deactivate-mark will have likely been set by all the editting actions
    ;; in the temporary buffer.  We fix this here, thereby keeping the mark
    ;; active, if it is active.
    ;; if in XEmacs, use (zmacs-activate-region) instead.
    (if (boundp 'deactivate-mark)
        (if deactivate-mark (setq deactivate-mark nil))
        (if (and old-mark-active (fboundp 'zmacs-activate-region))
            (zmacs-activate-region)))))

(defun interactive-send-string-to-hol (string &optional echoit)
   "Send a string to HOL process."
   (interactive "sString to send to HOL process: \nP")
   (if hol-emit-time-elapsed-p
       (send-timed-string-to-hol string echoit)
     (send-string-to-hol string echoit)))

(if (null temporary-file-directory)
    (if (equal system-type 'windows-nt)
        (if (not (null (getenv "TEMP")))
            (setq temporary-file-directory (getenv "TEMP")))
      (setq temporary-file-directory "/tmp")))

(defun make-temp-file-xemacs (prefix &optional dir-flag)
  "Create a temporary file.
The returned file name (created by appending some random characters at the end
of PREFIX, and expanding against `temporary-file-directory' if necessary,
is guaranteed to point to a newly created empty file.
You can then use `write-region' to write new data into the file.

If DIR-FLAG is non-nil, create a new empty directory instead of a file."
  (let (file)
    (while (condition-case ()
	       (progn
		 (setq file
		       (make-temp-name
			(expand-file-name prefix temporary-file-directory)))
		 (if dir-flag
		     (make-directory file)
		   (write-region "" nil file nil 'silent nil)) ;; 'excl
		 nil)
	    (file-already-exists t))
      ;; the file was somehow created by someone else between
      ;; `make-temp-name' and `write-region', let's try again.
      nil)
    file))

(defvar hol-mode-to-delete nil
  "String optionally containing name of last temporary file used to transmit
HOL sources to a running session (using \"use\")")

(defun send-buffer-to-hol-maybe-via-file (&optional echoit)
  "Send the contents of current buffer to HOL, possibly putting it into a
file to \"use\" first."
  (if (< 500 (buffer-size))
          (let ((fname (if (fboundp 'make-temp-file)
                              ;; then
                                    (make-temp-file "hol")
                              ;; else
                                    (make-temp-file-xemacs "hol")
                                 )))
            (if (stringp hol-mode-to-delete)
                (progn (condition-case nil
                           (delete-file hol-mode-to-delete)
                         (error nil))
                       (setq hol-mode-to-delete nil)))
            ; below, use visit parameter = 1 to stop message in mini-buffer
            (write-region (point-min) (point-max) fname nil 1)
            (send-raw-string-to-hol (format "use \"%s\"" fname) nil t)
            (setq hol-mode-to-delete fname))
    (send-raw-string-to-hol (buffer-string) echoit t)))


(defun send-raw-string-to-hol (string echoit newstart)
  "Sends a string in the raw to HOL.  Not for interactive use."
  (let ((buf (ensure-hol-buffer-ok)))
    (if echoit
        (save-excursion
          (set-buffer buf)
          (goto-char (point-max))
          (princ (concat string ";") (get-buffer buf))
          (goto-char (point-max))
          (comint-send-input)
          (hol-recentre))
      (comint-send-string buf (concat string ";\n")))))


(defun hol-backup ()
  "Perform a HOL backup."
  (interactive)
  (send-raw-string-to-hol "proofManagerLib.b()" hol-echo-commands-p t))

(defun hol-user-backup ()
  "Perform a HOL backup to a user-defined save-point."
  (interactive)
  (send-raw-string-to-hol "proofManagerLib.restore()" hol-echo-commands-p t))

(defun hol-user-save-backup ()
  "Saves the current status of the proof for later backups to this point."
  (interactive)
  (send-raw-string-to-hol "proofManagerLib.save()" hol-echo-commands-p t))

(defun hol-print-goal ()
  "Print the current HOL goal."
  (interactive)
  (send-raw-string-to-hol "proofManagerLib.p()" hol-echo-commands-p t))

(defun hol-print-all-goals ()
  "Print all the current HOL goals."
  (interactive)
  (send-raw-string-to-hol "proofManagerLib.status()" hol-echo-commands-p t))

(defun hol-interrupt ()
  "Perform a HOL interrupt."
  (interactive)
  (let ((buf (ensure-hol-buffer-ok)))
    (interrupt-process (get-buffer-process buf))))


(defun hol-kill ()
  "Kill HOL process."
  (interactive)
  (let ((buf (ensure-hol-buffer-ok)))
    (kill-process (get-buffer-process buf))))

(defun hol-recentre ()
  "Display the HOL window in such a way that it displays most text."
  (interactive)
  (if (get-buffer-window hol-buffer-name t)
      (save-selected-window
        (select-window (get-buffer-window hol-buffer-name t))
        (and hol-raise-on-recentre (raise-frame))
        (goto-char (point-max))
        (recenter -1))))

(defun hol-rotate (arg)
  "Rotate the goal stack N times.  Once by default."
  (interactive "p")
  (send-raw-string-to-hol (format "proofManagerLib.r %d" arg)
                          hol-echo-commands-p t))

(defun hol-scroll-up (arg)
  "Scrolls the HOL window."
  (interactive "P")
  (ensure-hol-buffer-ok)
  (save-excursion
    (select-window (get-buffer-window hol-buffer-name t))
    (scroll-up arg)))

(defun hol-scroll-down (arg)
  "Scrolls the HOL window."
  (interactive "P")
  (ensure-hol-buffer-ok)
  (save-excursion
    (select-window (get-buffer-window hol-buffer-name t))
    (scroll-down arg)))

(defun hol-use-file (filename)
  "Gets HOL session to \"use\" a file."
  (interactive "fFile to use: ")
  (send-raw-string-to-hol (concat "use \"" filename "\";")
                          hol-echo-commands-p nil))

(defun hol-load-string (s)
  "Loads the ML object file NAME.uo; checking that it isn't already loaded."
  (let* ((buf (ensure-hol-buffer-ok))
         (mys (format "%s" s)) ;; gets rid of text properties
         (commandstring
          (concat "val _ = if List.exists (fn s => s = \""
                  mys
                  "\") (emacs_hol_mode_loaded()) then () else "
                  "(print  \"Loading " mys
                  "\\n\"; " "Meta.load \"" mys "\");\n")))
    (comint-send-string buf commandstring)))

(defun hol-load-modules-in-region (start end)
  "Attempts to load all of the words in the region as modules."
  (interactive "rP")
  (save-excursion
    (goto-char start)
    (while (re-search-forward (concat "\\b" sml-struct-id-regexp "\\b") end t)
      (hol-load-string (match-string 0)))))

(defun hol-load-file (arg)
  "Gets HOL session to \"load\" the file at point.
If there is no filename at point, then prompt for file.  If the region
is active (in transient mark mode) and it looks like it might be a
module name or a white-space delimited list of module names, then send
region instead. With prefix ARG prompt for a file-name to load."
  (interactive "P")
  (let* ((wap (word-at-point))
         (txt (condition-case nil
                  (buffer-substring (region-beginning) (region-end))
                (error nil))))
    (cond (arg (hol-load-string (read-string "Library to load: ")))
          ((and (is-region-active)
                (string-match (concat "^\\(\\s-*" sml-struct-id-regexp
                                      "\\)+\\s-*$") txt))
           (hol-load-modules-in-region (region-beginning) (region-end)))
          ((and wap (string-match "^\\w+$" wap)) (hol-load-string wap))
          (t (hol-load-string (read-string "Library to load: "))))))


(defun hol-mode-init-sml ()
   (hol-toggle-quiet-quietdec)
   (send-raw-string-to-hol hol-mode-sml-init-command nil nil)
   (hol-toggle-quiet-quietdec))

(defun turn-off-hol-font-lock (oldvar)
  (interactive)
  (if (not oldvar)
      (progn
        (message "Turning on font-lock mode does nothing in HOL mode")
        (setq font-lock-defaults nil)))
  (setq font-lock-mode nil))

(defun holmake (&optional dir)
   (interactive "DRun Holmake in dir: ")
   (if (not (null dir))
      (save-excursion
         (set-buffer (get-buffer-create "*Holmake*"))
         (delete-region (point-min) (point-max))
         (cd (expand-file-name dir)))
      )
   (let* ((buf (make-comint "Holmake"
                  holmake-executable nil "--qof" "-k")))
      (save-excursion
         (set-buffer buf)
         (font-lock-mode 0)
         (make-local-variable 'font-lock-function)
         (setq font-lock-function 'turn-off-hol-font-lock)
         (setq comint-preoutput-filter-functions '(holmakepp-output-filter)))
         (setq comint-scroll-show-maximum-output t)
         (setq comint-scroll-to-bottom-on-output t)
      (display-buffer buf)
   ))

;** hol map keys and function definitions
(defun hol (niceness)
  "Runs a HOL session in a comint window.
With a numeric prefix argument, runs it niced to that level
or at level 10 with a bare prefix. "
  (interactive "P")
  (let* ((hol-was-ok (hol-buffer-ok hol-buffer-name))
         (niceval (cond ((null niceness) 0)
                        ((listp niceness) 0)
                        (t (prefix-numeric-value niceness))))
         (holname (format "HOL(n:%d)" niceval))
         (buf (cond ((> niceval 0)
                     (make-comint holname "nice" nil
                                  (format "-%d" niceval)
                                  hol-executable))
                    (t (make-comint "HOL" hol-executable)))))
    (setq hol-buffer-name (buffer-name buf))
    (switch-to-buffer buf)
    (setq comint-prompt-regexp "^- ")
    (setq hol-buffer-name (buffer-name buf))
    ;; must go to ridiculous lengths to ensure that font-lock-mode is
    ;; turned off and stays off
    (font-lock-mode 0)
    (make-local-variable 'font-lock-function)
    (setq font-lock-function 'turn-off-hol-font-lock)
    (make-local-variable 'comint-preoutput-filter-functions)
    (holpp-quiet-reset)
    (setq comint-preoutput-filter-functions '(holpp-output-filter))
    (setq comint-scroll-show-maximum-output t)
    (setq comint-scroll-to-bottom-on-output t)
    (if hol-was-ok t (hol-mode-init-sml))
    (send-raw-string-to-hol
     "val _ = Parse.current_backend := PPBackEnd.emacs_terminal;" nil nil)))

(defun hol-display ()
   (interactive)
   (display-buffer hol-buffer-name));


(defun hol-vertical (niceness)
  "Runs a HOL session after splitting the window"
  (interactive "P")
  (split-window-vertically)
  (other-window 1)
  (hol ())
  (other-window -1))

(defun hol-horizontal (niceness)
  "Runs a HOL session after splitting the window"
  (interactive "P")
  (split-window-horizontally)
  (other-window 1)
  (hol ())
  (other-window -1))


(defun run-program (filename niceness)
  "Runs a PROGRAM in a comint window, with a given (optional) NICENESS."
  (interactive "fProgram to run: \nP")
  (let* ((niceval (cond ((null niceness) 0)
                        ((listp niceness) 10)
                        (t (prefix-numeric-value niceness))))
         (progname (format "%s(n:%d)"
                          (file-name-nondirectory filename)
                          niceval))
         (buf (cond ((> niceval 0)
                     (make-comint progname "nice" nil
                                  (format "-%d" niceval)
                                  (expand-file-name filename)))
                   (t (make-comint progname
                                   (expand-file-name filename)
                                   nil)))))
    (switch-to-buffer buf)))

(defun hol-toggle-var (s)
  "Toggles the boolean variable STRING."
  (message (concat "Toggling " s))
  (send-raw-string-to-hol
   (format (concat "val _ = (%s := not (!%s);"
                   "print (\"*** %s now \" ^"
                   "Bool.toString (!%s)^\" ***\\n\"))")
           s s s s) nil nil))

(defun hol-toggle-var-quiet (s)
  "Toggles the boolean variable STRING."
  (send-raw-string-to-hol
   (format "val _ = (%s := not (!%s));"
           s s) nil nil))

(defun hol-toggle-trace (s &optional arg)
  "Toggles the trace variable STRING between zero and non-zero.  With prefix
argument N, sets the trace to that value in particular."
  (interactive "sTrace name: \nP")
  (if (null arg)
      (progn
        (message (concat "Toggling " s))
        (send-raw-string-to-hol
         (format "val _ = let val nm = \"%s\"
                      fun findfn r = #name r = nm
                      val old =
                            #trace_level (valOf (List.find findfn (traces())))
                  in
                      print (\"** \"^nm^\" trace now \");
                      if 0 < old then (set_trace nm 0; print \"off\\n\")
                      else (set_trace nm 1; print \"on\\n\")
                  end handle Option =>
                        print \"** No such trace var: \\\"%s\\\"\\n\""
                 s s) nil nil))
    (let ((n (prefix-numeric-value arg)))
      (message (format "Setting %s to %d" s n))
      (send-raw-string-to-hol
       (format "val _ = (set_trace \"%s\" %d; print \"** %s trace now %d\\n\")
                        handle HOL_ERR _ =>
                           print \"** No such trace var: \\\"%s\\\"\\n\""
               s n s n s) nil nil))))

(defun hol-toggle-unicode ()
  "Toggles the \"Unicode\" trace."
  (interactive)
  (hol-toggle-trace "Unicode"))


(defun hol-toggle-emacs-tooltips ()
  "Toggles whether HOL produces tooltip information while pretty-printing."
  (interactive)
  (hol-toggle-trace "PPBackEnd show types"))

(defun hol-toggle-pp-styles ()
  "Toggles whether HOL produces style informations while pretty-printing."
  (interactive)
  (hol-toggle-trace "PPBackEnd use styles"))

(defun hol-toggle-pp-cases ()
  "Toggles the \"pp_cases\" trace."
  (interactive)
  (hol-toggle-trace "pp_cases"))

(defun hol-toggle-pp-annotations ()
  "Toggles whether HOL produces annotations while pretty-printing."
  (interactive)
  (hol-toggle-trace "PPBackEnd use annotations"))

(defun hol-toggle-goalstack-fvs ()
  "Toggles the trace \"Goalstack.print_goal_fvs\"."
  (interactive)
  (hol-toggle-trace "Goalstack.print_goal_fvs"))

(defun hol-toggle-goalstack-print-goal-at-top ()
  "Toggles the trace \"Goalstack.print_goal_at_top\"."
  (interactive)
  (hol-toggle-trace "Goalstack.print_goal_at_top"))

(defun hol-toggle-goalstack-num-assums (arg)
  "Toggles the number of assumptions shown in a goal."
  (interactive "nMax. number of visible assumptions: ")
  (hol-toggle-trace "Goalstack.howmany_printed_assums" arg))

(defun hol-toggle-goalstack-num-subgoals (arg)
  "Toggles the number of shown subgoals."
  (interactive "nMax. number of shown subgoals: ")
  (hol-toggle-trace "Goalstack.howmany_printed_subgoals" arg))

(defun hol-toggle-simplifier-trace (arg)
  "Toggles the trace \"simplifier\".  With ARG sets trace to this value."
  (interactive "P")
  (hol-toggle-trace "simplifier" arg))

(defun hol-toggle-show-types (arg)
  "Toggles the global show_types variable. With prefix ARG sets trace to this value (setting trace to 2, is the same as setting the show_types_verbosely variable)."
  (interactive "P")
  (hol-toggle-trace "types" arg))

(defun hol-toggle-show-types-verbosely ()
  "Toggles the global show_types_verbosely variable."
  (interactive)
  (hol-toggle-var "Globals.show_types_verbosely"))

(defun hol-toggle-show-numeral-types()
  "Toggles the global show_numeral_types variable."
  (interactive)
  (hol-toggle-var "Globals.show_numeral_types"))

(defun hol-toggle-show-assums()
  "Toggles the global show_assums variable."
  (interactive)
  (hol-toggle-var "Globals.show_assums"))

(defun hol-toggle-quietdec ()
  "Toggles quiet declarations in the interactive system."
  (interactive)
  (message "Toggling 'Quiet declaration'")
  (send-raw-string-to-hol
   (concat
    "val _ = print (\"*** 'Quiet declaration' now \" ^"
    "Bool.toString (HOL_Interactive.toggle_quietdec()) ^ \" ***\\n\")") nil nil)
  (hol-toggle-var "Globals.interactive"))

(defun hol-toggle-quiet-quietdec ()
  "Toggles quiet declarations in the interactive system."
  (interactive)
  (send-raw-string-to-hol
    "val _ = HOL_Interactive.toggle_quietdec()" nil nil)
  (hol-toggle-var-quiet "Globals.interactive"))

(defun hol-toggle-show-times()
  "Toggles the elisp variable 'hol-emit-time-elapsed-p."
  (interactive)
  (setq hol-emit-time-elapsed-p (not hol-emit-time-elapsed-p))
  (message (if hol-emit-time-elapsed-p "Elapsed times WILL be displayed"
             "Elapsed times WON'T be displayed")))

(defun hol-toggle-echo-commands ()
  "Toggles the elisp variable 'hol-echo-commands-p."
  (interactive)
  (setq hol-echo-commands-p (not hol-echo-commands-p))
  (message (if hol-echo-commands-p "Commands WILL be echoed"
             "Commands WON'T be echoed")))

(defun hol-toggle-auto-load ()
  "Toggles the elisp variable 'hol-auto-load-p."
  (interactive)
  (setq hol-auto-load-p (not hol-auto-load-p))
  (message (if hol-auto-load-p "automatic loading ON"
             "automatic loading OFF")))

(defun hol-toggle-ppbackend ()
  "Toggles between using the Emacs and \"raw\" terminal pretty-printing."
  (interactive)
  (send-raw-string-to-hol
   (concat
    "val _ = if #name (!Parse.current_backend) = \"emacs_terminal\" then"
    "(Parse.current_backend := PPBackEnd.raw_terminal;"
    "print \"*** PP Backend now \\\"raw\\\" ***\\n\")"
    "else (Parse.current_backend := PPBackEnd.emacs_terminal;"
    "print \"*** PP Backend now \\\"emacs\\\" ***\\n\")") nil nil))



(defun set-hol-executable (filename)
  "Sets the HOL executable variable to be equal to FILENAME."
  (interactive "fHOL executable: ")
  (setq hol-executable filename))

(defun hol-restart-goal ()
  "Restarts the current goal."
  (interactive)
  (send-raw-string-to-hol "proofManagerLib.restart()" hol-echo-commands-p t))

(defun hol-drop-goal ()
  "Drops the current goal."
  (interactive)
  (send-raw-string-to-hol "proofManagerLib.drop()" hol-echo-commands-p t))

(defun hol-open-string (prefixp)
  "Opens HOL modules, prompting for the name of the module to load.
With prefix ARG, toggles quietdec variable before and after opening,
potentially saving a great deal of time as tediously large modules are
printed out.  (That's assuming that quietdec is false to start with.)"
  (interactive "P")
  (let* ((prompt0 "Name of module to (load and) open")
         (prompt (concat prompt0 (if prefixp " (toggling quietness)") ": "))
         (module-name (read-string prompt)))
    (hol-load-string module-name)
    (if prefixp (hol-toggle-quietdec))
    (send-raw-string-to-hol (concat "open " module-name) hol-echo-commands-p t)
    (if prefixp (hol-toggle-quietdec))))

(defun hol-db-match (tm)
  "Does a DB.match [] on the given TERM (given as a string, without quotes)."
  (interactive "sTerm to match on: ")
  (send-raw-string-to-hol (format "DB.print_match [] (Term`%s`)" tm)
                          hol-echo-commands-p t))

(defun hol-db-find (tm)
  "Does a DB.find on the given string."
  (interactive "sTheorem name part: ")
  (send-raw-string-to-hol (format "DB.print_find \"%s\"" tm)
                          hol-echo-commands-p t))

(defun hol-db-check (ty)
  "Does a sanity check on the current theory."
  (interactive "sTheory name: ")
  (send-raw-string-to-hol (format "Sanity.sanity_check_theory \"%s\"" ty)
                          hol-echo-commands-p t))

(defun hol-db-check-current ()
  "Does a sanity check on the current theory."
  (interactive)
  (send-raw-string-to-hol "Sanity.sanity_check()"
                          hol-echo-commands-p t))

(defun hol-drop-all-goals ()
  "Drops all HOL goals from the current proofs object."
  (interactive)
  (send-raw-string-to-hol
   (concat "proofManagerLib.dropn (case proofManagerLib.status() of "
           "Manager.PRFS l => List.length l)") nil t))

(defun hol-subgoal-tactic (p)
  "Without a prefix argument, sends term at point (delimited by backquote
characters) as a subgoal to prove.  Will usually create at least two sub-
goals; one will be the term just sent, and the others will be the term sent
STRIP_ASSUME'd onto the assumption list of the old goal.  This mimicks what
happens with the \"by\" command.

With a prefix argument, sends the delimited term as if the
argument of a \"suffices_by\" command, making two new goals: the
first is to show that the new term implies the old goal, and the
second is to show the new term.

(Loads the BasicProvers module if not already loaded.)"
  (interactive "P")
  (let ((tactic (if p "suffices_by" "by")))
    (send-string-to-hol
     (format "proofManagerLib.e (BasicProvers.%s(`%s`,ALL_TAC))"
             tactic
             (hol-term-at-point)))))


;; (defun hol-return-key ()
;;   "Run comint-send-input, but only if both: the user is editting the
;; last command in the buffer, and that command ends with a semicolon.
;; Otherwise, insert a newline at point."
;;   (interactive)
;;   (let ((comand-finished
;;          (let ((process (get-buffer-process (current-buffer))))
;;            (and (not (null process))
;;                 (let ((pmarkpos (marker-position
;;                                  (process-mark process))))
;;                   (and (< (point) pmarkpos)
;;                        (string-match ";[ \t\n\r]*$"
;;                                      (buffer-substring pmarkpos
;;                                                        (point-max)))))))))
;;     (if command-finished
;;         (progn
;;           (goto-char (point-max))
;;           (comint-send-input))
;;       (insert "\n"))))

;; (define-key comint-mode-map "\r" 'hol-return-key)



;;templates
(defun hol-extract-script-name (arg)
  "Return the name of the theory associated with the given filename"
(let* (
   (pos (string-match "[^/]*Script\.sml" arg)))
   (cond (pos (substring arg pos -10))
         (t "<insert theory name here>"))))

(defun hol-template-new-script-file ()
  "Inserts standard template for a HOL theory"
   (interactive)
   (insert "open HolKernel Parse boolLib bossLib;\n\nval _ = new_theory \"")
   (insert (hol-extract-script-name buffer-file-name))
   (insert "\";\n\n\n\n\nval _ = export_theory();\n\n"))

(defun hol-template-comment-star ()
   (interactive)
   (insert "\n\n")
   (insert "(******************************************************************************)\n")
   (insert "(*                                                                            *)\n")
   (insert "(*                                                                            *)\n")
   (insert "(*                                                                            *)\n")
   (insert "(******************************************************************************)\n"))

(defun hol-template-comment-minus ()
   (interactive)
   (insert "\n\n")
   (insert "(* -------------------------------------------------------------------------- *)\n")
   (insert "(*                                                                            *)\n")
   (insert "(*                                                                            *)\n")
   (insert "(*                                                                            *)\n")
   (insert "(* -------------------------------------------------------------------------- *)\n"))

(defun hol-template-comment-equal ()
   (interactive)
   (insert "\n\n")
   (insert "(* ========================================================================== *)\n")
   (insert "(*                                                                            *)\n")
   (insert "(*                                                                            *)\n")
   (insert "(*                                                                            *)\n")
   (insert "(* ========================================================================== *)\n"))

(defun hol-template-define (name)
   (interactive "sNew name: ")
   (insert "val ")
   (insert name)
   (insert "_def = Define `")
   (insert name)
   (insert " = `;\n"))

(defun hol-template-store-thm (name)
   (interactive "sTheorem name: ")
   (insert "val ")
   (insert name)
   (insert " = store_thm(")
   (cond ((> (length name) 30) (insert "\n  "))
          (t t))
   (insert "\"")
   (insert name)
   (insert "\",\n  ``  ``,\n"))

(defun hol-template-new-datatype ()
   (interactive)
   (insert "val _ = Datatype `TREE = LEAF ('a -> num) | BRANCH TREE TREE`;\n"))

;;checking for trouble with names in store_thm, save_thm, Define
(setq store-thm-regexp
   "val[ \t\n]*\\([^ \t\n]*\\)[ \t\n]*=[ \t\n]*store_thm[ \t\n]*([ \t\n]*\"\\([^\"]*\\)\"")
(setq save-thm-regexp
   "val[ \t\n]*\\([^ \t\n]*\\)[ \t\n]*=[ \t\n]*save_thm[ \t\n]*([ \t\n]*\"\\([^\"]*\\)\"")
(setq define-thm-regexp
   "val[ \t\n]*\\([^ \t\n]*\\)_def[ \t\n]*=[ \t\n]*Define[ \t\n]*`[ \t\n(]*\$?\\([^ \t\n([!?:]*\\)")

(setq statement-eq-regexp-list (list store-thm-regexp save-thm-regexp define-thm-regexp))

(defun hol-correct-eqstring (s1 p1 s2 p2)
  (interactive)
  (let (choice)
    (setq choice 0)
    (while (eq choice 0)
      (message
       (concat
	"Different names used. Please choose one:\n(0) "
	s1 "\n(1) " s2 "\n(i) ignore"))
      (setq choice (if (fboundp 'read-char-exclusive)
		       (read-char-exclusive)
		     (read-char)))
      (cond ((= choice ?0) t)
	    ((= choice ?1) t)
	    ((= choice ?i) t)
	    (t (progn (setq choice 0) (ding))))
      )
    (if (= choice ?i) t
    (let (so sr pr)
      (cond ((= choice ?0) (setq so s1 sr s2 pr p2))
	    (t             (setq so s2 sr s1 pr p1)))
      (delete-region pr (+ pr (length sr)))
      (goto-char pr)
      (insert so)
      ))))


(defun hol-check-statement-eq-string ()
  (interactive)
  (save-excursion
  (dolist (current-regexp statement-eq-regexp-list t)
  (goto-char 0)
  (let (no-error-found s1 p1 s2 p2)
    (while (re-search-forward current-regexp nil t)
      (progn (setq s1 (match-string-no-properties 1))
             (setq s2 (match-string-no-properties 2))
             (setq p1 (match-beginning 1))
             (setq p2 (match-beginning 2))
             (setq no-error-found (string= s1 s2))
             (if no-error-found t (hol-correct-eqstring s1 p1 s2 p2)))))
  (message "checking for problematic names done"))))


;;indentation and other cleanups
(defun hol-replace-tabs-with-spaces ()
   (save-excursion
      (goto-char (point-min))
      (while (search-forward "\t" nil t)
         (delete-region (- (point) 1) (point))
         (let* ((count (- tab-width (mod (current-column) tab-width))))
           (dotimes (i count) (insert " "))))))

(defun hol-remove-tailing-whitespaces ()
   (save-excursion
      (goto-char (point-min))
      (while (re-search-forward " +$" nil t)
         (delete-region (match-beginning 0) (match-end 0)))))


(defun hol-remove-tailing-empty-lines ()
   (save-excursion
      (goto-char (point-max))
      (while (bolp) (delete-char -1))
      (insert "\n")))

(defun hol-cleanup-buffer ()
   (interactive)
   (hol-replace-tabs-with-spaces)
   (hol-remove-tailing-whitespaces)
   (hol-remove-tailing-empty-lines)
   (message "Buffer cleaned up!"))



;;load-path
(defun ml-quote (s)
   (let* (
     (s1 (replace-regexp-in-string "\\\\" "\\\\\\\\" s))
     (s2 (replace-regexp-in-string "\n" "\\\\n" s1))
     (s3 (replace-regexp-in-string "\t" "\\\\t" s2))
     (s4 (replace-regexp-in-string "\"" "\\\\\"" s3))
   ) s4))

(defun hol-add-load-path (path)
  (interactive "DAdd new load-path: ")
  (let ((epath (expand-file-name path)))
  (if (file-accessible-directory-p epath)
     (progn
        (send-raw-string-to-hol
            (concat "loadPath := \"" (ml-quote epath) "\" :: !loadPath;")
            nil nil)
        (message (concat "Load-path \"" epath "\" added.")))
     (progn (ding) (message "Not a directory!")))
))


(defun hol-show-current-load-paths ()
   (interactive)
   (send-raw-string-to-hol "print_current_load_paths ()"
   nil nil))

(defun hol-type-info ()
   "Gives informations about the type of a term"
   (interactive)
   (let* ((txt (buffer-substring-no-properties (region-beginning) (region-end)))
          (use-marked (and (is-region-active) (= (count ?\` txt) 0)))
          (at-point-term (thing-at-point 'hol-term))

          (main-term (ml-quote (if use-marked txt at-point-term)))
          (context-term (ml-quote (if use-marked at-point-term "")))
          (command-s (concat "print_type_of_in_context true "
                      (if use-marked (concat "(SOME \"" context-term "\")") "NONE")
                      " \"" main-term "\"")))
   (send-raw-string-to-hol command-s nil nil)))


(defun holpp-decode-color (code)
  (cond ((equal code "0") "#000000")
        ((equal code "1") "#840000")
        ((equal code "2") "#008400")
        ((equal code "3") "#848400")
        ((equal code "4") "#000084")
        ((equal code "5") "#840084")
        ((equal code "6") "#008484")
        ((equal code "7") "#555555")
        ((equal code "8") "#949494")
        ((equal code "9") "#FF0000")
        ((equal code "A") "#00C600")
        ((equal code "B") "#FFFF00")
        ((equal code "C") "#0000FF")
        ((equal code "D") "#FF00FF")
        ((equal code "E") "#00FFFF")
        ((equal code "F") "#FFFFFF")
))

(defun holpp-decode-full-style (style)
   (let* (
       (fg (substring style 0 1))
       (bg (substring style 1 2))
       (b (substring style 2 3))
       (u (substring style 3 4))
       (fg-face (if (equal fg "-") nil
                    (cons :foreground (cons (holpp-decode-color fg) ()))))
       (bg-face (if (equal bg "-") nil
                    (cons :background (cons (holpp-decode-color bg) ()))))
       (b-face  (if (equal b "-") nil
                    (cons :weight (cons 'bold ()))))
       (u-face  (if (equal u "-") nil
                    (cons :underline (cons t ())))))
       (cons 'face (cons (append fg-face bg-face b-face u-face) ()))))


(defun holpp-find-comment-end (n)
   (if (not (re-search-forward "\\((\\*(\\*(\\*\\)\\|\\(\\*)\\*)\\*)\\)" nil t 1))
       nil
       (if (save-excursion (goto-char (- (point) 6))
                           (looking-at "(\\*(\\*(\\*"))
           (progn
              (holpp-find-comment-end (+ n 1)))
           (if (= n 1) t (holpp-find-comment-end (- n 1))))))

(defun holpp-execute-code-face-tooltip (start end toolprop codeface)
  (let ((tooltipprop
         (if (equal toolprop nil) nil (list 'help-echo toolprop))))
    (add-text-properties start end (append codeface tooltipprop))))

(defun holpp-execute-code (code arg1 start end)
  (cond ((equal code "FV")
             (holpp-execute-code-face-tooltip start end arg1
             '(face hol-free-variable)))
        ((equal code "BV")
             (holpp-execute-code-face-tooltip start end arg1
             '(face hol-bound-variable)))
        ((equal code "TV")
             (holpp-execute-code-face-tooltip start end arg1
             '(face hol-type-variable)))
        ((equal code "TY")
             (holpp-execute-code-face-tooltip start end arg1
             '(face hol-type)))
        ((equal code "CO")
         (holpp-execute-code-face-tooltip start end arg1 nil))
        ((equal code "ST")
           (add-text-properties start end
             (holpp-decode-full-style arg1)))))

(setq temp-hol-output-buf nil)

(defun holpp-quiet-reset ()
  (let ((tmpbuf (or temp-hol-output-buf
                     (generate-new-buffer " *HOL output filter*)"))))
      (setq temp-hol-output-buf tmpbuf)
      (save-excursion
         (set-buffer tmpbuf)
         (delete-region (point-min) (point-max)))))

(defun holpp-reset ()
  (interactive)
  (holpp-quiet-reset)
  (send-raw-string-to-hol "print \"\\n\\n*** hol-mode reset ***\\n\";" nil nil))

(defun holpp-output-filter (s)
  "Converts a munged emacs_terminal string into a pretty one with text properties."
  (interactive "sinput: ")
  (let* ((tmpbuf (or temp-hol-output-buf
                     (generate-new-buffer " *HOL output filter*)")))
         end)
    (setq temp-hol-output-buf tmpbuf)
    (save-excursion
      (set-buffer tmpbuf)
      (unwind-protect
          (progn
            (goto-char (point-max))
            (insert s)
            (goto-char (point-min))
            (while (and (not end) (search-forward "(*(*(*" nil t))
              (let ((uptoann (- (point) 6))
                    (start (point)))
                (if (not (holpp-find-comment-end 1))
                    (progn
                      (goto-char uptoann)
                      (setq end t))
                  (delete-region uptoann start)
                  (let*
                      ((start (- start 6))
                       (code (buffer-substring start (+ start 2)))
                       (argument
                        (save-excursion
                          (goto-char (+ start 2))
                          (if (equal (following-char) 0)
                              (progn
                                (goto-char (+ (point) 1))
                                (skip-chars-forward "^\^@")
                                (prog1
                                    (if (equal (+ start 3) (point)) nil
                                    (buffer-substring (+ start 3)
                                                            (point)))
                                  (delete-region (+ start 2) (1+ (point)))))
                            nil))))
                       (holpp-execute-code code argument
                        (+ start 2)
                        (- (point) 6))
                       (delete-region start (+ start 2))
                       (delete-region (- (point) 6) (point))
                       (goto-char start)))))
            (if (not end)
                (progn
                  (goto-char (point-max))
                  (skip-chars-backward "(*")))
            (prog1
                (buffer-substring (point-min) (point))
              (delete-region (point-min) (point))))))))

(defun holmakepp-mark-error (start end)
   (add-text-properties start end '(face holmake-error)))


(defun holmakepp-mark-mosml-error ()
  (interactive)
  (goto-char (point-min))
  (while (re-search-forward "^!" nil t)
     (let* ((start (match-beginning 0)))
     (forward-line)
     (while (or (looking-at "!") (looking-at " ")) (forward-line))
     (holmakepp-mark-error start (- (point) 1))))
)

(setq temp-holmake-output-buf nil)
(defun holmakepp-output-filter (s)
  "Converts a munged emacs_terminal string into a pretty one with text properties."
  (interactive "sinput: ")
  (let* ((tmpbuf (or temp-holmake-output-buf
                     (generate-new-buffer " *HOLMAKE output filter*)")))
         end)
    (setq temp-holmake-output-buf tmpbuf)
    (save-excursion
      (set-buffer tmpbuf)
      (unwind-protect
          (progn
            (goto-char (point-max))
            (insert s)
            (holmakepp-mark-mosml-error)
            (prog1
                (buffer-substring (point-min) (point-max))
              (delete-region (point-min) (point-max))))))))

(defgroup hol-faces nil "Faces used in pretty-printing HOL values"
  :group 'faces
  :group 'hol)

(defface holmake-error
  '((((class color))
     :foreground "red"
     :weight bold))
  "The face for errors shown by HOLMAKE."
  :group 'hol-faces)

(defface hol-free-variable
  '((((class color))
     :foreground "blue"
     :weight bold))
  "The face for presenting free variables in HOL terms."
  :group 'hol-faces)

(defface hol-bound-variable
  '((((class color))
     :foreground "#009900"))
  "The face for presenting bound variables in HOL terms."
  :group 'hol-faces)

(defface hol-type-variable
  '((((class color))
     :foreground "purple"
     :slant italic))
  "The face for presenting free type variables in HOL terms."
  :group 'hol-faces)

(defface hol-type
  '((((class color))
     :foreground "cyan3"
     :slant italic))
  "The face for presenting HOL types."
  :group 'hol-faces)

(defun hol-region-to-unicode-pdf (filename beg end)
  "Print region to FILE as a PDF, handling Unicode characters."
  (interactive "FFile to write to: \nr")
  (if (and transient-mark-mode (not mark-active))
      (error "No active region"))
  (let* ((temp-ps-file (make-temp-file "holprint" nil ".ps"))
         (lpr-switches
          (list "-font" hol-unicode-print-font-filename
                "-out" temp-ps-file))
         (lpr-add-switches nil)
         (lpr-command "uniprint"))
    (lpr-region beg end)
    (shell-command (concat "ps2pdf " temp-ps-file " " filename))
    (delete-file temp-ps-file)))

;;The key combinations
(define-key global-map "\M-h" 'hol-map)
(define-prefix-command 'holpp-map)
(define-key hol-map "\M-p" 'holpp-map)


(define-key hol-map "\C-c" 'hol-interrupt)
(define-key hol-map "\C-l" 'hol-recentre)
(define-key hol-map "\C-q" 'hol-toggle-quietdec)
(define-key hol-map "\C-s" 'hol-toggle-simplifier-trace)
(define-key hol-map "\C-v" 'hol-scroll-up)
(define-key hol-map "\M-f" 'forward-hol-tactic)
(define-key hol-map "\M-b" 'backward-hol-tactic)
(define-key hol-map "\M-r" 'copy-region-as-hol-definition)
(define-key hol-map "\C-r" 'copy-region-as-hol-definition-quitely)
(define-key hol-map "\M-q" 'copy-region-as-hol-definition-real-quitely)
(define-key hol-map "\M-t" 'hol-toggle-show-times)
(define-key hol-map "\M-s" 'hol-subgoal-tactic)
(define-key hol-map "\M-v" 'hol-scroll-down)
(define-key hol-map "b"    'hol-backup)
(define-key hol-map "B"    'hol-user-backup)
(define-key hol-map "S"    'hol-user-save-backup)
(define-key hol-map "d"    'hol-drop-goal)
(define-key hol-map "D"    'hol-drop-all-goals)
(define-key hol-map "e"    'copy-region-as-hol-tactic)
(define-key hol-map "E"    'copy-region-as-goaltree-tactic)
(define-key hol-map "g"    'hol-do-goal)
(define-key hol-map "G"    'hol-do-goaltree)
(define-key hol-map "h"    'hol)
(define-key hol-map "\M-m" 'holmake)
(define-key hol-map "4"    'hol-display)
(define-key hol-map "3"    'hol-horizontal)
(define-key hol-map "2"    'hol-vertical)
(define-key hol-map "l"    'hol-load-file)
(define-key hol-map "m"    'hol-db-match)
(define-key hol-map "f"    'hol-db-find)
(define-key hol-map "n"    'hol-name-top-theorem)
(define-key hol-map "o"    'hol-open-string)
(define-key hol-map "p"    'hol-print-goal)
(define-key hol-map "P"    'hol-print-all-goals)
(define-key hol-map "r"    'hol-rotate)
(define-key hol-map "R"    'hol-restart-goal)
(define-key hol-map "t"    'mark-hol-tactic)
(define-key hol-map "T"    'hol-start-termination-proof)
(define-key hol-map "i"    'hol-type-info)
(define-key hol-map "s"    'interactive-send-string-to-hol)
(define-key hol-map "u"    'hol-use-file)
(define-key hol-map "c"    'hol-db-check-current)
(define-key hol-map "*"    'hol-template-comment-star)
(define-key hol-map "-"    'hol-template-comment-minus)
(define-key hol-map "="    'hol-template-comment-equal)
(define-key hol-map "\M-d" 'hol-template-define)
(define-key hol-map "\M-x" 'hol-template-store-thm)


(define-key hol-map   "\C-a" 'hol-toggle-show-assums)
(define-key holpp-map "a"    'hol-toggle-show-assums)
(define-key hol-map   "\C-t" 'hol-toggle-show-types)
(define-key holpp-map "\C-t" 'hol-toggle-show-types)
(define-key hol-map   "\C-n" 'hol-toggle-show-numeral-types)
(define-key holpp-map "n"    'hol-toggle-show-numeral-types)
(define-key hol-map   "\C-f" 'hol-toggle-goalstack-fvs)
(define-key holpp-map "f"    'hol-toggle-goalstack-fvs)
(define-key hol-map   "\C-o" 'hol-toggle-goalstack-print-goal-at-top)
(define-key holpp-map "o"    'hol-toggle-goalstack-print-goal-at-top)
(define-key hol-map   "\M-a" 'hol-toggle-goalstack-num-assums)
(define-key holpp-map "\M-a" 'hol-toggle-goalstack-num-assums)
(define-key hol-map   "\C-u" 'hol-toggle-unicode)
(define-key holpp-map "u"    'hol-toggle-unicode)
(define-key hol-map   "\C-p" 'hol-toggle-ppbackend)
(define-key holpp-map "p"    'hol-toggle-ppbackend)
(define-key holpp-map "b"    'hol-toggle-emacs-tooltips)
(define-key holpp-map "t"    'hol-toggle-pp-annotations)
(define-key holpp-map "s"    'hol-toggle-pp-styles)
(define-key holpp-map "c"    'hol-toggle-pp-cases)


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; The definition of the HOL menu
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(define-key-after (lookup-key global-map [menu-bar])
  [hol-menu]
  (cons "HOL" (make-sparse-keymap "HOL"))
  'tools)


;; HOL misc
(define-key
  global-map
  [menu-bar hol-menu hol-misc]
  (cons "Misc" (make-sparse-keymap "Misc")))

(define-key global-map [menu-bar hol-menu hol-misc clean-up]
   '("Clean up (remove tab, white spaces at end of line, etc...)" .
     hol-cleanup-buffer))

(define-key global-map [menu-bar hol-menu hol-misc check-names]
   '("Check names in store_thm, ..." . hol-check-statement-eq-string))

(define-key global-map [menu-bar hol-menu hol-misc sep4]
   '(menu-item "--"))

(define-key global-map [menu-bar hol-menu hol-misc check-theory-current]
   '("Sanity check current theory" . hol-db-check-current))

(define-key global-map [menu-bar hol-menu hol-misc check-theory]
   '("Sanity check theory" . hol-db-check))

(define-key global-map [menu-bar hol-menu hol-misc sep3]
   '(menu-item "--"))

(define-key global-map [menu-bar hol-menu hol-misc mark-tactic]
   '("Mark tactic" . mark-hol-tactic))

(define-key global-map [menu-bar hol-menu hol-misc backward-tactic]
   '("Move to previous tactic" . backward-hol-tactic))

(define-key global-map [menu-bar hol-menu hol-misc forward-tactic]
   '("Move to next tactic" . forward-hol-tactic))

(define-key global-map [menu-bar hol-menu hol-misc sep2]
   '(menu-item "--"))

(define-key global-map [menu-bar hol-menu hol-misc open-string]
   '("Load and open" . hol-open-string))

(define-key global-map [menu-bar hol-menu hol-misc use-file]
   '("Use file" . hol-use-file))

(define-key global-map [menu-bar hol-menu hol-misc load-file]
   '("Load file" . hol-load-file))

(define-key global-map [menu-bar hol-menu hol-misc auto-load]
   '(menu-item "Automatic loading" hol-toggle-auto-load
                     :button (:toggle
                              . (and (boundp 'hol-auto-load-p)
                                     hol-auto-load-p))))

(define-key global-map [menu-bar hol-menu hol-misc show-load-paths]
   '("Show load-paths" . hol-show-current-load-paths))

(define-key global-map [menu-bar hol-menu hol-misc add-load-path]
   '("Add load-path ..." . hol-add-load-path))

(define-key global-map [menu-bar hol-menu hol-misc sep1]
   '(menu-item "--"))

(define-key global-map [menu-bar hol-menu hol-misc hol-type-info]
   '("Type info of marked term" . hol-type-info))

(define-key global-map [menu-bar hol-menu hol-misc sep0]
   '(menu-item "--"))

(define-key global-map [menu-bar hol-menu hol-misc db-find]
   '("DB find" . hol-db-find))

(define-key global-map [menu-bar hol-menu hol-misc db-match]
   '("DB match" . hol-db-match))



;; templates
(define-key
  global-map
  [menu-bar hol-menu hol-template]
  (cons "Templates" (make-sparse-keymap "Templates")))

(define-key global-map [menu-bar hol-menu hol-template new-script]
   '("New theory" . hol-template-new-script-file))

(define-key global-map [menu-bar hol-menu hol-template new-datatype]
   '("New datatype" . hol-template-new-datatype))

(define-key global-map [menu-bar hol-menu hol-template define]
   '("New definition" . hol-template-define))

(define-key global-map [menu-bar hol-menu hol-template store-thm]
   '("Store theorem" . hol-template-store-thm))

(define-key global-map [menu-bar hol-menu hol-template sep1]
   '(menu-item "--"))

(define-key global-map [menu-bar hol-menu hol-template comment-star]
   '("Comment *" . hol-template-comment-star))

(define-key global-map [menu-bar hol-menu hol-template comment-equal]
   '("Comment =" . hol-template-comment-equal))

(define-key global-map [menu-bar hol-menu hol-template comment-minus]
   '("Comment -" . hol-template-comment-minus))


;; printing
(define-key
  global-map
  [menu-bar hol-menu hol-printing]
  (cons "Printing switches" (make-sparse-keymap "Printing switches")))

(define-key global-map [menu-bar hol-menu hol-printing simplifier-trace]
   '("Simplifier trace" . hol-toggle-simplifier-trace))

(define-key global-map [menu-bar hol-menu hol-printing times]
   '("Show times" . hol-toggle-show-times))

(define-key global-map [menu-bar hol-menu hol-printing echo]
   '("Echo commands" . hol-toggle-echo-commands))

(define-key global-map [menu-bar hol-menu hol-printing quiet]
   '("Quiet (hide output except errors)" . hol-toggle-quietdec))

(define-key
  global-map
  [menu-bar hol-menu hol-printing backends]
  (cons "Pretty-printing backends" (make-sparse-keymap "Pretty-printing backends")))

(define-key global-map [menu-bar hol-menu hol-printing backends ppreset]
  '("Reset hol-mode pretty-printing (error recovery)" . holpp-reset))

(define-key global-map [menu-bar hol-menu hol-printing backends sep1]
   '(menu-item "--"))

(define-key global-map [menu-bar hol-menu hol-printing backends ppstyles]
  '("Toggle use styles" . hol-toggle-pp-styles))

(define-key global-map [menu-bar hol-menu hol-printing backends ppannotations]
  '("Toggle use annotations" . hol-toggle-pp-annotations))

(define-key global-map [menu-bar hol-menu hol-printing backends pptooltip]
  '("Toggle show tooltips" . hol-toggle-emacs-tooltips))

(define-key global-map [menu-bar hol-menu hol-printing backends sep2]
   '(menu-item "--"))

(define-key global-map [menu-bar hol-menu hol-printing backends ppbackend]
  '("Toggle pretty-printing backend" . hol-toggle-ppbackend))

(define-key global-map [menu-bar hol-menu hol-printing unicode]
   '("Unicode" . hol-toggle-unicode))

(define-key global-map [menu-bar hol-menu hol-printing ppcases]
  '("Toggle pretty-printing of cases" . hol-toggle-pp-cases))

(define-key global-map [menu-bar hol-menu hol-printing sep2]
   '(menu-item "--"))


(define-key global-map [menu-bar hol-menu hol-printing num-subgoals]
   '("Set no. of shown subgoals" . hol-toggle-goalstack-num-subgoals))

(define-key global-map [menu-bar hol-menu hol-printing num-assums]
   '("Set no. of shown assumptions" . hol-toggle-goalstack-num-assums))

(define-key global-map [menu-bar hol-menu hol-printing print-goal-at-top]
   '("Print goal at top" . hol-toggle-goalstack-print-goal-at-top))

(define-key global-map [menu-bar hol-menu hol-printing goal-fvs]
   '("Show free vars in goal" . hol-toggle-goalstack-fvs))

(define-key global-map [menu-bar hol-menu hol-printing sep1]
   '(menu-item "--"))


(define-key global-map [menu-bar hol-menu hol-printing show-assums]
   '("Show assumptions" . hol-toggle-show-assums))

(define-key global-map [menu-bar hol-menu hol-printing show-num-types]
   '("Show numeral types" . hol-toggle-show-numeral-types))

(define-key global-map [menu-bar hol-menu hol-printing show-types-verbosely]
   '("Show types verbosely" . hol-toggle-show-types-verbosely))

(define-key global-map [menu-bar hol-menu hol-printing show-types]
   '("Show types" . hol-toggle-show-types))





;; HOL goals
(define-key
  global-map
  [menu-bar hol-menu hol-goalstack]
  (cons "Goalstack" (make-sparse-keymap "Goalstack")))


(define-key global-map [menu-bar hol-menu hol-goalstack apply-tactic-goaltree]
   '("Apply tactic (goaltree)" . copy-region-as-goaltree-tactic))

(define-key global-map [menu-bar hol-menu hol-goalstack new-goaltree]
   '("New goaltree" . hol-do-goaltree))

(define-key global-map [menu-bar hol-menu hol-goalstack sep3]
   '(menu-item "--"))

(define-key global-map [menu-bar hol-menu hol-goalstack restart-goal]
   '("Restart goal" . hol-restart-goal))

(define-key global-map [menu-bar hol-menu hol-goalstack drop-all]
   '("Drop all goals" . hol-drop-all-goals))

(define-key global-map [menu-bar hol-menu hol-goalstack drop-goal]
   '("Drop goal" . hol-drop-goal))

(define-key global-map [menu-bar hol-menu hol-goalstack sep1]
   '(menu-item "--"))

(define-key global-map [menu-bar hol-menu hol-goalstack print-all]
   '("Print all goals" . hol-print-all-goals))

(define-key global-map [menu-bar hol-menu hol-goalstack print-top]
   '("Print goal" . hol-print-goal))

(define-key global-map [menu-bar hol-menu hol-goalstack sep0]
   '(menu-item "--"))

(define-key global-map [menu-bar hol-menu hol-goalstack top-thm]
   '("Name top theorem" . hol-name-top-theorem))

(define-key global-map [menu-bar hol-menu hol-goalstack subgoal-tac]
   '("Subgoal tactic" . hol-subgoal-tactic))

(define-key global-map [menu-bar hol-menu hol-goalstack rotate]
   '("Rotate" . hol-rotate))

(define-key global-map [menu-bar hol-menu hol-goalstack back-up-user]
   '("Restore" . hol-user-backup))

(define-key global-map [menu-bar hol-menu hol-goalstack back-up-save-user]
   '("Save" . hol-user-save-backup))

(define-key global-map [menu-bar hol-menu hol-goalstack back-up]
   '("Back up" . hol-backup))

(define-key global-map [menu-bar hol-menu hol-goalstack apply-tactic]
   '("Apply tactic" . copy-region-as-hol-tactic))

(define-key global-map [menu-bar hol-menu hol-goalstack new-goal]
   '("New goal" . hol-do-goal))



;;process
(define-key
  global-map
  [menu-bar hol-menu hol-process]
  (cons "Process" (make-sparse-keymap "Process")))

(define-key global-map [menu-bar hol-menu hol-process hol-scroll-down]
   '("Scroll down" . hol-scroll-down))

(define-key global-map [menu-bar hol-menu hol-process hol-scroll-up]
   '("Scroll up" . hol-scroll-up))

(define-key global-map [menu-bar hol-menu hol-process hol-recentre]
   '("Recentre" . hol-recentre))

(define-key global-map [menu-bar hol-menu hol-process sep2]
   '(menu-item "--"))

(define-key global-map [menu-bar hol-menu hol-process hol-send-string]
   '("Send string to HOL" . interactive-send-string-to-hol))

(define-key global-map [menu-bar hol-menu hol-process hol-send-region-quietly]
   '("Send region to HOL - hide non-errors" . copy-region-as-hol-definition-quitely))

(define-key global-map [menu-bar hol-menu hol-process hol-send-region]
   '("Send region to HOL" . copy-region-as-hol-definition))

(define-key global-map [menu-bar hol-menu hol-process sep1]
   '(menu-item "--"))

(define-key global-map [menu-bar hol-menu hol-process hol-exe]
   '("Set HOL executable" . hol-set-executable))

(define-key global-map [menu-bar hol-menu hol-process hol-kill]
   '("Kill HOL" . hol-kill))

(define-key global-map [menu-bar hol-menu hol-process hol-interrupt]
   '("Interrupt HOL" . hol-interrupt))

(define-key global-map [menu-bar hol-menu hol-process sep02]
   '(menu-item "--"))

(define-key global-map [menu-bar hol-menu hol-process holmake]
   '("Run Holmake" . holmake))

(define-key global-map [menu-bar hol-menu hol-process sep01]
   '(menu-item "--"))

(define-key global-map [menu-bar hol-menu hol-process hol-display]
   '("Display HOL buffer" . hol-display))

(define-key global-map [menu-bar hol-menu hol-process hol-start-vertical]
   '("Start HOL - vertical split" . hol-vertical))

(define-key global-map [menu-bar hol-menu hol-process hol-start-horizontal]
   '("Start HOL - horizontal split" . hol-horizontal))

(define-key global-map [menu-bar hol-menu hol-process hol-start]
   '("Start HOL" . hol))
