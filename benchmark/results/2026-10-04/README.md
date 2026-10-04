# Recorded long-document runs

See [methodology and interpretation](../../../docs/benchmark-results-2026-10-04.md).
These JSON files are unchanged copies of the measured reports, including every
operation, environment, source revision and dirty-checkout flag.
`manifest.json` records file hashes and observation counts.

`baseline-*` files came from exploratory dirty checkouts and are not exact clean
commit baselines. The other reports were recorded at the clean revision stated
in each file. The main suite resets each invocation; `*-typing` and `curses-plain`,
`curses-markdown`, `curses-ruby` files measure consecutive edits instead.

`qt-plain-layout-*` reports record the clean `b13a60c` follow-up. Complete and
large diagnostic reports contain two observations per case; the focused 1500-line
report has forty and the focused 10,000-line report has one hundred. Their
methodology remains execution plus frontend flush, excluding keyboard queues and
compositor timing.
