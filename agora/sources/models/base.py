from __future__ import annotations

from typing import Annotated, Literal

from pydantic import BaseModel, Field, field_validator, model_validator


class DenseVectorConfig(BaseModel):
    name: str = "dense"
    kind: Literal["dense"] = "dense"
    size: int | None = None
    distance: Literal["cosine"] = "cosine"
    model: str | None = None


class SparseVectorConfig(BaseModel):
    name: str = "sparse"
    kind: Literal["sparse"] = "sparse"
    provider: Literal["fastembed"] = "fastembed"
    model: str = "Qdrant/bm25"
    modifier: Literal["idf", "none"] = "idf"
    language: str | None = None
    disable_stemmer: bool = False


class MultiVectorConfig(BaseModel):
    name: str = "multi"
    kind: Literal["multi"] = "multi"
    provider: Literal["fastembed"] = "fastembed"
    model: str = "answerdotai/answerai-colbert-small-v1"
    size: int | None = None
    distance: Literal["cosine"] = "cosine"
    comparator: Literal["max_sim"] = "max_sim"


VectorModeConfig = Annotated[
    DenseVectorConfig | SparseVectorConfig | MultiVectorConfig,
    Field(discriminator="kind"),
]


class VectorIndexConfig(BaseModel):
    vectors: list[VectorModeConfig] = Field(
        default_factory=lambda: [DenseVectorConfig()]
    )

    @model_validator(mode="after")
    def _check_unique_names(self):
        names = [v.name for v in self.vectors]
        if not names:
            raise ValueError("vector_index must configure at least one vector")
        if len(names) != len(set(names)):
            raise ValueError("vector_index vector names must be unique")
        return self


class IngestionStrategyConfig(BaseModel):
    llm_summary_retrieval: bool = False
    summary_model: object = "gemma"
    summary_granularity: object = "chapter"
    max_summary_length: object = 5
    index_raw_chunks: object = True

    @field_validator("llm_summary_retrieval", mode="before")
    @classmethod
    def _validate_llm_summary_retrieval(cls, value: object) -> bool:
        if type(value) is not bool:
            raise ValueError("llm_summary_retrieval must be a boolean.")
        return value

    @model_validator(mode="after")
    def _validate_llm_summary_retrieval_options(self):
        if not self.llm_summary_retrieval:
            return self

        if self.summary_model != "gemma":
            raise ValueError(
                "summary_model must be 'gemma' when llm_summary_retrieval is enabled."
            )
        if self.summary_granularity != "chapter":
            raise ValueError(
                "summary_granularity must be 'chapter' when "
                "llm_summary_retrieval is enabled."
            )
        if type(self.max_summary_length) is not int or self.max_summary_length <= 0:
            raise ValueError(
                "max_summary_length must be a positive integer representing the "
                "maximum number of sentences per summary."
            )
        if type(self.index_raw_chunks) is not bool:
            raise ValueError("index_raw_chunks must be a boolean.")
        if self.index_raw_chunks is False:
            raise ValueError(
                "index_raw_chunks=False is not supported when "
                "llm_summary_retrieval is enabled."
            )
        return self


class SourceDefaults(BaseModel):
    """Cross-kind defaults (safe for any file-based source)."""

    include_globs: list[str] = ["**/*.md", "**/*.qmd", "**/*.Rmd"]
    exclude_dirs: list[str] = [
        ".git",
        "_book",
        "docs",
        ".quarto",
        "renv",
        ".github",
        "node_modules",
        "build",
        "dist",
        "site",
    ]
    default_lang: str = "en"
    follow_symlinks: bool = False


class SourcesConfig(IngestionStrategyConfig):
    """Top-level configuration with shared defaults and named sources.

    `sources` is a mapping: source name -> typed config (discriminated by `kind`).
    The discriminated union is assembled in the loader, so we keep the field
    shape here and let the loader fill the type info.
    """

    version: int = 1
    vector_index: VectorIndexConfig = Field(default_factory=VectorIndexConfig)
    defaults: SourceDefaults = Field(default_factory=SourceDefaults)
    # The loader will parse this into a discriminated union.
    sources: dict[str, dict]
