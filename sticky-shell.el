;;; sticky-shell.el --- Minor mode to keep track of previous prompt in your shell  -*- lexical-binding: t; -*-

;; Copyright (C) 2022  Andrew De Angelis

;; Author: Andrew De Angelis <bobodeangelis@gmail.com>
;; Maintainer: Andrew De Angelis <bobodeangelis@gmail.com>
;; URL: https://github.com/andyjda/sticky-shell
;; Version: 1.0.0
;; Package-Requires: ((emacs "25.1"))
;; Keywords: processes, terminals, tools

;; This program is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with this program.  If not, see <https://www.gnu.org/licenses/>.

;;; Commentary:

;; This package provides a minor mode that creates a header in a shell buffer.
;; The header shows a previous prompt according to the value of
;; `sticky-shell-get-prompt'.
;; This is most useful when working with many lines of output:
;; setting `sticky-shell-get-prompt' to `sticky-shell-prompt-above-visible'
;; will ensure that the command corresponding to the top output-line
;; is always visible.

;;; Code:
(eval-when-compile
  (require 'eshell)
  (require 'comint))

(declare-function eshell-previous-prompt "ext:eshell")
(declare-function comint-previous-prompt "ext:comint")

(defgroup sticky-shell nil
  "Display a sticky header with latest shell-prompt."
  :group 'terminals)


(defcustom sticky-shell-get-prompt
  #'sticky-shell-prompt-above-visible
  "Function used by `sticky-shell-mode' to pick the prompt to show in the header.
Available values are: `sticky-shell-latest-prompt',
`sticky-shell-prompt-above-visible',
`sticky-shell-prompt-above-cursor',
`sticky-shell-prompt-before-cursor'
or you can write your own function and assign it to this variable."
  :group 'sticky-shell
  :type 'function)

(defface sticky-shell-shorten-header-ellipsis
  '((t :inherit default))
  "Face used for the ellipsis shortening the sticky-shell header."
  :group 'sticky-shell)

;;;; helper functions
(defun sticky-shell-current-line-trimmed ()
  "Return the current line and remove trailing whitespace."
  (let ((prompt (or (thing-at-point 'line) "")))
    ;; remove whitespace at the end of the line:
    (string-trim-right prompt "[ \t\n\r]+")))

(defun sticky-shell-previous-prompt (n)
  "Move to end of Nth previous prompt in the buffer.
Depending on the current mode, call `comint-previous-prompt'
or `eshell-previous-prompt'."
  (if (derived-mode-p 'eshell-mode)
      (eshell-previous-prompt n)
    (comint-previous-prompt n)))

;;;; get prompt
(defun sticky-shell-latest-prompt ()
  "Get the latest prompt that was run."
  (interactive)
  (save-excursion
    (goto-char (point-max))
    (forward-line -1)
    (sticky-shell-previous-prompt 1)
    (sticky-shell-current-line-trimmed)))

(defun sticky-shell-prompt-above-visible ()
  "Get the prompt above the top visible line in the current window.
This ensures that the prompt in the header corresponds to top output-line"
  (interactive)
  (save-excursion
    (goto-char (window-start))
    (sticky-shell-previous-prompt 1)
    (sticky-shell-current-line-trimmed)))

(defun sticky-shell-prompt-above-cursor ()
  "Get the prompt above the cursor's current line."
  (interactive)
  (save-excursion
    (move-beginning-of-line 1)
    (sticky-shell-previous-prompt 1)
    (sticky-shell-current-line-trimmed)))

;;;; shorten header
(defun sticky-shell-fit-within-line (header)
  "Shorten HEADER, ensuring its beginning and end are visible within the line.
The shortening logic is:
 - if the header already fits in the available space in the line:
   don't do anything
 - else:
 - get the difference between the header and the `window-max-chars-per-line'
 - divide the header in two
 - from each header-half, remove half of the difference (in characters)
 - now our header fits the line
 - add an ellipsis (\"...\") between the two halves
 - remove three chars from the second half to make room for the ellipsis
The \"...\" is propertized with the face `sticky-shell-shorten-header-ellipsis'"
  (let* ((max-chars-per-line (window-max-chars-per-line))
         (header-length (length header))
         (diff (- header-length max-chars-per-line)))
    (if (<= diff 0)
        header
      (format "%s%s%s"
              ;; first half of the header, minus half the difference
              (seq-take header
                        (- (/ header-length 2)
                           (/ diff 2)))
              (propertize "..." 'face 'sticky-shell-shorten-header-ellipsis)
              ;; second half of the header, minus half the difference
              ;; and making room for the three dots
              (seq-drop header
                        (+ (+ (/ (length header) 2)
                              (/ diff 2))
                           3))))))

(defun sticky-shell-shorten-header ()
  "Apply `sticky-shell-fit-within-line' to `header-line-format'.
`header-line-format' should look like this:
\(:eval (funcall sticky-shell-get-prompt)),
so we take the part after `eval'
and wrap it within `sticky-shell-fit-within-line'"
  (let ((header-function (cadr header-line-format)))
    (setq-local header-line-format
                `(:eval (sticky-shell-fit-within-line ,header-function)))))


(defun sticky-shell-restore-header ()
  "Remove `sticky-shell-fit-within-line' from `header-line-format'."
  (when (eq (caadr header-line-format) #'sticky-shell-fit-within-line)
    (let ((header-function (cadadr header-line-format)))
      (setq-local header-line-format
                  `(:eval ,header-function)))))

(define-minor-mode sticky-shell-shorten-header-mode
  "Minor mode to shorten the header, making the beginning and end both visible."
  :group 'sticky-shell
  :global nil
  :lighter nil
  (if (bound-and-true-p sticky-shell-mode)
      (if sticky-shell-shorten-header-mode
          (sticky-shell-shorten-header)
        (sticky-shell-restore-header))
    (progn
      (message
       "Cannot enable `sticky-shell-shorten-header-mode' while `sticky-shell-mode' is disabled")
      (setq-local sticky-shell-shorten-header-mode nil))))


;;;###autoload
(define-minor-mode sticky-shell-mode
  "Minor mode to show the previous prompt as a sticky header.
Which prompt to pick depends on the value of `sticky-shell-get-prompt'."
  :group 'comint
  :global nil
  :lighter nil
  (if sticky-shell-mode
      (setq-local header-line-format
                  '(:eval ; question: why do we use :eval instead of `eval' here??
                    (funcall sticky-shell-get-prompt)))
    (setq-local header-line-format nil
                sticky-shell-shorten-header-mode nil)))

(provide 'sticky-shell)
;;; sticky-shell.el ends here
