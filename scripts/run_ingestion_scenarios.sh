#!/usr/bin/env bash

# Run the complete Agora ingestion matrix for one or more datasets.
#
# Before the first run, replace the five FILL_ME paths below. Each dataset is
# expected to be a source key present in both source configuration files.
#
# Usage:
#   scripts/run_ingestion_scenarios.sh DATASET [DATASET ...]
#
# Optional environment variables:
#   AGORA_INGEST_BIN=/path/to/agora-ingest  Command to execute.
#   COLLECTION_PREFIX=experiment_          Prefix for every collection.
#   DRY_RUN=1                               Print commands without running them.

set -Eeuo pipefail

readonly SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
readonly REPOSITORY_ROOT="$(cd -- "${SCRIPT_DIR}/.." && pwd)"

# Keep labels short: they become part of the Qdrant collection name.
readonly ENVIRONMENT_LABELS=(
  "bge_gemma426b"
  "bge_qwen3_5_35b"
  # "bge_gpt4o_mini"
  "nomic_gemma426b"
  "nomic_qwen3_5_35b"
  # "nomic_gpt4o_mini"
)
readonly DOTENV_PATHS=(
  ".emb.bge-m3.gen.ollama.gemma426b.env"
  ".emb.bge-m3.gen.ollama.qwen3_5_35b.env"
  # ".emb.bge-m3.gen.openai.gpt4o-mini.env"
  ".emb.nomic.gen.ollama.gemma426b.env"
  ".emb.nomic.gen.ollama.qwen3_5_35b.env"
  # ".emb.nomic.gen.openai.gpt4o-mini.env"
)

readonly SOURCE_CONFIG_LABELS=(
  "s3snt_parent_1kt"
  "s5snt_parent_2kt"
)
readonly SOURCE_CONFIG_PATHS=(
  "./source.utilitR.sum_3_sent.parent_1000t.yml"
  "./source.utilitR.sum_5_sent.parent_2000t.yml"
)

# An empty value deliberately omits --split-heading-level. The second variant
# explicitly splits on level-three headings.
readonly HEADING_LABELS=("heading_default" "heading_3")
readonly HEADING_LEVELS=("" "3")

readonly EXPECTED_SCENARIOS_PER_DATASET=16
readonly COLLECTION_PREFIX="${COLLECTION_PREFIX:-}"
readonly DRY_RUN="${DRY_RUN:-0}"

usage() {
  printf 'Usage: %s DATASET [DATASET ...]\n' "${0##*/}" >&2
}

resolve_from_repository() {
  local path="$1"
  if [[ "$path" = /* ]]; then
    printf '%s\n' "$path"
  else
    printf '%s/%s\n' "$REPOSITORY_ROOT" "$path"
  fi
}

collection_component() {
  local value="$1"
  value="${value//[^[:alnum:]_-]/_}"
  printf '%s\n' "$value"
}

print_command() {
  local argument
  printf '  '
  for argument in "$@"; do
    printf '%q ' "$argument"
  done
  printf '\n'
}

if (( $# == 0 )); then
  usage
  exit 2
fi

if (( ${#ENVIRONMENT_LABELS[@]} != ${#DOTENV_PATHS[@]} )); then
  printf 'Error: environment labels and paths must have the same length.\n' >&2
  exit 2
fi
if (( ${#SOURCE_CONFIG_LABELS[@]} != ${#SOURCE_CONFIG_PATHS[@]} )); then
  printf 'Error: source-config labels and paths must have the same length.\n' >&2
  exit 2
fi

scenario_count=$((
  ${#DOTENV_PATHS[@]}
  * ${#HEADING_LEVELS[@]}
  * ${#SOURCE_CONFIG_PATHS[@]}
))
if (( scenario_count != EXPECTED_SCENARIOS_PER_DATASET )); then
  printf 'Error: the scenario matrix contains %d runs; expected %d.\n' \
    "$scenario_count" "$EXPECTED_SCENARIOS_PER_DATASET" >&2
  exit 2
fi

if [[ -n "${AGORA_INGEST_BIN:-}" ]]; then
  ingest_bin="$AGORA_INGEST_BIN"
elif [[ -x "${REPOSITORY_ROOT}/.venv/bin/agora-ingest" ]]; then
  ingest_bin="${REPOSITORY_ROOT}/.venv/bin/agora-ingest"
else
  ingest_bin="agora-ingest"
fi

if [[ "$ingest_bin" == */* ]]; then
  if [[ ! -x "$ingest_bin" ]]; then
    printf 'Error: Agora ingestion command is not executable: %s\n' "$ingest_bin" >&2
    exit 2
  fi
elif ! command -v "$ingest_bin" >/dev/null 2>&1; then
  printf 'Error: Agora ingestion command was not found: %s\n' "$ingest_bin" >&2
  exit 2
fi

# Validate the shared files before starting, avoiding a partially completed
# dataset caused by a placeholder or typo.
for configured_path in "${DOTENV_PATHS[@]}" "${SOURCE_CONFIG_PATHS[@]}"; do
  resolved_path="$(resolve_from_repository "$configured_path")"
  if [[ ! -f "$resolved_path" ]]; then
    printf 'Error: configure an existing file in this script: %s\n' \
      "$configured_path" >&2
    exit 2
  fi
done

for dataset in "$@"; do
  dataset_label="$(collection_component "$dataset")"
  if [[ -z "$dataset_label" ]]; then
    printf 'Error: dataset name cannot produce an empty collection name: %s\n' \
      "$dataset" >&2
    exit 2
  fi

  run_number=0
  printf 'Dataset %s: running %d ingestion scenarios\n' \
    "$dataset" "$EXPECTED_SCENARIOS_PER_DATASET"

  for environment_index in "${!DOTENV_PATHS[@]}"; do
    dotenv_path="$(resolve_from_repository "${DOTENV_PATHS[$environment_index]}")"
    environment_label="$(collection_component "${ENVIRONMENT_LABELS[$environment_index]}")"

    for heading_index in "${!HEADING_LEVELS[@]}"; do
      heading_level="${HEADING_LEVELS[$heading_index]}"
      heading_label="$(collection_component "${HEADING_LABELS[$heading_index]}")"

      for source_index in "${!SOURCE_CONFIG_PATHS[@]}"; do
        source_config_path="$(
          resolve_from_repository "${SOURCE_CONFIG_PATHS[$source_index]}"
        )"
        source_config_label="$(
          collection_component "${SOURCE_CONFIG_LABELS[$source_index]}"
        )"
        collection_name="${COLLECTION_PREFIX}${dataset_label}_${environment_label}_${heading_label}_${source_config_label}"

        command=(
          "$ingest_bin"
          --sources-config-path "$source_config_path"
          --source "$dataset"
          --collection "$collection_name"
          --dotenv-path "$dotenv_path"
          --drop-collection
        )
        if [[ -n "$heading_level" ]]; then
          command+=(--split-heading-level "$heading_level")
        fi

        ((run_number += 1))
        printf '[%02d/%02d] %s\n' \
          "$run_number" "$EXPECTED_SCENARIOS_PER_DATASET" "$collection_name"
        print_command "${command[@]}"

        # set -e makes the matrix a fail-fast chain: scenario N+1 starts only
        # when scenario N succeeds. Collection dropping is intentionally fixed.
        if [[ "$DRY_RUN" != "1" ]]; then
          "${command[@]}"
        fi
      done
    done
  done
done
