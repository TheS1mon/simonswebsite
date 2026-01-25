;;; website-publish.el --- Org‑publish setup for my static site -*- lexical-binding: t; -*-

;;; Commentary:
;; This package provides org-publish configuration for generating a static
;; website with blog functionality, RSS feed, and plain-text export.
;; Source: https://github.com/therealdrdos/simonswebsite
;;
;; Configuration:
;; Customize these variables to adapt to your setup:
;; - `my/site-url': Base URL of your website
;; - `my/rss-avatar-url': Avatar image URL for RSS feed
;;
;; Functions
;; - `my/site-root-reset': Clear cached root (useful after changing directories)
;; - `my/website-publish-mode-disable': Disable automatic root detection
;; - f`my/website-publish-force': Force-publish all files (ignores cache)
;;
;; Cache Behavior:
;; - Automatic cleanup when entire site/ directory is deleted
;; - Individual deleted files: use M-x my/website-publish-force or C-u M-x org-publish
;;


;;; Code:

;;;; Dependencies
(require 'ox-publish)
(require 'ox-rss)
(require 'subr-x) ;; for when-let

(setq user-full-name "DrDos")
(setq user-mail-address "simon@dr-dos.org")

;;;; Site Root Detection

(defvar my/--site-root-directory nil
  "Cached website project root directory.
Internal variable, use `my/site-root' to access.
Reset with `my/site-root-reset'.")

(defun my/site-root ()
  "Find and return website project root by searching for template.html.
Searches current directory and all parent directories.
Returns the directory path with trailing slash.
Signals an error if template.html cannot be found.

Result is memoized for performance.  Use `my/site-root-reset' to
invalidate the cache after changing directories."
  (or my/--site-root-directory
      (setq my/--site-root-directory
            (let ((root (locate-dominating-file default-directory "template.html")))
              (if root
                  (file-name-as-directory (expand-file-name root))
                (error "Website project not found!

Cannot find template.html in current directory or any parent directory.
Current directory: %s

To fix this:
  1. Navigate to your website project directory (where template.html exists)
  2. Or run M-x cd RET /path/to/your/website/ RET
  3. Then try M-x org-publish RET website RET again"
                       default-directory))))))

