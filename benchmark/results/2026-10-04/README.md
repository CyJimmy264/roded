# Recorded long-document runs

See [methodology and interpretation](../../../docs/benchmark-results-2026-10-04.md).
These JSON files are unchanged copies of the measured reports, including every
operation, environment, source revision and dirty-checkout flag.
`manifest.json` records file hashes and observation counts.

`baseline-*` files came from exploratory dirty checkouts and are not exact clean
commit baselines. The other reports were recorded at the clean revision stated
in each file. The main suite resets each invocation; `*-typing` and `curses-plain`,
`curses-markdown`, `curses-ruby` files measure consecutive edits instead.
