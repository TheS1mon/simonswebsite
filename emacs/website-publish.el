;;; website-publish.el --- org-publish config -*- lexical-binding: t; -*-

;;; Commentary:
;; Static site generator with blog and RSS.
;; Load this file, then call (org-publish "website" t) to build.

;;; Code:

(require 'ox-publish)
(require 'ox-rss)
(require 'subr-x)

(setq user-full-name "DrDos")
(setq user-mail-address "simon@dr-dos.org")

;;; Global Configuration

(defconst ws-root (file-name-directory
                   (directory-file-name
                    (file-name-directory load-file-name))))
(defconst ws-url "https://www.dr-dos.org")
(defconst ws-rss-avatar (concat ws-url "/rss-avatar.png"))
(defconst ws-blog-index "/blog/blog.html")
(defconst ws-posts-dir "posts/")
(defconst ws-blog-title "DrDos' Blog")
(defconst ws-blog-desc "DrDos' personal blog about IT, security and more.")

;; ANSI escapes for plain-text export
(defconst ws-ansi-bold "\e[1m")
(defconst ws-ansi-italic "\e[3m")
(defconst ws-ansi-underline "\e[4m")
(defconst ws-ansi-reset "\e[0m")

(setq org-html-doctype "html5")
(setq org-html-html5-fancy t)
(setq org-html-scripts "")
(setq org-export-with-toc nil)
(setq org-html-validation-link nil)

;;; HTML Template

(defun ws-html-template (output backend info)
  "Wrap OUTPUT in template.html.  BACKEND must be html, INFO is export plist."
  (if (not (eq backend 'html))
      output
    (let* ((tpl (expand-file-name "template.html" ws-root))
           (title (org-export-data (plist-get info :title) info))
           (desc (or (plist-get info :description) ""))
           (year (format-time-string "%Y"))
           (lang (or (plist-get info :language) "en"))
           (tags (ws--format-tags (plist-get info :filetags))))
      (unless (file-exists-p tpl)
        (error "Template not found: %s" tpl))
      (with-temp-buffer
        (insert-file-contents tpl)
        (goto-char (point-min))
        (while (re-search-forward "{{\\(title\\|description\\|year\\|tags\\|lang\\|contents\\)}}" nil t)
          (replace-match
           (pcase (match-string 1)
             ("title" title)
             ("description" desc)
             ("year" year)
             ("lang" lang)
             ("tags" (or tags ""))
             ("contents" output))
           t t))
        (buffer-string)))))

(defun ws--format-tags (filetags)
  "Format FILETAGS as HTML links.  Return nil if no tags."
  (when filetags
    (let ((tags (if (stringp filetags) (split-string filetags) filetags)))
      (mapconcat (lambda (tag)
                   (format "<a class=\"tag\" href=\"%s#%s\">#%s</a>"
                           ws-blog-index tag tag))
                 tags " "))))

(unless (memq #'ws-html-template org-export-filter-final-output-functions)
  (add-to-list 'org-export-filter-final-output-functions #'ws-html-template))

;;; Blog Helpers

(defun ws--extract-desc (file)
  "Get #+DESCRIPTION from FILE."
  (when (file-exists-p file)
    (with-temp-buffer
      (insert-file-contents file)
      (goto-char (point-min))
      (when (re-search-forward "^#\\+DESCRIPTION:[ \t]*\\(.*\\)$" nil t)
        (match-string 1)))))

(defun ws--entry-data (entry project)
  "Common metadata for ENTRY in PROJECT."
  (let* ((base (or (org-publish-property :base-directory project)
                   default-directory))
         (abs (expand-file-name entry base)))
    (list :file (file-name-nondirectory entry)
          :title (org-publish-find-title entry project)
          :date (org-publish-find-date entry project)
          :desc (ws--extract-desc abs))))

;;; Sitemap Formatters

(defun ws-sitemap-entry (entry _style project)
  "Format ENTRY for blog index.  PROJECT provides base directory."
  (let* ((d (ws--entry-data entry project))
         (file (plist-get d :file))
         (title (plist-get d :title))
         (date (plist-get d :date))
         (desc (plist-get d :desc)))
    (format "%s [[file:%s%s][%s]] – %s"
            (format-time-string "%Y-%m-%d" date)
            ws-posts-dir file title (or desc ""))))

(defun ws-sitemap-function (title list)
  "Blog index page with TITLE and LIST."
  (concat
   "#+TITLE: " title "\n\n"
   "Welcome to my blog – here you'll find all posts. "
   (format "RSS feed: [[file:%sblog-rss.xml][XML]]\n\n" ws-posts-dir)
   (org-list-to-org list)))

;;; RSS Formatters

(defun ws-rss-entry (entry _style project)
  "Format ENTRY as RSS item.  PROJECT provides base directory."
  (let* ((d (ws--entry-data entry project))
         (file (plist-get d :file))
         (title (plist-get d :title))
         (date (plist-get d :date))
         (desc (plist-get d :desc)))
    (format "* %s
:PROPERTIES:
:RSS_PERMALINK: %s
:PUBDATE: %s
:END:
%s"
            title
            (file-name-sans-extension file)
            (format-time-string "<%Y-%m-%d>" date)
            (or desc ""))))

(defun ws-rss-sitemap (_title list)
  "RSS feed from LIST."
  (concat
   (format "#+TITLE: %s\n#+DESCRIPTION: %s\n\n" ws-blog-title ws-blog-desc)
   (mapconcat
    (lambda (e)
      (cond ((stringp e) e)
            ((consp e) (if (stringp (cdr e)) (cdr e) (car e)))
            (t (format "%s" e))))
    (cdr list)
    "\n\n")))

;;; Plain-Text Export

(defun ws--add-ansi (file)
  "Add ANSI escapes to FILE for bold/italic/underline."
  (with-temp-buffer
    (insert-file-contents file)
    (dolist (pair `(("\\*\\*\\([^*]+\\)\\*\\*" . ,ws-ansi-bold)
                    ("//\\([^/]+\\)//" . ,ws-ansi-italic)
                    ("__\\([^_]+\\)__" . ,ws-ansi-underline)))
      (goto-char (point-min))
      (while (re-search-forward (car pair) nil t)
        (replace-match (concat (cdr pair) (match-string 1) ws-ansi-reset) t t)))
    (write-region (point-min) (point-max) file)))

(defun ws-ascii-publish (plist filename pub-dir)
  "Publish FILENAME to PUB-DIR as ASCII with ANSI.  PLIST is publish config."
  (let ((out (org-ascii-publish-to-ascii plist filename pub-dir)))
    (ws--add-ansi out)
    out))

;;; Project Configuration

(setq org-publish-project-alist
      `(("pages"
         :base-directory ,(expand-file-name "src" ws-root)
         :base-extension "org"
         :exclude "blog/posts/.*"
         :publishing-directory ,(expand-file-name "site" ws-root)
         :recursive t
         :publishing-function org-html-publish-to-html
         :with-timestamp nil
         :body-only t
         :with-author nil)

        ("posts"
         :base-directory ,(expand-file-name "src/blog/posts" ws-root)
         :publishing-directory ,(expand-file-name "site/blog/posts" ws-root)
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
         :sitemap-format-entry ws-sitemap-entry
         :sitemap-function ws-sitemap-function)

        ("rss"
         :base-directory ,(expand-file-name "src/blog/posts" ws-root)
         :publishing-directory ,(expand-file-name "site/blog/posts" ws-root)
         :base-extension "org"
         :recursive t
         :publishing-function org-rss-publish-to-rss
         :html-link-home ,(concat ws-url "/blog/posts/")
         :html-link-use-abs-url t
         :rss-extension "xml"
         :rss-image-url ,ws-rss-avatar
         :author ,user-full-name
         :email ,user-mail-address
         :auto-sitemap t
         :sitemap-filename "blog-rss.org"
         :sitemap-title ,ws-blog-title
         :sitemap-sort-files anti-chronologically
         :sitemap-format-entry ws-rss-entry
         :sitemap-function ws-rss-sitemap)

        ("static"
         :base-directory ,(expand-file-name "static" ws-root)
         :base-extension "css\\|png\\|jpg\\|jpeg\\|svg\\|gif\\|webp\\|ico\\|asc\\|xml\\|txt\\|pdf"
         :publishing-directory ,(expand-file-name "site" ws-root)
         :recursive t
         :publishing-function org-publish-attachment)

        ("txt"
         :base-directory ,(expand-file-name "src" ws-root)
         :publishing-directory ,(expand-file-name "site/txt" ws-root)
         :base-extension "org"
         :recursive t
         :publishing-function ws-ascii-publish
         :body-only t
         :ascii-text-width 80)

        ("website" :components ("pages" "posts" "rss" "static" "txt"))))

(provide 'website-publish)
;;; website-publish.el ends here
