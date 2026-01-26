;;; website-publish.el --- org-publish config -*- lexical-binding: t; -*-

;;; Commentary:
;; Static site generator with blog and RSS.
;; Customize my/site-url and my/rss-avatar-url.

;;; Code:

;;;; Dependencies
(require 'ox-publish)
(require 'ox-rss)
(require 'subr-x)

(setq user-full-name "DrDos")
(setq user-mail-address "simon@dr-dos.org")

;;;; Site Root Detection

(defvar my/site-root-cache nil
  "Cached site root.")

(defun my/site-root ()
  "Return cached site root."
  (or my/site-root-cache
      (setq my/site-root-cache
            (let ((root (locate-dominating-file default-directory "template.html")))
              (if root
                  (file-name-as-directory (expand-file-name root))
                (error "template.html not found (started from %s)" default-directory))))))

(defun my/site-root-reset ()
  "Clear cached root directory."
  (interactive)
  (setq my/site-root-cache nil)
  (when (called-interactively-p 'any)
    (message "Site root cache cleared")))

(defun my/site-path (sub)
  "Return absolute path of SUB inside website root."
  (expand-file-name sub (my/site-root)))

;;; Configuration

(defcustom my/site-url "https://www.dr-dos.org"
  "Base URL (no trailing slash)."
  :type 'string
  :group 'org-export-publish)

(defcustom my/rss-avatar-url "https://www.dr-dos.org/rss-avatar.png"
  "Avatar URL for RSS feed."
  :type 'string
  :group 'org-export-publish)

(defconst my/blog-path "/blog/blog.html")
(defconst my/posts-dir "posts/")

;;;; Global Export Parameters

(setq org-html-doctype "html5")
(setq org-html-html5-fancy t)
(setq org-html-scripts "")
(setq org-export-with-toc nil)
(setq org-html-validation-link nil)

;;;; HTML Template System

(defun my/html-template (output backend info)
  "Wrap OUTPUT in template.html, substituting placeholders."
  (if (eq backend 'html)
      (let* ((template-file (my/site-path "template.html"))
             (title (org-export-data (plist-get info :title) info))
             (description (or (plist-get info :description) ""))
             (year (format-time-string "%Y"))
             (lang (or (plist-get info :language) "en"))
             (tags (when-let ((filetags (plist-get info :filetags)))
                     (let ((tag-list (if (stringp filetags)
                                         (split-string filetags)
                                       filetags)))
                       (mapconcat (lambda (tag)
                                    (format "<a class=\"tag\" href=\"%s#%s\">#%s</a>"
                                            my/blog-path tag tag))
                                  tag-list " ")))))
        (with-temp-buffer
          (insert-file-contents template-file)
          (goto-char (point-min))
          (while (re-search-forward "{{\\(title\\|description\\|year\\|tags\\|lang\\|contents\\)}}" nil t)
            (replace-match
             (pcase (match-string 1)
               ("title" title)
               ("description" description)
               ("year" year)
               ("lang" lang)
               ("tags" (or tags ""))
               ("contents" output))
             nil t))
          (buffer-string)))
    output))
(add-to-list 'org-export-filter-final-output-functions #'my/html-template)

;;;; Blog Index Formatting

(defun my/extract-description (file-path)
  "Extract #+DESCRIPTION from FILE-PATH."
  (when (file-exists-p file-path)
    (with-temp-buffer
      (insert-file-contents file-path)
      (goto-char (point-min))
      (when (re-search-forward "^#\\+DESCRIPTION:[ \\t]+\\(.*\\)$" nil t)
        (match-string 1)))))

(defun my/sitemap-entry (entry _style project)
  "Format sitemap ENTRY."
  (let* ((base-dir   (or (org-publish-property :base-directory project)
                       default-directory))
         (abs-entry  (expand-file-name entry base-dir))
         (filename   (file-name-nondirectory entry))
         (link       (concat my/posts-dir filename))
         (title      (org-publish-find-title entry project))
         (date       (org-publish-find-date  entry project))
         (description (my/extract-description abs-entry)))
    (format "%s [[file:%s][%s]] – %s"
            (format-time-string "%Y-%m-%d" date)
            link title (or description ""))))

;;;; Plain-Text Export with ANSI Colors

(defun my/add-ansi-colors (filename)
  "Add ANSI escape codes to FILENAME (bold, italic, underline)."
  (with-temp-buffer
    (insert-file-contents filename)
    (goto-char (point-min))
    (while (re-search-forward "\\*\\*\\([^*]+\\)\\*\\*" nil t)
      (replace-match (concat "\e[1m" (match-string 1) "\e[0m") nil t))
    (goto-char (point-min))
    (while (re-search-forward "//\\([^/]+\\)//" nil t)
      (replace-match (concat "\e[3m" (match-string 1) "\e[0m") nil t))
    (goto-char (point-min))
    (while (re-search-forward "__\\([^_]+\\)__" nil t)
      (replace-match (concat "\e[4m" (match-string 1) "\e[0m") nil t))
    (write-region (point-min) (point-max) filename)))

(defun my/org-ascii-publish-with-ansi (plist filename pub-dir)
  "Publish to ASCII, then add ANSI codes."
  (let ((outfile (org-ascii-publish-to-ascii plist filename pub-dir)))
    (my/add-ansi-colors outfile)
    outfile))

(defun my/sitemap-with-intro (title list)
  "Generate blog index with TITLE and LIST of posts."
  (concat
   "#+TITLE: " title "\n\n "
   "Welcome to my blog – here you'll find all posts. "
   (format "RSS feed: [[file:%sblog-rss.xml][XML]]\n\n  " my/posts-dir)
   (org-list-to-org list)))

;;;; RSS Feed Generation

(defun my/rss-sitemap-entry (entry _style project)
  "Format ENTRY as RSS headline."
  (let* ((base-dir (or (org-publish-property :base-directory project)
                      default-directory))
         (abs-entry (expand-file-name entry base-dir))
         (filename (file-name-nondirectory entry))
         (title (org-publish-find-title entry project))
         (date (org-publish-find-date entry project))
         (description (my/extract-description abs-entry)))
    (format "* %s
:PROPERTIES:
:RSS_PERMALINK: %s
:PUBDATE: %s
:END:
%s"
            title
            (file-name-sans-extension filename)
            (format-time-string "<%Y-%m-%d>" date)
            (or description ""))))

(defun my/rss-sitemap-function (_title list)
  "Generate RSS sitemap from LIST."
  (let ((entries (cdr list))
        (output "#+TITLE: DrDos' Blog
#+DESCRIPTION: DrDos' personal blog about IT, security and more.

"))
    (dolist (entry entries output)
      (let ((entry-str (cond
                        ((stringp entry) entry)
                        ((consp entry) (if (stringp (cdr entry))
                                          (cdr entry)
                                        (car entry)))
                        (t (format "%s" entry)))))
        (setq output (concat output entry-str "\n\n"))))))

;;;; Publishing Project Configuration

(defun my/setup-publish-alist ()
  "Set up org-publish-project-alist for current website root."
  (interactive)
  (setq org-publish-project-alist
        `(("pages"
           :base-directory ,(my/site-path "src")
           :base-extension "org"
           :exclude "blog/posts/.*"
           :publishing-directory ,(my/site-path "site")
           :recursive t
           :publishing-function org-html-publish-to-html
           :with-timestamp nil
           :body-only t
           :with-author nil)

          ("posts"
           :base-directory ,(my/site-path "src/blog/posts")
           :publishing-directory ,(my/site-path "site/blog/posts")
           :base-extension "org"
           :recursive t
           :publishing-function org-html-publish-to-html
           :with-timestamp nil
           :body-only t
           :with-author nil
           :section-numbers nil
           :auto-sitemap t
           :sitemap-filename "../blog.org"
           :sitemap-title "Blog"
           :sitemap-sort-files anti-chronologically
           :sitemap-format-entry my/sitemap-entry
           :sitemap-function my/sitemap-with-intro)

          ("rss"
           :base-directory ,(my/site-path "src/blog/posts")
           :publishing-directory ,(my/site-path "site/blog/posts")
           :base-extension "org"
           :recursive t
           :publishing-function org-rss-publish-to-rss
           :html-link-home ,(concat my/site-url "/blog/posts/")
           :html-link-use-abs-url t
           :rss-extension "xml"
           :rss-image-url ,my/rss-avatar-url
           :author "DrDos"
           :email "simon@dr-dos.org"
           :auto-sitemap t
           :sitemap-filename "blog-rss.org"
           :sitemap-title "DrDos' Blog"
           :sitemap-sort-files anti-chronologically
           :sitemap-format-entry my/rss-sitemap-entry
           :sitemap-function my/rss-sitemap-function)

          ("static"
           :base-directory ,(my/site-path "static")
           :base-extension "css\\|png\\|jpg\\|jpeg\\|svg\\|gif\\|webp\\|ico\\|asc\\|xml\\|txt\\|pdf"
           :publishing-directory ,(my/site-path "site")
           :recursive t
           :publishing-function org-publish-attachment)

          ("txt"
           :base-directory ,(my/site-path "src")
           :publishing-directory ,(my/site-path "site/txt")
           :base-extension "org"
           :recursive t
           :publishing-function my/org-ascii-publish-with-ansi
           :body-only t
           :ascii-text-width 80)

          ("website" :components ("pages" "posts" "rss" "static" "txt")))))

;;;; Advice Management

(defun my/org-publish-clean-stale-cache ()
  "Remove stale cache entries when output dirs are missing."
  (require 'ox-publish)
  (when (boundp 'org-publish-timestamp-directory)
    (let ((cache-dir (file-name-as-directory
                      (expand-file-name org-publish-timestamp-directory))))
      (when (file-directory-p cache-dir)
        (dolist (cache-file (directory-files cache-dir t "\\.cache\\'"))
          (let* ((project-name (file-name-base cache-file))
                 (project (assoc project-name org-publish-project-alist)))
            (when project
              (let* ((pub-dir (plist-get (cdr project) :publishing-directory))
                     (outputs-missing (and pub-dir
                                          (not (file-directory-p pub-dir)))))
                (when outputs-missing
                  (delete-file cache-file)
                  (message "Cleaned cache: %s" project-name))))))))))

(defun my/website-publish-force ()
  "Force-publish, ignoring cache."
  (interactive)
  (org-publish "website" t)
  (message "Force-published website"))

(defun my/refresh-publish-alist-advice (&rest _args)
  "Refresh project alist before publishing."
  (my/site-root-reset)
  (my/setup-publish-alist)
  (my/org-publish-clean-stale-cache))

(defun my/website-publish-mode-enable ()
  "Enable auto-refresh of project alist."
  (interactive)
  (advice-add 'org-publish :before #'my/refresh-publish-alist-advice)
  (when (called-interactively-p 'any)
    (message "Publish mode enabled")))

(defun my/website-publish-mode-disable ()
  "Disable auto-refresh of project alist."
  (interactive)
  (advice-remove 'org-publish #'my/refresh-publish-alist-advice)
  (when (called-interactively-p 'any)
    (message "Publish mode disabled")))

(my/website-publish-mode-enable)
(ignore-errors (my/setup-publish-alist))

(provide 'website-publish)
;;; website-publish.el ends here
