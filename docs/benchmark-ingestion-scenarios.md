# Benchmark ingestion scenarios

This document is the decoding guide for Qdrant collections created by
[`scripts/run_ingestion_scenarios.sh`](../scripts/run_ingestion_scenarios.sh).
Its purpose is to let someone identify the ingestion and RAG strategy from a
collection name before comparing benchmark results.

> Status: scaffold. The labels and command behavior below match the launcher.
> Fields marked **TBD** must be completed after the referenced `.env` and source
> YAML files are finalized. Do not put API keys or other secrets in this file.

## Scenario matrix

The launcher currently creates **16 scenarios per dataset**:

```text
4 embedding/generation environments
× 2 heading-splitting strategies
× 2 summary/parent strategies
= 16 collections per dataset
```

Every scenario is a fresh ingestion because the launcher always passes
`--drop-collection`. Runs are sequential and fail fast: a scenario starts only
after the preceding scenario succeeds.

## Collection-name format

```text
[PREFIX]<dataset>_<environment>_<heading-strategy>_<source-strategy>
```

For example:

```text
benchmark_utilitR_bge_gemma426b_heading_3_s3snt_parent_1kt
```

| Component | Decoded value |
|---|---|
| Optional prefix | `benchmark_` |
| Dataset/source key | `utilitR` |
| Environment | `bge_gemma426b` |
| Heading strategy | `heading_3` |
| Source strategy | `s3snt_parent_1kt` |

The optional prefix comes from `COLLECTION_PREFIX`. Dataset and prefix are not
self-delimiting, and labels themselves contain underscores. Therefore, do not
decode a name by splitting on every underscore. Match the known environment,
heading, and source suffixes from right to left. Record the prefix and dataset
separately in the benchmark manifest described below.

### Related collections

Depending on the selected source configuration, Agora can create collections
alongside the named main collection:

| Suffix | Contents | Retrieval role |
|---|---|---|
| no suffix | Embedded child chunks | Fine-grained retrieval |
| `_summaries` | Synthetic summary points | Summary-based retrieval |
| `_parents` | Payload-only parent chunks | Larger generation context |

Confirm which related collections exist for each source strategy after its YAML
file is finalized.

## Environment variants

An environment selects the embedding configuration and the model used to
generate synthetic summaries. The exact endpoint, provider, model identifier,
model revision, and dimensions come from the corresponding `.env` file and
must be recorded without exposing credentials.

| Collection label | Environment file | Intended embedding family | Intended summary generator | Provider | Exact model IDs and revisions |
|---|---|---|---|---|---|
| `bge_gemma426b` | `.emb.bge-m3.gen.ollama.gemma426b.env` | BGE-M3 | `gemma426b` | Ollama | **TBD** |
| `bge_qwen3_5_35b` | `.emb.bge-m3.gen.ollama.qwen3_5_35b.env` | BGE-M3 | `qwen3_5_35b` | Ollama | **TBD** |
| `nomic_gemma426b` | `.emb.nomic.gen.ollama.gemma426b.env` | Nomic | `gemma426b` | Ollama | **TBD** |
| `nomic_qwen3_5_35b` | `.emb.nomic.gen.ollama.qwen3_5_35b.env` | Nomic | `qwen3_5_35b` | Ollama | **TBD** |

Two additional OpenAI/GPT-4o mini environment variants are present but
commented out in the launcher. They are not part of the current 16-scenario
matrix and must not be reported as benchmarked unless enabled and ingested.

### Environment details to complete

For each active environment, record:

- `EMBED_MODEL` and an immutable model revision or artifact digest;
- dense-vector dimension and normalization behavior;
- enabled sparse or multi-vector encoders, if any;
- `LLM_MODEL`, immutable revision, temperature, and generation limits;
- provider/runtime and runtime version;
- endpoint class or deployment name, without credentials;
- relevant tokenizer and prompt-template versions.

## Heading-splitting variants

| Collection label | CLI option | Meaning |
|---|---|---|
| `heading_default` | Option omitted | Any Markdown heading-path change closes the current child chunk. |
| `heading_3` | `--split-heading-level 3` | Only a change to the active H3 section forces a child-chunk boundary. Token limits can still split content within an H3 section. Ancestor headings remain embedding context. |

