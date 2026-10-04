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

`background-ruby-*` reports at clean `59e903f` contain one hundred foreground
typing observations each, plus two separately recorded waits for final syntax
coloring. Their harness hash and latency scope differ from the earlier fully
synchronous Ruby reports; they are not strict before/after comparisons.

`qt-exec-original` / `qt-exec-released`, at clean `a1e5a0d`, are native event-loop
scheduling probes. They record individual ticker gaps rather than editor
operations; the manifest lists them separately under `probes`. They demonstrate
Ruby thread progress, not keyboard-to-visible-frame latency.

The final Russian report is
[optimization-final-report-2026-10-05.md](../../../docs/optimization-final-report-2026-10-05.md).
The archive directory retains the initial benchmark date; final work crossed local midnight.

The final core/application/curses matrix at clean f019493 has 204 cases, twenty
observations each. Subsequent changes affect Qt only. The final Qt matrix at clean
0df1077 has all 34 operations at both sizes, two observations each. Fixture hashes
match the original baseline; historical ratios do not imply compatible harnesses
or identical observation counts.

The three qt-long-2500 reports compare the pre-fix reference a570254, the
character-format/Fusion stage 9e8851c, and the final one-time scroll-timer callback
0df1077. They share fixture, configuration, latency harness hash and 100 observations
per direction. The reference bundle retains a570254 with prerequisite f019493;
it changes only the benchmark harness on top of the old production source.

The remaining final long-line, one-buffer, small-window, Unicode and real-file
reports cover deeper columns and large windows. The final real-key plain 1500
and Ruby 10000 reports have 50 observations per paired operation and 100 typing
observations. Source files in the real-file case were read, not edited; their
hashes and the actual Qt style/window dimensions are included.
