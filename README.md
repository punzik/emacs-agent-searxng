# emacs-agent-searxng

Web-search helper for [emacs-agent](../emacs-agent) through a
[SearXNG](https://docs.searxng.org/) instance.

It follows the same model as `pi-searxng`: one ordinary Lisp function
(`emacs-agent-searxng-search`) that the agent calls through its existing
`eval_elisp` tool. Loading the file registers the helper in the
`emacs-agent-register-helper` registry, so every new agent input gets a
compact description, return shape and usage example in its system prompt.
No new tool, permission or keybinding is added.

## Requirements

- Emacs 28.1+ (tested with 30.2)
- `emacs-agent` on the load-path (for `emacs-agent-user-helpers`)
- A reachable SearXNG instance with the JSON format enabled
  (`formats: [html, json]` in `settings.yml`)

## Usage

```elisp
(add-to-list 'load-path "/path/to/emacs-ai-agent/emacs-agent")
(add-to-list 'load-path "/path/to/emacs-ai-agent/emacs-agent-searxng")
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

## Configuration

- `emacs-agent-searxng-url` — SearXNG base URL. Default: the
  `SEARXNG_URL` environment variable, else `http://172.16.3.65:8180`.
- `emacs-agent-searxng-timeout` — response timeout in seconds (default 15).

The request is synchronous and changes no editor state; unreachable
instances, HTTP errors and invalid JSON signal an error the agent can see.

## Test

```bash
make test          # offline tests (URL building, formatting, registration)
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
