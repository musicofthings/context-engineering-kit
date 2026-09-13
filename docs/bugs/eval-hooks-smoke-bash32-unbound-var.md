# Crash report: eval_hooks_smoke.sh fails on stock macOS bash (3.2)

**Filed:** 2026-09-13, by another Claude session working in this repo (attempted
delivery via cross-session message; that channel's approval expired unanswered,
so filing here instead).

> ## Resolved 2026-09-13 — confirmed and fixed in v3.0.1
>
> Reproduced independently before fixing. It does **not** reproduce under
> `LC_CTYPE=C`, which is why both Ubuntu CI and a C-locale shell on the same
> bash 3.2 stayed green — the locale, not just the bash version, is load-bearing:
>
> ```
> $ /bin/bash -c 'set -u; before=1; echo "$before→"'          # LC_CTYPE=C
> (1→)
> $ LC_ALL=en_US.UTF-8 /bin/bash -c 'set -u; before=1; echo "$before→"'
> /bin/bash: before?: unbound variable
> ```
>
> Fixed by bracing all six interpolations. Two gates added so it cannot return:
> a `git grep` in CI for any `$var` immediately followed by a non-ASCII byte,
> and a `macos-latest` job that runs the eval suites under `/bin/bash` with
> `LC_ALL=en_US.UTF-8` — the exact configuration that failed.
>
> Verified: 67/67 under bash 3.2 + UTF-8, still 67/67 under `LC_CTYPE=C`.
>
> Thanks to whoever filed this. The report was accurate and the root cause
> analysis was correct.

**Severity:** Test-infra only — not a plugin defect. The actual hooks all pass
once this is worked around.

## Symptom

```
scripts/eval_hooks_smoke.sh: line 175: before�: unbound variable
```

Eval dies mid-run (57/64 checks executed) under `set -uo pipefail`, aborting
before the SubagentStart/Stop, PreCompact/PostCompact,
InstructionsLoaded/Notification, SessionEnd, and regression/containment
sections ever run.

## Environment

```
$ bash --version
GNU bash, version 3.2.57(1)-release (x86_64-apple-darwin24)
$ which bash
/bin/bash
$ locale | grep LANG
LANG="en_IN.UTF-8"
```

macOS ships bash 3.2 as `/bin/bash` (frozen pre-GPLv3) and never patches it.
`#!/usr/bin/env bash` resolves to this same binary on any Mac without Homebrew
bash installed — so this isn't an edge case, it's the default on stock macOS.

## Root cause

Three lines interpolate a bare `$variable` immediately followed by a Unicode
arrow (`→`, U+2192, no separating space) inside a double-quoted string:

```
scripts/eval_hooks_smoke.sh:175:  ok "SubagentStart increments ($before→$after)" ... "$before→$after"
scripts/eval_hooks_smoke.sh:178:  ok "SubagentStop decrements back ($after→$final)" ... "$after→$final"
scripts/eval_hooks_smoke.sh:188:  ok "compact_count incremented ($cbefore→$cafter)" ... "$cbefore→$cafter"
```

bash 3.2's multibyte-aware variable-name scanner (under a UTF-8 locale)
misreads the arrow's UTF-8 continuation bytes as valid name characters, so it
looks for a variable literally named `before<mangled-byte>` instead of
stopping the name at `before`. That variable is unset, and `set -u` kills the
script.

## Minimal repro

4 lines, no plugin code involved:

```bash
#!/usr/bin/env bash
set -uo pipefail
before=2; after=3
echo "test: ($before→$after)"
```

```
$ bash repro.sh
repro.sh: line 4: before�: unbound variable
```

Bash 4+/5+ do not have this bug — but this machine has no Homebrew bash, so
`env bash` and the shebang both resolve to 3.2.

## Fix

Replace the three glued `$var→$var` interpolations with an ASCII separator,
e.g. `->`:

```diff
- [ "$after" = "$((before+1))" ] && ok "SubagentStart increments ($before→$after)" || bad "SubagentStart increments" "$before→$after"
+ [ "$after" = "$((before+1))" ] && ok "SubagentStart increments ($before->$after)" || bad "SubagentStart increments" "$before->$after"

- [ "$final" = "$before" ] && ok "SubagentStop decrements back ($after→$final)" || bad "SubagentStop decrements" "$after→$final"
+ [ "$final" = "$before" ] && ok "SubagentStop decrements back ($after->$final)" || bad "SubagentStop decrements" "$after->$final"

- [ "$cafter" -gt "${cbefore:-0}" ] && ok "compact_count incremented ($cbefore→$cafter)" || bad "compact_count incremented" "$cbefore→$cafter"
+ [ "$cafter" -gt "${cbefore:-0}" ] && ok "compact_count incremented ($cbefore->$cafter)" || bad "compact_count incremented" "$cbefore->$cafter"
```

(Any separator works — a literal space before the arrow would also do it;
ASCII `->` is simplest and matches the style already used elsewhere for
`fire()`'s comment `# fire <hook.sh> <json>  -> sets RC / OUT / ERR`.)

## Verification after fix

With the arrow swapped for `->` in a scratch copy, the full suite ran clean
against the installed plugin: 64/64 passed, including every section the crash
had been skipping (SubagentStart/Stop, PreCompact/PostCompact,
InstructionsLoaded/Notification, SessionEnd + git-commit path, regression
checks, containment guard).

## Not yet checked

Grep the rest of the repo for the same `$var→$var` (or any `→`/em-dash glued
to a `$var`) pattern in other `.sh` files before calling this closed — this
report only checked `eval_hooks_smoke.sh` since that's what crashed.

Delete this file once the fix lands and is committed.
