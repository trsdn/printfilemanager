# AI enrichment benchmark — 2026-08-29, corrected 2026-08-30

The enrichment prompt had never been measured. It describes its JSON schema in prose and the client
strips ```` ```json ```` fences by hand, which looks dated beside structured outputs — so the
obvious "modernisation" was to replace it with `response_format: {type: "json_schema"}`.

That would have broken the feature. This is what measuring found instead.

Reproduce with `scripts/bench-enrichment.py`, which reads real records from the installed library
rather than invented ones.

## Correction: the discipline metric could not see what it claimed to measure

The first version of this document reported **zero invented sources** and concluded the prompt needs
no change. The measurement behind that number was broken.

Discipline was scored by reducing each value to its first token — splitting on whitespace, `/`, `:`
and `.` — and asking whether that token appeared anywhere in the input as a substring. For a URL the
first token is therefore always the scheme. Every fabricated `sourceURL` was compared as the string
`https`, against inputs that routinely carry a URL of their own inside 3MF metadata. Substring
matching failed the other way too: `cc` and `mit` match inside `success` and `submitted`.

Measured against the same 40 real records, feeding a fabricated
`https://www.thingiverse.com/thing:4711` into every one of them:

| | fabrication detected |
|---|---|
| old metric | 23/40 |
| corrected metric | **40/40** |

The 17 it missed are exactly the records whose input already contained a URL — the ones most likely
to tempt a model into producing one.

The corrected metric compares normalised URLs (host and path, with scheme, `www.`, query, fragment
and HTML escaping removed) against the URLs found in the input, and treats a path reaching deeper
than the input's own URL as invention. Every other value must match whole tokens rather than
substrings. Flagged values are printed rather than only counted, and
`bench-enrichment.py --self-test` pins 13 cases offline on every CI run, so the metric is checked as
well as the models.

Its own limits, stated so they are not rediscovered later: it accepts a value when *one* token of it
occurs in the input, so `MakerWorld` is evidenced by `makerworld.com`, and a licence expanded from
`CC-BY` to `Creative Commons Attribution` would be counted as invented.

**The conclusion survives the correction** — see the re-measured tables below — but it now rests on a
metric that has been shown to detect fabrication, which is not something the earlier run could
claim.

## Method

40 records sampled from a real 1,025-file library, against
`http://192.168.2.177:8080/v1/chat/completions`. Each response scored on:

| | |
|---|---|
| **schema** | all 11 keys present, `printability` within its enum, `tags` a list of 5–12 |
| **bare JSON** | parses without fence-stripping |
| **discipline** | are `sourcePlatform`/`Author`/`License`/`URL` null unless the input evidenced them — an invented source is worse than none, because it gets stored and shown as fact |
| **unusable** | description under 30 characters, or a metadata value echoed back verbatim |
| **latency** | wall clock per record |

All five are computed by the committed script. The first version of this document reported
`unusable`, `description Ø` and `tags Ø` from workings that were never committed, so those numbers
could not be reproduced; they are now part of the script's own output.

## Structured outputs are not usable here

| variant | bare JSON | after strip | schema |
|---|---|---|---|
| current (prose schema) | 12/12 | 12/12 | **12/12** |
| `response_format: json_schema` | 2/12 | 11/12 | **0/12** |

The endpoint ignores `response_format` entirely. With the prose schema removed, the model invents
its own keys:

```json
{ "project": "...", "fileName": "...", "fileType": "3MF", "metadata": { ... } }
```

None of which the app reads. **The prose schema is load-bearing, not legacy.**

## Fence-stripping is load-bearing too

Claude fences every single response. Gemini fences most of them — 10 of 12 on one run, 7 of 12 on
another, so it is not a stable property to rely on. Every model produces schema-valid JSON *after*
stripping. Removing the fence-stripping as "no longer needed" would break those models outright.

## The prompt itself needs no change

Re-measured with the corrected metric: **full schema conformance and zero invented sources across
every model tested**. The injection delimiters, the enumerated keys and the "use null when not
evidenced" rule all hold. There was nothing to fix.

## Model comparison

Current small-tier models, 40 records each, re-measured 2026-08-30:

| model | schema | bare JSON | description Ø | tags Ø | unusable | invented | median |
|---|---|---|---|---|---|---|---|
| **claude-haiku-4.5** | 40/40 | 0/40 | **161** | **8.3** | 1 | 0 | **3.26 s** |
| gpt-5.6-luna | 40/40 | **40/40** | 112 | 7.4 | 3 | 0 | 3.73 s |

At 12 records, alongside them:

| model | schema | bare JSON | description Ø | tags Ø | unusable | invented | median |
|---|---|---|---|---|---|---|---|
| claude-haiku-4.5 | 12/12 | 0/12 | 125 | 8.0 | 0 | 0 | **2.95 s** |
| gpt-5.4-mini *(was configured)* | 12/12 | 12/12 | 83 | 7.7 | 0 | 0 | 4.06 s |
| gemini-3.7-flash | 12/12 | 5/12 | 110 | 7.7 | 0 | 0 | 8.26 s |

**`claude-haiku-4.5` is the recommendation**: fastest, longest descriptions, most tags, no invented
sources. `gpt-5.6-luna` is the alternative if bare JSON matters — it never fences.

`gemini-3.7-flash` is still the worst combination here, but on latency alone: two to three times
Haiku for shorter descriptions.

The earlier claim that **gemini-3.7-flash was "the only model that invented a source" does not
reproduce**. Under the corrected metric it invented none, and the original flag was most likely the
old substring test firing on a short value. It is withdrawn rather than left standing.

## A first attempt that picked the wrong models

The first version of this benchmark selected candidates by grepping the model list for
`mini|flash|haiku|small|fast`. That matches old naming conventions, so it tested `gpt-4o-mini`
(2024) and treated `gpt-5.4-mini` as current. Both conclusions were wrong, and the correction came
from being told so rather than from the method. Pick candidates from the full list deliberately.

`gpt-4o-mini` is worth recording as the trap it is: fastest of everything measured, 12/12 on schema,
and it returned `"Boost Me"` as the description of a real file. Schema validity and latency are not
quality. A benchmark measuring only those would have recommended it.

## Models that are listed but cannot be used

`mai-code-1.1-flash` and `mai-code-1-flash-picker` appear in `/v1/models` but return HTTP 502:

```
model "mai-code-1.1-flash" is not accessible via the /chat/completions endpoint
```

They are selectable in Settings and cannot work. The list comes straight from the endpoint, so this
is not something the app invents — but a user picking one gets a failure with no hint why.

## What changed as a result

Nothing in the prompt. The configured model is worth changing in Settings. The discipline metric was
rewritten, because the version that produced the original "zero invented sources" could not have
detected the failure it claimed to rule out — and a metric nobody could check is how that survived a
review. The benchmark script is committed so the question can be re-asked when models change, rather
than re-guessed.
