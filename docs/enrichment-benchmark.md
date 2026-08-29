# AI enrichment benchmark — 2026-08-29

The enrichment prompt had never been measured. It describes its JSON schema in prose and the client
strips ```` ```json ```` fences by hand, which looks dated beside structured outputs — so the
obvious "modernisation" was to replace it with `response_format: {type: "json_schema"}`.

That would have broken the feature. This is what measuring found instead.

Reproduce with `scripts/bench-enrichment.py`, which reads real records from the installed library
rather than invented ones.

## Method

40 records sampled from a real 1,024-file library (12 used per run). Each response scored on:

| | |
|---|---|
| **parse** | is the response JSON at all, before and after fence-stripping |
| **schema** | all 11 keys present, `printability` within its enum, `tags` a list of 5–12 |
| **discipline** | are `sourcePlatform`/`Author`/`License`/`URL` null unless the input evidenced them — an invented source is worse than none, because it gets stored and shown as fact |
| **latency** | wall clock per record |

## Structured outputs are not usable here

| variant | JSON direct | after strip | schema |
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

| model | returns bare JSON |
|---|---|
| gpt-5.4-mini | 12/12 |
| gpt-4o-mini | 7/12 |
| gemini-3.7-flash | 5/12 |
| claude-haiku-4.5 | **0/12** |

Every model produces schema-valid JSON *after* stripping. Claude fences every single response.
Removing the fence-stripping as "no longer needed" would break that model completely.

## The prompt itself needs no change

Across all four models: **12/12 schema conformance, 0 invented sources.** The injection delimiters,
the enumerated keys and the "use null when not evidenced" rule all hold. There was nothing to fix.

## Model choice is the real lever

| model | description Ø | shortest | tags Ø | unusable | median |
|---|---|---|---|---|---|
| gpt-5.4-mini *(configured)* | 115 chars | 61 | 7.3 | 0/12 | 5.15 s |
| **claude-haiku-4.5** | **129** | 31 | **7.6** | **0/12** | **2.62 s** |
| gpt-4o-mini | 122 | **8** | 5.8 | **3/12** | 1.17 s |

`claude-haiku-4.5` is twice as fast as the configured model with equal reliability and slightly
richer output.

`gpt-4o-mini` is the trap: fastest by far, and the one that returned `"Boost Me"` as a description.
Schema conformance alone would have scored it 12/12 and recommended it. Latency and schema
validity are not quality.

## What changed as a result

Nothing in the prompt. The configured model is worth changing in Settings; the benchmark script is
committed so the question can be re-asked when models change, rather than re-guessed.
