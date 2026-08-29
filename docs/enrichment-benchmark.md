# AI enrichment benchmark — 2026-08-29

The enrichment prompt had never been measured. It describes its JSON schema in prose and the client
strips ```` ```json ```` fences by hand, which looks dated beside structured outputs — so the
obvious "modernisation" was to replace it with `response_format: {type: "json_schema"}`.

That would have broken the feature. This is what measuring found instead.

Reproduce with `scripts/bench-enrichment.py`, which reads real records from the installed library
rather than invented ones.

## Method

40 records sampled from a real 1,024-file library. Each response scored on:

| | |
|---|---|
| **schema** | all 11 keys present, `printability` within its enum, `tags` a list of 5–12 |
| **bare JSON** | parses without fence-stripping |
| **discipline** | are `sourcePlatform`/`Author`/`License`/`URL` null unless the input evidenced them — an invented source is worse than none, because it gets stored and shown as fact |
| **unusable** | description under 30 characters, or a metadata value echoed back verbatim |
| **latency** | wall clock per record |

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

Claude fences every single response; Gemini fences all but two. Every model produces schema-valid
JSON *after* stripping. Removing the fence-stripping as "no longer needed" would break those models
outright.

## The prompt itself needs no change

Across every model tested: **full schema conformance, zero invented sources** (one exception, noted
below). The injection delimiters, the enumerated keys and the "use null when not evidenced" rule
all hold. There was nothing to fix.

## Model comparison

Current small-tier models, 40 records each:

| model | schema | bare JSON | description Ø | tags Ø | unusable | invented | median |
|---|---|---|---|---|---|---|---|
| **claude-haiku-4.5** | 40/40 | 0/40 | **166** | **8.1** | 2 | 0 | **3.15 s** |
| gpt-5.6-luna | 40/40 | **40/40** | 105 | 7.3 | 1 | 0 | 4.23 s |

At 12 records, alongside them:

| model | schema | description Ø | tags Ø | invented | median |
|---|---|---|---|---|---|
| gemini-3.7-flash | 12/12 | 109 | 7.6 | **1** | 9.97 s |
| gpt-5.4-mini *(was configured)* | 12/12 | 115 | 7.3 | 0 | 5.15 s |

**`claude-haiku-4.5` is the recommendation**: fastest, longest descriptions, most tags, no invented
sources. `gpt-5.6-luna` is the alternative if bare JSON matters — it never fences.

`gemini-3.7-flash` is the worst combination here: three times the latency of Haiku, and the only
model that invented a source.

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

Nothing in the prompt. The configured model is worth changing in Settings. The benchmark script is
committed so the question can be re-asked when models change, rather than re-guessed.