Both modes use the launcher CLI defaults unless the command is later changed:

| Chunking parameter | Current value |
|---|---:|
| Target tokens | 800 |
| Maximum tokens | 1200 |
| Overlap tokens | 120 |

The default mode does **not** mean “no heading split.” It is the more
fine-grained mode in which every heading-path change can create a boundary.

## Source configuration variants

The source label describes the intended synthetic-summary and parent-chunk
policy. The YAML file remains authoritative; verify the descriptions below
against the final files before publishing benchmark results.

| Collection label | Source YAML | Intended summary size | Intended parent target | Other settings |
|---|---|---:|---:|---|
| `s3snt_parent_1kt` | `source.utilitR.sum_3_sent.parent_1000t.yml` | 3 sentences | 1,000 tokens | **TBD from YAML** |
| `s5snt_parent_2kt` | `source.utilitR.sum_5_sent.parent_2000t.yml` | 5 sentences | 2,000 tokens | **TBD from YAML** |

Complete the following for both source configurations:

- summary prompt and prompt version;
- summary grouping policy and input-token budget;
- keyword-generation behavior;
- `parent_storage_mode`;
- parent target, maximum, and overlap token values;
- included/excluded file globs and source commit;
- named-vector configuration;
- any setting that differs between the two YAML files besides summary length
  and parent size.

## Quick decoding procedure

Given a collection name:

1. Remove `_summaries` or `_parents`, if present, and record the collection
   role.
2. Match one of the source-strategy suffixes:
   `s3snt_parent_1kt` or `s5snt_parent_2kt`.
3. Match the preceding heading label: `heading_default` or `heading_3`.
4. Match the preceding environment label from the environment table.
5. Interpret the remaining text using the recorded dataset and optional
   `COLLECTION_PREFIX` from the benchmark manifest.
6. Verify the run manifest and configuration checksums. The collection name is
   a readable label, not a complete reproducibility record.

## Benchmark manifest template

Create one manifest per benchmark campaign. Commit it next to the evaluation
results, using a format such as YAML:

```yaml
campaign_id: TBD
created_at_utc: TBD
agora_git_commit: TBD
launcher_git_commit: TBD
collection_prefix: TBD
datasets:
  - source_key: utilitR
    content_git_commit: TBD

environments:
  bge_gemma426b:
    dotenv_sha256: TBD
    embed_model: TBD
    embed_model_revision: TBD
    vector_dimension: TBD
    summary_model: TBD
    summary_model_revision: TBD
    runtime: TBD

source_strategies:
  s3snt_parent_1kt:
    config_path: source.utilitR.sum_3_sent.parent_1000t.yml
    config_sha256: TBD
    summary_prompt_revision: TBD

ingestion:
  target_tokens: 800
  max_tokens: 1200
  overlap_tokens: 120
  drop_collection: true

evaluation:
  query_set: TBD
  query_set_revision: TBD
  retriever_configuration: TBD
  reranker_configuration: TBD
  generation_configuration: TBD
  metrics: []
```

Do not copy secrets into the manifest. A checksum of a secret-bearing `.env`
file can also disclose whether someone possesses the same file; store that
checksum only where the benchmark's security policy permits it. A safer public
alternative is a checksum of a separately maintained, redacted environment
descriptor.

## Reporting checklist

Before treating two scores as a strategy comparison, verify that:

- all 16 expected main collections completed successfully;
- related summary and parent collections exist where expected;
- document, child, summary, and parent point counts were captured;
- the same dataset revision and evaluation query set were used;
- retrieval depth, filters, reranking, and generation settings were held fixed
  unless they are the variable under test;
- configuration files and model revisions were recorded;
- failed or partial ingestions were excluded;
- latency and quality measurements identify warm/cold-cache conditions and the
  number of repetitions.

## Maintenance rule

The launcher is the source of truth for active matrix labels. Update this
document whenever `ENVIRONMENT_LABELS`, `HEADING_LABELS`,
`SOURCE_CONFIG_LABELS`, collection-name construction, or CLI chunking options
change. If the matrix size changes, update both the stated scenario count and
the benchmark manifest.
