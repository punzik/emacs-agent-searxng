# emacs-agent-searxng

Web-search and readable-page helpers for [emacs-agent](https://github.com/punzik/emacs-agent).
Search uses a [SearXNG](https://docs.searxng.org/) instance; page fetching
connects directly to the requested website.

It follows the same model as `pi-searxng`: ordinary Lisp functions
(`emacs-agent-searxng-search` and `emacs-agent-searxng-fetch`) that the agent
calls through its existing `eval_elisp` tool. Loading the file registers
both helpers in the `emacs-agent-register-helper` registry, so every new
agent input gets compact descriptions, return shapes and usage examples.
No new tool, permission or keybinding is added.

## Requirements

- Emacs 28.1+ (tested with 30.2)
- [emacs-agent](https://github.com/punzik/emacs-agent) on the load-path (for `emacs-agent-user-helpers`)
- For search: a reachable SearXNG instance with the JSON format enabled
  (`formats: [html, json]` in `settings.yml`)
- For HTML fetching: Emacs built with libxml2 support (`(libxml-available-p)`)
- No external programs or additional Emacs packages are needed

## Usage

```elisp
(add-to-list 'load-path "/path/to/emacs-agent")
(add-to-list 'load-path "/path/to/emacs-agent-searxng")
(require 'emacs-agent-searxng)
```

The agent then uses it through `eval_elisp`:

```elisp
(emacs-agent-searxng-search "SearXNG JSON API" :language "en" :limit 3)
```

Returns a numbered plain-text list of title, URL (source engine) and
snippet for up to `limit` results (1–10, default 5), or a short "no
results" notice. Keyword options:

- `:query` — nonempty search string (positional)
- `:categories` — list of SearXNG categories, e.g. `("general" "science")`
- `:language` — language code, e.g. `"en"`, `"ru"`
- `:limit` — 1 to 10, default 5

## Read a page

```elisp
(emacs-agent-searxng-fetch "https://example.org/article" :max-length 20000)
```

Returns plain text with a title, the final source URL after redirects,
readable page content and numbered links. Relative links are resolved
against the page URL. HTML is rendered using built-in libxml and SHR,
preferring `<main>`, then `<article>`, then the full body. Scripts, styles,
navigation and other obvious boilerplate are removed; headings, lists
and preformatted text are retained. This is a simple heuristic, not
Readability or a browser.

- URL is positional and must use HTTP or HTTPS.
- `:max-length` is a positive character limit (default 20000) for the whole
  output. A truncation notice is appended outside this limit when needed.
  This does **not** limit the downloaded response size.
- Supports HTML, XHTML and plain text. PDF, binary files and responses
  without a supported `Content-Type` signal errors.
- Uses the response charset, or HTML charset metadata, falling back to UTF-8.
- JavaScript is not executed; images and other subresources are not fetched.
  JavaScript-only pages with no readable text signal an error.
- HTTP failures and unreachable URLs signal errors. Temporary response and
  rendering buffers are discarded; user buffers and files are unchanged.

Cite `Source` or the returned link URLs when using the fetched content.
Fetching is independent of SearXNG and needs no running search instance.

## Configuration

- `emacs-agent-searxng-url` — SearXNG base URL. Default: the
  `SEARXNG_URL` environment variable, else `http://localhost:8080`.
- `emacs-agent-searxng-timeout` — response timeout for both search and page
  fetching, in seconds (default 15).

The request is synchronous and changes no editor state; unreachable
instances, HTTP errors and invalid JSON signal an error the agent can see.

## Test

```bash
make test          # offline search/fetch tests (mocked HTTP responses)
make test-live     # also queries the real SearXNG instance
make compile
```

Without make:

```bash
emacs -Q --batch -L . -L /path/to/emacs-agent \
  -l test/emacs-agent-searxng-test.el -f ert-run-tests-batch-and-exit
```

The live test runs only with `EMACS_AGENT_SEARXNG_TEST=1` set. Note that this
helper relies on the URL implementation of the local Emacs build
(`url-retrieve-synchronously`); it is tested against the NixOS Emacs 30.2
package, whose URL and json behavior differs from stock Emacs in a few
ways.

## License

GNU General Public License v3.0 only (`GPL-3.0-only`), like `pi-searxng`.
