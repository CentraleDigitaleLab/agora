from __future__ import annotations

from collections.abc import Callable

LLM_SUMMARY_RETRIEVAL_NOT_IMPLEMENTED = (
    "LLM Summary Retrieval ingestion strategy is registered but summary "
    "generation is not implemented yet. This will be implemented in stories "
    "#42 and #43."
)


class DefaultIngestionStrategy:
    uses_default_pipeline = True


class LLMSummaryRetrievalIngestionStrategy:
    uses_default_pipeline = False

    def run(self) -> None:
        # Intentionally a stub until grouping and summary generation land.
        raise NotImplementedError(LLM_SUMMARY_RETRIEVAL_NOT_IMPLEMENTED)


IngestionStrategyFactory = Callable[[], object]
_REGISTRY: dict[bool, IngestionStrategyFactory] = {}


def register_ingestion_strategy(
    llm_summary_retrieval: bool,
    factory: IngestionStrategyFactory,
) -> None:
    _REGISTRY[llm_summary_retrieval] = factory


def get_ingestion_strategy_registry() -> dict[bool, IngestionStrategyFactory]:
    return dict(_REGISTRY)


def select_ingestion_strategy(config: object) -> object:
    enabled = getattr(config, "llm_summary_retrieval", False)
    if type(enabled) is not bool:
        raise ValueError(
            f"Unsupported llm_summary_retrieval value for ingestion strategy: {enabled!r}"
        )
    try:
        factory = _REGISTRY[enabled]
    except KeyError as exc:
        raise ValueError(
            f"Unsupported llm_summary_retrieval value for ingestion strategy: {enabled!r}"
        ) from exc
    return factory()


register_ingestion_strategy(False, DefaultIngestionStrategy)
register_ingestion_strategy(True, LLMSummaryRetrievalIngestionStrategy)
