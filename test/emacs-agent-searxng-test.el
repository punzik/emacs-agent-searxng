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

(cl-defun emacs-agent-searxng-test--with-page
    (body thunk &key (content-type "text/html; charset=utf-8")
          (status 200) (coding 'utf-8) final-url)
  "Call THUNK with a mocked HTTP response containing BODY.
CONTENT-TYPE, STATUS, CODING and FINAL-URL describe the response."
  (let ((response (generate-new-buffer " *searxng-test-page*")))
    (unwind-protect
        (progn
          (with-current-buffer response
            (set-buffer-multibyte nil)
            (when final-url
              (setq-local url-current-object (url-generic-parse-url final-url)))
            (insert (format "HTTP/1.1 %d Test\r\n" status))
            (when content-type
              (insert "Content-Type: " content-type "\r\n"))
            (insert "\r\n" (encode-coding-string body coding)))
          (prog1
              (cl-letf (((symbol-function 'url-retrieve-synchronously)
                         (lambda (_url silent inhibit-cookies timeout)
                           (should silent)
                           (should inhibit-cookies)
                           (should (equal timeout emacs-agent-searxng-timeout))
                           response))
                        ((symbol-function 'url-retrieve)
                         (lambda (&rest _) (ert-fail "Unexpected subresource request")))
                        ((symbol-function 'url-queue-retrieve)
                         (lambda (&rest _) (ert-fail "Unexpected queued request"))))
                (funcall thunk))
            (should-not (buffer-live-p response))))
      (when (buffer-live-p response)
        (kill-buffer response)))))

(ert-deftest emacs-agent-searxng-fetch-html ()
  (emacs-agent-searxng-test--with-page
   (concat "<html><head><title>  Тест &amp; пример </title></head><body>"
           "<header>Header noise</header><nav>Navigation noise</nav>"
           "<main><h1>Heading</h1><p>Привет <a href='../docs'>Guide</a>.</p>"
           "<ul><li>First item</li><li>Second item</li></ul>"
           "<pre>  code\n    indent</pre>"
           "<script>Script noise</script><style>Style noise</style>"
           "<img src='/image.png'><iframe src='/frame'>Frame noise</iframe></main>"
           "<footer>Footer noise</footer><p>Outside main</p></body></html>")
   (lambda ()
     (let ((current (current-buffer))
           (result (emacs-agent-searxng-fetch "https://example.org/start")))
       (should (eq current (current-buffer)))
       (should (string-prefix-p
                "Title: Тест & пример\nSource: https://example.org/articles/page\n"
                result))
       (dolist (text '("Heading" "Привет" "Guide" "First item" "Second item"
                       "    indent" "https://example.org/docs" "Links:"))
         (should (string-search text result)))
       (dolist (text '("Header noise" "Navigation noise" "Script noise"
                       "Style noise" "Frame noise" "Footer noise" "Outside main"))
         (should-not (string-search text result)))
       (should-not (text-properties-at 0 result))))
   :final-url "https://example.org/articles/page"))

(ert-deftest emacs-agent-searxng-fetch-article-and-body ()
  (dolist (html '("<html><body><article>Article text</article><p>Other</p></body></html>"
                  "<html><body><p>Article text</p></body></html>"))
    (emacs-agent-searxng-test--with-page
     html
     (lambda ()
       (let ((result (emacs-agent-searxng-fetch "https://example.org")))
         (should (string-search "Article text" result))
         (should-not (string-search "Other" result)))))))

(ert-deftest emacs-agent-searxng-fetch-plain-text ()
  (emacs-agent-searxng-test--with-page
   "  Привет\n\n  Preserve indentation.\n"
   (lambda ()
     (should (equal (emacs-agent-searxng-fetch "https://example.org/readme")
                    (concat "Title: https://example.org/readme\n"
                            "Source: https://example.org/readme\n\n"
                            "  Привет\n\n  Preserve indentation.\n"))))
   :content-type "Text/Plain; Charset=windows-1251" :coding 'windows-1251))

(ert-deftest emacs-agent-searxng-fetch-preformatted ()
  (emacs-agent-searxng-test--with-page
   "<html><body><pre>    first\n      second</pre></body></html>"
   (lambda ()
     (should (string-search "\n\n    first\n      second"
                            (emacs-agent-searxng-fetch "https://example.org"))))))

(ert-deftest emacs-agent-searxng-fetch-charsets ()
  (emacs-agent-searxng-test--with-page
   "Привет 😀"
   (lambda ()
     (should (string-suffix-p "Привет 😀"
                              (emacs-agent-searxng-fetch "https://example.org"))))
   :content-type "text/plain")
  (dolist (meta '("<meta charset='windows-1251'>"
                  "<meta content='text/html; charset=windows-1251' http-equiv='Content-Type'>"))
    (emacs-agent-searxng-test--with-page
     (concat "<html><head>" meta "</head><body><p>Привет</p></body></html>")
     (lambda ()
       (should (string-search "Привет"
                              (emacs-agent-searxng-fetch "https://example.org"))))
     :content-type "text/html" :coding 'windows-1251)))

(ert-deftest emacs-agent-searxng-fetch-links ()
  (emacs-agent-searxng-test--with-page
   (concat "<html><head><base href='https://docs.example.org/manual/'></head>"
           "<body><p><a href='intro'>Intro</a> and <a href='intro'>Again</a>. "
           "<a href='https://other.example.org'>Other</a>. "
           "<a href='javascript:alert(1)'>Unsafe</a>.</p></body></html>")
   (lambda ()
     (let ((result (emacs-agent-searxng-fetch "https://example.org")))
       (should (string-search "Intro [1]" result))
       (should (string-search "Again [1]" result))
       (should (string-search "[1] https://docs.example.org/manual/intro" result))
       (should (string-search "[2] https://other.example.org" result))
       (should-not (string-search "javascript:" result))))))

(ert-deftest emacs-agent-searxng-fetch-no-libxml ()
  (emacs-agent-searxng-test--with-page
   "<p>Some text</p>"
   (lambda ()
     (cl-letf (((symbol-function 'libxml-available-p) (lambda () nil)))
       (let ((err (should-error (emacs-agent-searxng-fetch "https://example.org"))))
         (should (string-match-p "libxml" (error-message-string err))))))))

(ert-deftest emacs-agent-searxng-fetch-truncation ()
  (emacs-agent-searxng-test--with-page
   (make-string 1000 ?x)
   (lambda ()
     (let ((result (emacs-agent-searxng-fetch "https://example.org" :max-length 100)))
       (should (= (length (car (split-string result "\n\n\\[Output truncated"))) 100))
       (should (string-suffix-p "[Output truncated at 100 characters]" result))))
   :content-type "text/plain"))

(ert-deftest emacs-agent-searxng-fetch-argument-errors ()
  (cl-letf (((symbol-function 'url-retrieve-synchronously)
             (lambda (&rest _) (ert-fail "Invalid arguments must not cause a request"))))
    (dolist (url '(nil "" "file:///etc/passwd" "ftp://example.org" "https://" "x"))
      (should-error (emacs-agent-searxng-fetch url)))
    (dolist (limit '(0 -1 1.5 "100" nil))
      (should-error (emacs-agent-searxng-fetch "https://example.org" :max-length limit)))))

(ert-deftest emacs-agent-searxng-fetch-response-errors ()
  (dolist (case '(("text/html" 404 "Not found" "HTTP 404")
                  ("application/pdf" 200 "%PDF" "Unsupported content type")
                  ("image/png" 200 "binary" "Unsupported content type")
                  (nil 200 "unknown" "Unsupported content type")
                  ("text/html" 200 "<html><body><script>JS only</script></body></html>"
                   "no readable text")))
    (emacs-agent-searxng-test--with-page
     (nth 2 case)
     (lambda ()
       (let ((err (should-error (emacs-agent-searxng-fetch "https://example.org"))))
         (should (string-match-p (nth 3 case) (error-message-string err)))))
     :content-type (nth 0 case) :status (nth 1 case)))
  (cl-letf (((symbol-function 'url-retrieve-synchronously) (lambda (&rest _) nil)))
    (should-error (emacs-agent-searxng-fetch "https://example.org"))))

(ert-deftest emacs-agent-searxng-fetch-helper-registered ()
  (let ((entry (gethash 'emacs-agent-searxng-fetch emacs-agent-user-helpers--registry)))
    (should (stringp entry))
    (should (string-search "emacs-agent-searxng-fetch" entry))
    (should (string-search "Example:" entry))))

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
