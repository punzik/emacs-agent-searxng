;;; emacs-agent-searxng-test.el --- SearXNG helper tests -*- lexical-binding: t; -*-

(require 'cl-lib)
(require 'ert)
(require 'emacs-agent-searxng)

(defun emacs-agent-searxng-test--with-url (url thunk)
  "Run THUNK with `emacs-agent-searxng-url' set to URL."
  (let ((emacs-agent-searxng-url url))
    (funcall thunk)))

(ert-deftest emacs-agent-searxng-url-specials ()
  (emacs-agent-searxng-test--with-url
   "https://searxng.example:8080"
   (lambda ()
     (should (equal (emacs-agent-searxng--url "hello world")
                    "https://searxng.example:8080/search?q=hello%20world&format=json"))
     (should (equal (emacs-agent-searxng--url "a&b=c d")
                    "https://searxng.example:8080/search?q=a%26b%3Dc%20d&format=json"))
     (should (equal (emacs-agent-searxng--url "q" :categories '("general" "science")
                                              :language "ru")
                    "https://searxng.example:8080/search?q=q&format=json&categories=general%2Cscience&language=ru"))
     (let ((raised nil))
       (condition-case err
           (emacs-agent-searxng-test--with-url
            "ftp://searxng.example/"
            (lambda () (emacs-agent-searxng--url "q")))
         (error (setq raised err)))
       (should raised)
       (should (string-match-p "http or https" (error-message-string raised)))))))

(ert-deftest emacs-agent-searxng-url-unicode ()
  (let ((emacs-agent-searxng-url "https://searxng.example"))
    (should (equal (emacs-agent-searxng--url " привет café 😀 " :language "ru")
                   (concat "https://searxng.example/search?q="
                           "%D0%BF%D1%80%D0%B8%D0%B2%D0%B5%D1%82"
                           "%20caf%C3%A9%20%F0%9F%98%80&format=json&language=ru")))))

(ert-deftest emacs-agent-searxng-url-trailing-slash ()
  (emacs-agent-searxng-test--with-url
   "http://searxng.example:8080/"
   (lambda ()
     (should (equal (emacs-agent-searxng--url "x")
                    "http://searxng.example:8080/search?q=x&format=json")))))

(ert-deftest emacs-agent-searxng-format-results ()
  (let* ((payload (json-read-from-string
                   (format
                    "{\"results\":[{\"url\":\"https://a.example/?x=1&y=2\",\"title\":\"First  Result\",\"content\":\"Snippet one.\",\"engine\":\"duckduckgo\"},{\"url\":\"\",\"title\":\"bad url\"},{\"url\":\"https://b.example\",\"title\":\"Second\",\"content\":\"Snippet two.\",\"engine\":\"startpage\"},{\"url\":\"https://c.example\",\"title\":\"Third\",\"content\":\"Third snippet\",\"engine\":\"brave\"}]}"))))
    (should (equal (emacs-agent-searxng--format "query" payload 2)
                   (concat "SearXNG results for query:\n\n"
                           "1. First Result\n"
                           "   https://a.example/?x=1&y=2 (duckduckgo)\n"
                           "   Snippet one.\n\n"
                           "2. Second\n"
                           "   https://b.example (startpage)\n"
                           "   Snippet two.")))
    (should (equal (emacs-agent-searxng--format "query" payload 10)
                   (concat "SearXNG results for query:\n\n"
                           "1. First Result\n"
                           "   https://a.example/?x=1&y=2 (duckduckgo)\n"
                           "   Snippet one.\n\n"
                           "2. Second\n"
                           "   https://b.example (startpage)\n"
                           "   Snippet two.\n\n"
                           "3. Third\n"
                           "   https://c.example (brave)\n"
                           "   Third snippet")))))

(ert-deftest emacs-agent-searxng-format-empty ()
  (should (equal (emacs-agent-searxng--format "nothing" (json-read-from-string "{}") 5)
                 "No SearXNG results for nothing."))
  (should (equal (emacs-agent-searxng--format "nothing" (json-read-from-string "{\"results\":[]}") 5)
                 "No SearXNG results for nothing.")))

(ert-deftest emacs-agent-searxng-search-http-response ()
  "Parse a response with point at its end, regardless of JSON settings."
  (dolist (settings '((alist vector symbol)
                      (hash-table vector string)
                      (alist list symbol)
                      (plist list keyword)))
    (let ((json-object-type (nth 0 settings))
          (json-array-type (nth 1 settings))
          (json-key-type (nth 2 settings))
          (response (generate-new-buffer " *searxng-test-response*")))
      (unwind-protect
          (progn
            (with-current-buffer response
              (set-buffer-multibyte nil)
              (insert "HTTP/1.1 200 OK\nContent-Type: application/json\n\n"
                      (encode-coding-string
                       (concat "{\"results\":[{\"url\":\"https://example.org\","
                               "\"title\":\"Тест\",\"content\":\"Snippet\",\"engine\":\"test\"}]}")
                       'utf-8))
              (goto-char (point-max)))
            (cl-letf (((symbol-function 'url-retrieve-synchronously)
                       (lambda (&rest _) response)))
              (should (equal (emacs-agent-searxng-search "q")
                             (concat "SearXNG results for q:\n\n1. Тест\n"
                                     "   https://example.org (test)\n   Snippet"))))
            (should-not (buffer-live-p response))
            (should (equal (list json-object-type json-array-type json-key-type)
                           settings)))
        (when (buffer-live-p response)
          (kill-buffer response))))))

(ert-deftest emacs-agent-searxng-payload-response-errors ()
  "HTTP and JSON errors must still release the response buffer."
  (dolist (case '(("HTTP/1.1 403 Forbidden\n\nForbidden" "HTTP 403")
                  ("HTTP/1.1 200 OK\n\nnot-json" "invalid JSON")))
    (let ((response (generate-new-buffer " *searxng-test-response*")))
      (unwind-protect
          (progn
            (with-current-buffer response
              (insert (car case)))
            (cl-letf (((symbol-function 'url-retrieve-synchronously)
                       (lambda (&rest _) response)))
              (let ((err (should-error
                          (emacs-agent-searxng--payload "http://example.org/search"))))
                (should (string-match-p (cadr case) (error-message-string err)))))
            (should-not (buffer-live-p response)))
        (when (buffer-live-p response)
          (kill-buffer response))))))

(ert-deftest emacs-agent-searxng-search-argument-errors ()
  (should-error (emacs-agent-searxng-search ""))
  (should-error (emacs-agent-searxng-search "x" :limit 0))
  (should-error (emacs-agent-searxng-search "x" :limit 11))
  (should-error (emacs-agent-searxng-search "x" :categories '("general" "")))
  (should-error (emacs-agent-searxng-search "x" :categories "general"))
  (should-error (emacs-agent-searxng-search "x" :language "")))

(ert-deftest emacs-agent-searxng-helper-registered ()
  (let ((entry (gethash 'emacs-agent-searxng-search emacs-agent-user-helpers--registry)))
    (should (stringp entry))
    (should (string-match-p "emacs-agent-searxng-search" entry))
    (should (string-match-p "SearXNG" entry))
    (should (string-search "Example:" entry))
    (should (string-search "(emacs-agent-searxng-search" entry))))

(ert-deftest emacs-agent-searxng-live-search ()
  "Query the configured instance; skipped unless EMACS_AGENT_SEARXNG_TEST=1."
  (unless (getenv "EMACS_AGENT_SEARXNG_TEST")
    (ert-skip "Set EMACS_AGENT_SEARXNG_TEST=1 to run the live search test"))
  (let ((result (emacs-agent-searxng-search "Emacs text editor" :limit 3)))
    (should (stringp result))
    (should (> (length result) 0))
    (should (string-match-p "^SearXNG results for Emacs text editor:$" result))))

(provide 'emacs-agent-searxng-test)
;;; emacs-agent-searxng-test.el ends here