(defun my/site-root-reset ()
  "Clear cached website root directory.
Call this after changing directories to force a fresh search."
  (interactive)
  (setq my/--site-root-directory nil)
  (when (called-interactively-p 'any)
    (message "Website root cache cleared")))

(defun my/site-path (sub)
  "Return absolute path of SUB inside website root.
Website root is determined dynamically by searching for template.html."
  (expand-file-name sub (my/site-root)))

;;; Configuration

(defcustom my/site-url "https://www.dr-dos.org"
  "Base URL of the website (without trailing slash)."
  :type 'string
  :group 'org-export-publish)

(defcustom my/rss-avatar-url "https://www.dr-dos.org/rss-avatar.png"
  "URL to avatar image for RSS feed."
  :type 'string
  :group 'org-export-publish)

(defconst my/--blog-path "/blog/blog.html"
  "Path to blog index page (relative to site root).")

(defconst my/--posts-dir "posts/"
  "Directory name for blog posts (with trailing slash).")

;;;; Global Export Parameters

(setq org-html-doctype "html5")
(setq org-html-html5-fancy t)
(setq org-html-scripts "")           ; strip all JS snippets that ox-html adds
(setq org-export-with-toc nil)       ; default – override per file via #+OPTIONS

(setq org-html-validation-link nil) ; deactivate org validation link

;;;; HTML Template System

(defun my/html-template (output backend info)
  "Replace placeholders in template.html and return full HTML page.
OUTPUT  – HTML fragment produced by Org export.
INFO    – plist with export context (titles, descriptions, tags).
BACKEND – What backend is the caller

{{title}}        – #+TITLE of the document
{{description}}  – #+DESCRIPTION (optional)
{{year}}         – current year
{{tags}}         – tag link list (posts only)
{{lang}}         – #+LANGUAGE of the document (defaults to en)
{{contents}}     – the exported HTML of the buffer"
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
                                            my/--blog-path tag tag))
                                  tag-list " ")))))
        ;; Verify template file exists before attempting to read it
        (unless (file-exists-p template-file)
          (error "Template.html not found at: %s

This file is required for HTML export.  Please ensure:
  1. You are in the correct website directory
  2. template.html exists in the website root
  3. The file has not been moved or deleted" template-file))
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
  "Extract #+DESCRIPTION from FILE-PATH.
Returns the description string or nil if not found."
  (when (file-exists-p file-path)
    (with-temp-buffer
      (insert-file-contents file-path)
      (goto-char (point-min))
      (when (re-search-forward "^#\\+DESCRIPTION:[ \\t]+\\(.*\\)$" nil t)
        (match-string 1)))))

(defun my/sitemap-entry (entry _style project)
  "Return formatted line for sitemap ENTRY in PROJECT."
  (let* ((base-dir   (or (org-publish-property :base-directory project)
                       default-directory))
         (abs-entry  (expand-file-name entry base-dir))
         (filename   (file-name-nondirectory entry))
         (link       (concat my/--posts-dir filename))
         (title      (org-publish-find-title entry project))
         (date       (org-publish-find-date  entry project))
         (description (my/extract-description abs-entry)))
    (format "%s [[file:%s][%s]] – %s"
            (format-time-string "%Y-%m-%d" date)
            link title (or description ""))))

;;;; Plain-Text Export with ANSI Colors

(defun my/add-ansi-colors (filename)
  "Post-process FILENAME, adding basic ANSI escape codes.
Signals an error if FILENAME does not exist or is not writable."
  (unless (file-exists-p filename)
    (error "Cannot add ANSI colors: file does not exist: %s" filename))
  (unless (file-writable-p filename)
    (error "Cannot add ANSI colors: file is not writable: %s" filename))
  (with-temp-buffer
    (insert-file-contents filename)
    ;; bold (**text** in ox-ascii output)
    (goto-char (point-min))
    (while (re-search-forward "\\*\\*\\([^*]+\\)\\*\\*" nil t)
      (replace-match (concat "\e[1m" (match-string 1) "\e[0m") nil t))
    ;; italic (//text//)
    (goto-char (point-min))
    (while (re-search-forward "//\\([^/]+\\)//" nil t)
      (replace-match (concat "\e[3m" (match-string 1) "\e[0m") nil t))
    ;; underline (__text__)
    (goto-char (point-min))
    (while (re-search-forward "__\\([^_]+\\)__" nil t)
      (replace-match (concat "\e[4m" (match-string 1) "\e[0m") nil t))
    (condition-case err
        (write-region (point-min) (point-max) filename)
      (file-error
       (error "Failed to write ANSI-colored output to %s: %s"
              filename (error-message-string err))))))

;; Wrapper to include the ansi escape codes
(defun my/org-ascii-publish-with-ansi (plist filename pub-dir)
  "Export to ASCII and inject ANSI codes.
PLIST contains project properties.
FILENAME is the Org file to export.
PUB-DIR is the publishing directory."
  (let ((outfile (org-ascii-publish-to-ascii plist filename pub-dir)))
    (my/add-ansi-colors outfile)
    outfile))

;; Builds the blog site with intro text
(defun my/sitemap-with-intro (title list)
  "Return TITLE, custom intro text and the automatic LIST of posts."
  (concat
   "#+TITLE: " title "\n\n "
   "Welcome to my blog – here you'll find all posts. "
   (format "RSS feed: [[file:%sblog-rss.xml][XML]]\n\n  " my/--posts-dir)
   (org-list-to-org list)))

;;;; RSS Feed Generation

(defun my/rss-sitemap-entry (entry _style project)
  "Return RSS-compatible headline for ENTRY in PROJECT.
ox-rss requires headlines (not lists) with links."
  (let* ((base-dir (or (org-publish-property :base-directory project)
                      default-directory))
         (abs-entry (expand-file-name entry base-dir))
         (filename (file-name-nondirectory entry))
         (title (org-publish-find-title entry project))
         (date (org-publish-find-date entry project))
         (description (my/extract-description abs-entry)))
    ;; RSS needs headlines with properties, not lists
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
  "Generate RSS-compatible sitemap from LIST.
Omits intro text and directly outputs headlines, not nested lists."
  ;; Build output string by iterating over entries
  (let ((entries (cdr list))
        (output "#+TITLE: Latest Blog Posts
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
  "Set up `org-publish-project-alist' with current website root.
This allows publishing from any directory containing template.html."
  (interactive)
  (setq org-publish-project-alist
        `(
          ;; Main static pages (index, aboutme, pgp, blog overview)
          ("pages"
           :base-directory ,(my/site-path "src")
           :base-extension "org"
           :exclude "blog/posts/.*"
           :publishing-directory ,(my/site-path "site")
           :recursive t
           :publishing-function org-html-publish-to-html
           :with-timestamp nil
           :body-only t
           :with-author nil)

          ;; Blog posts
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

          ;; RSS feed for posts
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
           :sitemap-title "Latest Blog Posts"
           :sitemap-sort-files anti-chronologically
           :sitemap-format-entry my/rss-sitemap-entry
           :sitemap-function my/rss-sitemap-function)

          ;; Static assets (CSS, images …)
          ("static"
           :base-directory ,(my/site-path "static")
           :base-extension "css\\|png\\|jpg\\|jpeg\\|svg\\|gif\\|webp\\|ico\\|asc\\|xml\\|txt\\|pdf"
           :publishing-directory ,(my/site-path "site")
           :recursive t
           :publishing-function org-publish-attachment)

          ;; Plain‑text variant for terminal displayability
          ("txt"
           :base-directory ,(my/site-path "src")
           :publishing-directory ,(my/site-path "site/txt")
           :base-extension "org"
           :recursive t
           :publishing-function my/org-ascii-publish-with-ansi
           :body-only t
           :ascii-text-width 80)

          ;; Build everything together
          ("website" :components ("pages" "posts" "rss" "static" "txt")))))

;;;; Advice Management

(defun my/org-publish-clean-stale-cache ()
  "Clean org-publish cache if output directories are missing.
This ensures files are republished when the site directory is deleted."
  (require 'ox-publish)
  (when (boundp 'org-publish-timestamp-directory)
    (let ((cache-dir (file-name-as-directory
                      (expand-file-name org-publish-timestamp-directory))))
      (when (file-directory-p cache-dir)
        (dolist (cache-file (directory-files cache-dir t "\\.cache\\'"))
          (let* ((project-name (file-name-base cache-file))
                 (project (assoc project-name org-publish-project-alist)))
            (when project
              ;; Check if any output file is missing
              (let* ((pub-dir (plist-get (cdr project) :publishing-directory))
                     (outputs-missing (and pub-dir
                                          (not (file-directory-p pub-dir)))))
                (when outputs-missing
                  (delete-file cache-file)
                  (message "Cleaned stale cache for project '%s'" project-name))))))))))

(defun my/website-publish-force ()
  "Force-publish entire website, ignoring org-publish cache.
Use this when individual files were deleted from output directory."
  (interactive)
  (org-publish "website" t)
  (message "Force-published entire website"))

(defun my/refresh-publish-alist-advice (&rest _args)
  "Refresh `org-publish-project-alist' before publishing.
This ensures the correct website root is used based on current directory."
  (my/site-root-reset)
  (my/setup-publish-alist)
  (my/org-publish-clean-stale-cache))

(defun my/website-publish-mode-enable ()
  "Enable automatic project alist refresh for website publishing.
This adds advice to `org-publish' that ensures the correct website
root is detected based on the current directory."
  (interactive)
  (advice-add 'org-publish :before #'my/refresh-publish-alist-advice)
  (when (called-interactively-p 'any)
    (message "Website publish mode enabled")))

(defun my/website-publish-mode-disable ()
  "Disable automatic project alist refresh for website publishing.
This removes the advice from `org-publish'."
  (interactive)
  (advice-remove 'org-publish #'my/refresh-publish-alist-advice)
  (when (called-interactively-p 'any)
    (message "Website publish mode disabled")))

;; Initial setup
(my/website-publish-mode-enable)

;; Try to set up project alist immediately if in a website directory
;; This allows org-publish completion to work without first calling org-publish
(ignore-errors (my/setup-publish-alist))

(provide 'website-publish)
;;; website-publish.el ends here
