EMACS ?= emacs
EMACS_AGENT ?= ../emacs-agent
BATCH = $(EMACS) -Q --batch -L . -L $(EMACS_AGENT)

.PHONY: test test-live compile clean

test:
	$(BATCH) -l test/emacs-agent-searxng-test.el -f ert-run-tests-batch-and-exit

# Requires a reachable SearXNG instance (SEARXNG_URL or the built-in default).
test-live:
	EMACS_AGENT_SEARXNG_TEST=1 $(BATCH) -l test/emacs-agent-searxng-test.el -f ert-run-tests-batch-and-exit

compile:
	$(BATCH) --eval '(setq byte-compile-error-on-warn t)' -f batch-byte-compile emacs-agent-searxng.el

clean:
	rm -f *.elc
