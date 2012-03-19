;;; emstar.el --- Emstar Game

;; Version: 1.4
;; Copyright
;; © Gwenhael Le Moine

;; Author: Gwenhael Le Moine <gwenhael.le.moine@gmail.com>
;; Keywords: games
;; URL: https://github.com/cycojesus/emstar

;; This file is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation; either version 3, or (at your option)
;; any later version.

;; This file is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with GNU Emacs; see the file COPYING.  If not, write to
;; the Free Software Foundation, Inc., 59 Temple Place - Suite 330,
;; Boston, MA 02111-1307, USA.

;;; Commentary:

;; Play Emstar in emacs.
;; Heavily based on emacs-sokoban

;; (require 'emstar)

;;; Code:

(require 'cl)

(defconst emstar-left  '(-1 .  0))
(defconst emstar-right '( 1 .  0))
(defconst emstar-down  '( 0 .  1))
(defconst emstar-up    '( 0 . -1))
(defconst emstar-eater   "eater")
(defconst emstar-stopper "stopper")

(defgroup emstar nil
  "Emstar game for GNU Emacs."
  :prefix "emstar-"
  :group 'games)

(defcustom emstar-playerfiles-dir "/tmp/"
  "*The directory holding the emstar playerfiles.
Emstar saves the information from `emstar-player-stats' to a
playerfile in this directory.  If you don't want to use
playerfiles, set value to NIL."
  :group 'emstar
  :type 'string)

(defvar emstar-player-stats nil
  "Alist with player specific information as saved in the playerfiles.
This holds the best results for each finished level and the
players current level.")

(defconst emstar-playerfile-prefix "emstar-pl-"
  "The prefix used for emstar playerfiles.")

(defvar emstar-best-players-list nil
  "A list with the best result for each level
generated from all available playerfiles, if `emstar-playerfiles-dir'
is none nil.")

(defcustom emstar-levels-dir (concat (file-name-directory load-file-name) "/emstar-levels")
  "*Directory holding the emstar level files"
  :group 'emstar
  :type 'string)

(defcustom emstar-levels-basename "emstar-lvl."
  "*Basename of the emstar level files"
  :group 'emstar
  :type 'string)

(defcustom emstar-start-level 1
  "*Defines the level-numver to start with.
This might be overwritten by the last level played,
as saved in the playerfile."
  :group 'emstar
  :type 'integer)

(defcustom emstar-undo-penalty 3
  "*Defines distance penatly for one undo."
  :group 'emstar
  :type 'integer)

(defvar emstar-eater-char ?@)
(defvar emstar-gift-char ?*)
(defvar emstar-stopper-char ?H)
(defvar emstar-wall-char ?#)

;; (defcustom emstar-eater-char ?@
;;   "*Defines the character used to diplay the eater."
;;   :group 'emstar
;;   :type 'character)

;; (defcustom emstar-gift-char ?*
;;   "*Defines the character used to diplay the gifts."
;;   :group 'emstar
;;   :type 'character)

;; (defcustom emstar-stopper-char ?H
;;   "*Defines the character used to diplay the stopper."
;;   :group 'emstar
;;   :type 'character)

;; (defcustom emstar-wall-char ?#
;;   "*Defines the character used to diplay the walls."
;;   :group 'emstar
;;   :type 'character)

(defface emstar-eater-face
  '((t (:foreground "green"
    :weight  bold)))
  "*Face used display the eater in emstar game."
  :group 'emstar)

(defface emstar-stopper-face
  '((t (:foreground "red"
    :weight  bold)))
  "*Face used display the stopper in emstar game."
  :group 'emstar)

(defface emstar-gift-face
  '((t (:foreground "yellow"
    :weight  bold)))
  "*Face used display gifts in emstar game."
  :group 'emstar)

(defface emstar-wall-face
  '((t (:foreground "black")))
  "*Face used display walls in emstar game."
  :group 'emstar)

(defvar emstar-eater-face 'emstar-eater-face)
(defvar emstar-stopper-face 'emstar-stopper-face)
(defvar emstar-gift-face 'emstar-gift-face)
(defvar emstar-wall-face 'emstar-wall-face)

(defconst emstar-font-lock-keywords
  `((,(regexp-quote (char-to-string emstar-eater-char))
     . emstar-eater-face)
    (,(regexp-quote (char-to-string emstar-stopper-char))
     . emstar-stopper-face)
    (,(regexp-quote (char-to-string emstar-gift-char))
     . emstar-gift-face)
    (,(regexp-quote (char-to-string emstar-wall-char))
     . emstar-wall-face))
  "Stuff to highlight in emstar.")

(defvar emstar-mode-map nil
  "Keymap for emstar.")
(defvar emstar-selected 'emstar-eater
  "Currently selected piece.")
(setq emstar-mode-map (make-sparse-keymap))
(define-key emstar-mode-map [up]    'emstar-move-up)
(define-key emstar-mode-map [down]  'emstar-move-down)
(define-key emstar-mode-map [left]  'emstar-move-left)
(define-key emstar-mode-map [right] 'emstar-move-right)
(define-key emstar-mode-map "u"     'emstar-undo)
(define-key emstar-mode-map "b"     'emstar-display-best-players-list)
(define-key emstar-mode-map ">"     'emstar-goto-next-level)
(define-key emstar-mode-map "n"     'emstar-goto-next-level)
(define-key emstar-mode-map "<"     'emstar-goto-prev-level)
(define-key emstar-mode-map "p"     'emstar-goto-prev-level)
(define-key emstar-mode-map " "     'emstar-switch-selected)
(define-key emstar-mode-map "r"     'emstar-reload-level)

(defvar emstar-collected-gifts 0
  "Number of gifts collected.  Buffer-local in emstar-mode.")
(defvar emstar-total-gifts 0
  "Total number of gifts.  Buffer-local in emstar-mode.")

(defvar emstar-level nil
  "Number of current level.  Buffer-local in emstar games.")
(defvar emstar-distance nil
  "Distance travelled by player.  Buffer-local in emstar-mode.")
(defvar emstar-pos nil
  "Current position of player.  Buffer-local in emstar-mode.")
(defvar emstar-last-pos nil
  "Backup of last player position.  Buffer-local in emstar-mode.")
(defvar emstar-game-info nil
  "String with infos to the current game.  Buffer-local in emstar-mode.")
(defvar emstar-level-best-string nil
  "String holding the best result for the current level as displayed.")

(defun emstar-forward-line (arg)
  "Like forward-line but preserve the current column.
The implementation is rather simple, as we can make certain
assumptions about the structure of a valid emstar level buffer."
  (let ((goal-column (current-column)))
    (forward-line arg)
    (move-to-column goal-column)))

(defun emstar-paint (char)
  "Insert char at point, overwriting the old char.
Extreme simple, but sufficient for our needs."
  (let ((inhibit-read-only t))
    (delete-char 1)
    (insert (char-to-string char))
    (forward-char -1))
  t)

(defun emstar-count-gifts ()
  (setq emstar-total-gifts 0)
  (goto-char (point-min))
  (while (search-forward (char-to-string emstar-gift-char) nil t)
    (setq emstar-total-gifts (1+ emstar-total-gifts))))

(defun emstar-refresh-collected-gifts ()
  (setq emstar-collected-gifts 0)
  (goto-char (point-min))
  (while (search-forward (char-to-string emstar-gift-char) nil t)
    (setq emstar-collected-gifts (1+ emstar-collected-gifts)))
  (setq emstar-collected-gifts (- emstar-total-gifts emstar-collected-gifts )))

(defun emstar-update-score (level distance)
  "Save the distance travelled for level to `emstar-player-stats'."
  (let* ((level-name (concat emstar-levels-basename
                 (number-to-string level)))
     (entry (assoc level-name emstar-player-stats)))
    (if entry
    (or (< (cdr entry) distance) (setcdr entry distance))
      (push (cons level-name distance) emstar-player-stats))))

(defun emstar-get-level-best (level &optional list)
  "Get best result for level from `emstar-player-stats'."
  (if level
      (let* ((level-name (concat emstar-levels-basename
                 (number-to-string level)))
         (entry (assoc level-name
               (or list emstar-player-stats))))
    (if entry
        (cdr entry)))))

(defun emstar-update-current-level (level)
  "Save current level to `emstar-player-stats'."
  (let ((entry (assoc :level emstar-player-stats)))
    (if entry
    (setcdr entry level)
      (push (cons :level level) emstar-player-stats))))

(defun emstar-save-playerfile ()
  "Save `emstar-player-stats' to playerfile."
  (if emstar-playerfiles-dir
      (let ((filename (concat emstar-playerfiles-dir "/"
                  emstar-playerfile-prefix
                  (user-login-name))))
    (with-temp-file filename
      (prin1 emstar-player-stats (current-buffer)))
    (set-file-modes filename #o644))))

(defun emstar-load-playerfile ()
  "Load `emstar-player-stats' from playerfile."
  (if emstar-playerfiles-dir
      (let ((filename (concat emstar-playerfiles-dir "/"
                  emstar-playerfile-prefix
                  (user-login-name))))
    (if (file-readable-p filename)
        (with-temp-buffer
          (insert-file-contents filename nil)
          (setq emstar-player-stats
            (read (current-buffer))))))))

(defun emstar-gen-best-players-list ()
  (if emstar-playerfiles-dir
      (let ((files (directory-files emstar-playerfiles-dir
                    t (concat "^" emstar-playerfile-prefix)
                    t)))
    (dolist (filename files)
      (if (file-readable-p filename)
          (with-temp-buffer
        (insert-file-contents filename nil)
        (let ((stats (read (current-buffer)))
              (player (substring (file-name-nondirectory filename)
                     (1- (length emstar-levels-basename)))))
          (dolist (entry stats)
            (let* ((level-name  (car entry))
               (best-entry (assoc level-name
                          emstar-best-players-list)))
              (if (and (stringp level-name)
               (compare-strings level-name
                        0 (length emstar-levels-basename)
                        emstar-levels-basename
                        0 nil))
              (cond ((and best-entry
                      (> (cadr best-entry) (cdr entry)))
                 (setcdr best-entry
                     (cons (cdr entry) player)))
                ((or (not best-entry)
                     (= (cadr best-entry) (cdr entry)))
                 (push (cons level-name
                         (cons (cdr entry) player))
                       emstar-best-players-list)))))))))))))


(defun emstar-display-best-players-list ()
  (interactive)
  (if emstar-best-players-list
      (progn
    (switch-to-buffer (get-buffer-create "*Emstar Best Players*"))
    (erase-buffer)
    (dolist (entry emstar-best-players-list)
      (let ((level-name (car entry)))
        (if (and (stringp level-name)
             (compare-strings level-name
                      0 (length emstar-levels-basename)
                      emstar-levels-basename
                      0 nil))
        (insert (format "%4s: %5d - %s\n"
                (substring level-name
                       (length emstar-levels-basename))
                (cadr entry)
                (cddr entry))))))
    (sort-columns nil (point-min) (point-max)))
    (error "No best players list available")))

(defun emstar-load-next-level (&optional arg)
  "Load next level, with negative arg load previous level.
If requested level doesn't exist, load `emstar-start-level'."
  (when (bound-and-true-p emstar-level)
    (setq emstar-level (if (and arg (< arg 0))
                           (1- emstar-level)
                         (1+ emstar-level)))
    (or (emstar-load-level emstar-level)
    (progn
      (setq emstar-level emstar-start-level)
      (emstar-load-level emstar-level)))
    (emstar-init-level)
    t))

(defun emstar-level-finished ()
  (message
   (format "You finished Level %d in %d meters.  Congratulations!"
           (or (bound-and-true-p emstar-level) 0)
           emstar-distance))
  (when (bound-and-true-p emstar-level)
    (emstar-update-score emstar-level emstar-distance))
  (when (emstar-load-next-level)
    (emstar-update-current-level emstar-level)
    (emstar-save-playerfile)))

(defun emstar-find-current-pos ()
  (goto-char (point-min))
  (search-forward (char-to-string (if (equal emstar-selected emstar-eater)
      emstar-eater-char
      emstar-stopper-char)))
  (forward-char -1)
  (setq emstar-pos (point)))

(defun emstar-move-here ()
  "Move player to point.
Move player char to point and evaluate game status."
  (interactive)
  (setq emstar-pos (point))
  (emstar-paint (if (equal emstar-selected emstar-eater)
      emstar-eater-char
      emstar-stopper-char))
  (goto-char emstar-last-pos)
  (emstar-paint 32)
  (emstar-update-mode-line))

(defun emstar-move-eater (direction)
  (goto-char emstar-pos)
  (setq emstar-last-pos (point))
  (while (progn
           (setq emstar-pos (point))
           (forward-char (car direction))
           (emstar-forward-line (cdr direction))
           (if (= (char-after) emstar-gift-char)
               (progn
                 (setq emstar-collected-gifts (1+ emstar-collected-gifts))
                 (emstar-paint 32)))
		   (setq emstar-distance (1+ emstar-distance))
		   (= (char-after) 32)))
  (setq emstar-distance (1- emstar-distance))
  (goto-char emstar-pos)
  (if (or
       (= (char-after) 32)
       (= (char-after) emstar-gift-char))
      (emstar-move-here))
  (if (= emstar-total-gifts emstar-collected-gifts)
      (emstar-level-finished)))

(defun emstar-move-stopper (direction)
  (goto-char emstar-pos)
  (setq emstar-last-pos (point))
  (while (progn
           (setq emstar-pos (point))
           (forward-char (car direction))
           (emstar-forward-line (cdr direction))
		   (setq emstar-distance (1+ emstar-distance))
           (= (char-after) 32)))
  (setq emstar-distance (1- emstar-distance))
  (goto-char emstar-pos)
  (if (= (char-after) 32)
      (emstar-move-here)))


(defun emstar-move-up ()
  "Move the player up if possible."
  (interactive)
  (if (equal emstar-selected emstar-eater)
      (emstar-move-eater emstar-up)
      (emstar-move-stopper emstar-up)))

(defun emstar-move-down ()
  "Move the player down if possible."
  (interactive)
  (if (equal emstar-selected emstar-eater)
      (emstar-move-eater emstar-down)
      (emstar-move-stopper emstar-down)))

(defun emstar-move-left ()
  "Move the player left if possible."
  (interactive)
  (if (equal emstar-selected emstar-eater)
      (emstar-move-eater emstar-left)
      (emstar-move-stopper emstar-left)))

(defun emstar-move-right ()
  "Move the player right if possible."
  (interactive)
  (if (equal emstar-selected emstar-eater)
      (emstar-move-eater emstar-right)
      (emstar-move-stopper emstar-right)))

(defun emstar-goto-next-level ()
  "Jump to next level."
  (interactive)
  (emstar-load-next-level))

(defun emstar-goto-prev-level ()
  "Jump to previous level."
  (interactive)
  (emstar-load-next-level -1))

(defun emstar-reload-level ()
  "Jump to previous level."
  (interactive)
  (emstar-load-level emstar-level)
  (emstar-init-level))

(defun emstar-switch-selected ()
  "Switch the item moved."
  (interactive)
  (setq emstar-selected (if (equal emstar-selected emstar-eater)
      emstar-stopper
      emstar-eater))
  (if (equal emstar-selected emstar-eater)
      (progn
        (set-face-inverse-video-p emstar-eater-face t)
        (set-face-inverse-video-p emstar-stopper-face nil))
      (progn
        (set-face-inverse-video-p emstar-eater-face nil)
        (set-face-inverse-video-p emstar-stopper-face t)))
  (emstar-find-current-pos))

(defun emstar-update-mode-line ()
  (setq emstar-game-info (format "Level: %d -- Gifts collected: %d/%d -- Distance: %d %s"
                                 (or (bound-and-true-p emstar-level)
                                     0)
                                 emstar-collected-gifts
                                 emstar-total-gifts
                                 emstar-distance
                                 (or emstar-level-best-string ""))))

(defun emstar-undo ()
  (interactive)
  (let ((inhibit-read-only t))
    (undo))
  (emstar-find-current-pos)
  (setq emstar-distance (+ emstar-distance emstar-undo-penalty))
  (emstar-refresh-collected-gifts)
  (emstar-update-mode-line))

(defun emstar-load-level (num)
  "Load emstar level num."
  (let ((inhibit-read-only t)
    (level-file
     (concat emstar-levels-dir "/"
         emstar-levels-basename (number-to-string num))))
    (when (file-exists-p level-file)
      (insert-file-contents level-file nil nil nil t)
      t)))

(defun emstar-init-level ()
  "Initialize level elements."
  (setq emstar-selected emstar-eater)
  (set-face-inverse-video-p emstar-eater-face t)
  (set-face-inverse-video-p emstar-stopper-face nil)
  (setq emstar-distance 0)
  (setq emstar-collected-gifts 0)
  (setq emstar-total-gifts 0)
  (setq emstar-level-best-string
    (let ((best (emstar-get-level-best emstar-level))
          (world-best (if emstar-best-players-list
                  (emstar-get-level-best
                   emstar-level
                   emstar-best-players-list))))
      (if (or best world-best)
          (format " [Best:%s%s]"
              (if best (number-to-string best) "")
              (if (and world-best
                   (or (not best)
                   (< (car world-best) best)))
              (format " (%s:%d)"
                  (cdr world-best) (car world-best))
              "")))))
  (emstar-count-gifts)
  (emstar-update-mode-line)
  (emstar-find-current-pos)
  (buffer-disable-undo (current-buffer))
  (buffer-enable-undo)
)
;;;###autoload
(defun emstar-mode ()
  "Major mode to play emstar.

Commands:
\\{emstar-mode-map}"
  (interactive)
  (kill-all-local-variables)
  (toggle-read-only 1)
  (use-local-map emstar-mode-map)
  (make-local-variable 'font-lock-defaults)
  (setq font-lock-defaults '(emstar-font-lock-keywords
                 t nil nil beginning-of-line))
  (setq cursor-type nil)
  (make-local-variable 'emstar-level)
  (make-local-variable 'emstar-pos)
  (make-local-variable 'emstar-last-pos)
  (make-local-variable 'emstar-distance)
  (make-local-variable 'emstar-collected-gifts)
  (make-local-variable 'emstar-total-gifts)
  (make-local-variable 'emstar-game-info)
  (setq major-mode 'emstar-mode)
  (setq mode-name "Emstar")
  (setq header-line-format
    (list "Emstar -- " 'emstar-game-info " ~ " 'emstar-selected))
  (emstar-init-level)
  (run-hooks 'emstar-mode-hook))

;;;###autoload
(defun emstar ()
  "Play emstar."
  (interactive)
  (switch-to-buffer (generate-new-buffer "*Emstar*"))
  (emstar-load-playerfile)
  (setq emstar-best-players-list nil)
  (emstar-gen-best-players-list)
  (let ((level (or (cdr (assoc :level emstar-player-stats))
           emstar-start-level)))
    (emstar-load-level level)
    (emstar-mode)
    (setq emstar-level level))
  (emstar-init-level)
  (emstar-update-mode-line))

(provide 'emstar)
;;; emstar.el ends here
