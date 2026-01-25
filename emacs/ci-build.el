;; ci-build.el --- build static site in CI  -*- lexical-binding: t; -*-
;;; Commentary:
;; Prepares Emacs for the website-publish ci job
;; ox-rss is required for publishing the rss file

;;; Code:
(require 'package)
(setq package-user-dir (expand-file-name ".cache/elpa" default-directory))
(setq package-archives
      '(("gnu"   . "https://elpa.gnu.org/packages/")
        ("nongnu". "https://elpa.nongnu.org/nongnu/")
        ("melpa" . "https://melpa.org/packages/")))
(package-initialize)

(unless (package-installed-p 'ox-rss)
  (package-refresh-contents)
  (package-install 'ox-rss))

;; Cleanup build dir
(when (file-directory-p (expand-file-name "site" default-directory))
  (delete-directory (expand-file-name "site" default-directory) t))
(make-directory (expand-file-name "site" default-directory) t)

(load-file (expand-file-name "emacs/website-publish.el" default-directory))

(condition-case err
    (progn
      (org-publish "website" t)
      (message "Build done. Output in %s" (expand-file-name "site" default-directory))
      (kill-emacs 0))
  (error
   (message "Build failed: %s" (error-message-string err))
   (kill-emacs 1)))

(provide 'ci-build)
;;; ci-build.el ends here
