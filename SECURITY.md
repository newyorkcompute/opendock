# Security Policy

## Reporting a vulnerability

Please don't report security problems in public issues, pull requests, or discussions.

Report them privately through GitHub's private vulnerability reporting instead: go to the
repository's [Security tab](https://github.com/newyorkcompute/opendock/security) and click
**Report a vulnerability**, or open
[a new advisory](https://github.com/newyorkcompute/opendock/security/advisories/new)
directly. Only the maintainers can see the report.

Please include:

- What the problem is and what an attacker could do with it
- Steps to reproduce, or a proof of concept
- Your OpenDock version (or commit) and macOS version

We'll acknowledge your report as soon as we can, keep you updated while we work on a fix, and
credit you in the advisory unless you'd rather stay anonymous.

## Supported versions

OpenDock is in early development. Security fixes go into `main` and the latest release only.

## Scope

OpenDock isn't sandboxed. It launches apps and opens files, reads your calendars when you
grant access, and imports layout files in JSON. Problems in any of these areas are in scope,
for example a crafted layout file that runs code or opens something you didn't ask for.
