# Makefile — integrate the devspace-mcp-tunnel toolchain
#
# Override variables on the command line, e.g.:
#   make install MIRROR=1
#   make tunnel TUNNEL_CMD="ngrok http 7676" URL_REGEX="https://[a-z0-9-]+\.ngrok-free\.app"
#   make report REVIEW_PATH=src NAME_GLOB=*.c
#   make finalize REPORT=review-report.md

SHELL := /bin/bash

MIRROR        ?=
TUNNEL_CMD    ?= ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -p 443 -R0:localhost:7676 a.pinggy.io
URL_REGEX     ?=
KNOWN_URL     ?=
REVIEW_PATH   ?= .
NAME_GLOB     ?= *
REPORT        ?= review-report.md
HTML          ?= $(REPORT:.md=.html)

.PHONY: help install tunnel tunnel-known report summarize html finalize

help:
	@echo "devspace-mcp-tunnel — toolchain"
	@echo
	@echo "Usage: make <target> [VAR=value ...]"
	@echo
	@echo "Targets:"
	@echo "  install      install DevSpace + interactive init (MIRROR=1 = npmmirror)"
	@echo "  tunnel       rebuild tunnel + sync configs + restart (TUNNEL_CMD=, URL_REGEX=)"
	@echo "  tunnel-known use an existing URL, skip tunnel mgmt (KNOWN_URL=)"
	@echo "  report       scaffold a static-review report (REVIEW_PATH=, NAME_GLOB=, REPORT=)"
	@echo "  summarize    tally a filled report by severity/type (REPORT=)"
	@echo "  html         render report to HTML (REPORT=, HTML=)"
	@echo "  finalize     summarize + html, run after the report is filled"

install:
	bash ./setup.sh $(if $(MIRROR),--mirror)

tunnel:
	bash ./refresh-devspace-mcp.sh --tunnel-cmd "$(TUNNEL_CMD)" $(if $(URL_REGEX),--url-regex "$(URL_REGEX)")

tunnel-known:
	bash ./refresh-devspace-mcp.sh --known-url "$(KNOWN_URL)"

report:
	bash ./review.sh --path "$(REVIEW_PATH)" --glob "$(NAME_GLOB)" --out "$(REPORT)"

summarize:
	bash ./review.sh --summarize "$(REPORT)"

html:
	bash ./report-to-html.sh --in "$(REPORT)" --out "$(HTML)"

finalize: summarize html
