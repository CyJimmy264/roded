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

`edit-range-before` and `edit-range-after` match forty observations per case
at clean `b4596c2` / `c085675`. `edit-range-qt-hot` has one hundred per case;
`edit-range-qt-large` has two. The `qt-plain-copy-*` follow-up at clean `e348e88`
also has two observations per case. Split cases include first creation and
subsequent pane-pool reuse; inspect individual operations when interpreting them.

`qt-damage-before` / `qt-damage-after` compare forty observations per case at
clean `bfdf4cf` / `b58976e`. `qt-damage-full` and `qt-damage-large` have two
observations; `qt-damage-hot` has one hundred, at clean `e4296e6`.
`exact-edit-qt-hot` matches that hundred-observation configuration at clean
`08df59a`. The `qt-damage-typing-1500` and `exact-edit-typing-*` reports measure
consecutive input. The 10,000-line exact-edit stream contains one hundred inserts,
including the repeated-character case that previously failed verification.
