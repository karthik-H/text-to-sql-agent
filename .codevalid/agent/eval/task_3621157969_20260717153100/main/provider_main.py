from __future__ import annotations

import json
import os
import sys
from copy import deepcopy
from pathlib import Path
from typing import Any
from unittest.mock import patch

from opentelemetry import trace
from opentelemetry.sdk.trace import TracerProvider
from opentelemetry.sdk.trace.export import SimpleSpanProcessor
from opentelemetry.sdk.trace.export.in_memory_span_exporter import InMemorySpanExporter

WORKSPACE_ROOT = Path(__file__).resolve().parents[5]
if str(WORKSPACE_ROOT) not in sys.path:
    sys.path.insert(0, str(WORKSPACE_ROOT))

import agent as target_agent

try:
    from opentelemetry.instrumentation.langchain import LangChainInstrumentor
except Exception:  # pragma: no cover
    from openinference.instrumentation.langchain import LangChainInstrumentor

_exporter = InMemorySpanExporter()
_provider = TracerProvider()
_provider.add_span_processor(SimpleSpanProcessor(_exporter))
try:
    trace.set_tracer_provider(_provider)
except Exception:
    pass

_instrumentor = LangChainInstrumentor()
_INSTRUMENTED = False
try:
    _instrumentor.instrument(tracer_provider=_provider)
    _INSTRUMENTED = True
except Exception:
    _INSTRUMENTED = False

_ENV_BASELINE = {
    key: os.environ.get(key)
    for key in [
        "OPENAI_API_BASE",
        "OPENAI_BASE_URL",
        "OPENAI_API_KEY",
        "ANTHROPIC_API_KEY",
        "ANTHROPIC_BASE_URL",
    ]
}
_PATCHERS: list[Any] = []


def _extract_vars(options: dict | None, context: dict | None) -> dict:
    options = options or {}
    context = context or {}
    merged: dict[str, Any] = {}
    for candidate in [
        context.get("vars"),
        options.get("vars"),
        context.get("variables"),
        options.get("variables"),
    ]:
        if isinstance(candidate, dict):
            merged.update(candidate)
    if isinstance(options.get("config"), dict) and isinstance(options["config"].get("vars"), dict):
        merged.update(options["config"]["vars"])
    return merged


def _get_test_case_id(options: dict | None, context: dict | None) -> str:
    vars_ = _extract_vars(options, context)
    value = vars_.get("test_case_id")
    return "" if value is None else str(value)


def _get_precondition(options: dict | None, context: dict | None) -> Any:
    vars_ = _extract_vars(options, context)
    if "precondition" in vars_:
        return vars_.get("precondition")
    return vars_.get("preconditions")


def _seed_simple_count_query_execution() -> None:
    return None


def _seed_top_selling_artists_with_ordering() -> None:
    return None


def _seed_employee_revenue_performance_query() -> None:
    return None


def _seed_filtered_query_with_where_clause() -> None:
    return None


def _seed_query_without_hallucinated_columns() -> None:
    return None


def _seed_aggregate_query_with_group_by() -> None:
    return None


def _seed_schema_discovery_for_table_names() -> None:
    return None


def _seed_ambiguous_question_requires_clarification() -> None:
    return None


def _seed_schema_inspection_before_complex_query() -> None:
    return None


def setup_dependencies(test_case_id: str, precondition: Any, config: dict | None) -> None:
    _ = precondition
    _ = config or {}
    dispatch = {
        "simple_count_query_execution": _seed_simple_count_query_execution,
        "top_selling_artists_with_ordering": _seed_top_selling_artists_with_ordering,
        "employee_revenue_performance_query": _seed_employee_revenue_performance_query,
        "filtered_query_with_where_clause": _seed_filtered_query_with_where_clause,
        "query_without_hallucinated_columns": _seed_query_without_hallucinated_columns,
        "aggregate_query_with_group_by": _seed_aggregate_query_with_group_by,
        "schema_discovery_for_table_names": _seed_schema_discovery_for_table_names,
        "ambiguous_question_requires_clarification": _seed_ambiguous_question_requires_clarification,
        "schema_inspection_before_complex_query": _seed_schema_inspection_before_complex_query,
    }
    seed_fn = dispatch.get(test_case_id)
    if seed_fn is not None:
        seed_fn()


def cleanup_dependencies() -> None:
    global _PATCHERS
    while _PATCHERS:
        patcher = _PATCHERS.pop()
        try:
            patcher.stop()
        except Exception:
            pass
    for key, value in _ENV_BASELINE.items():
        if value is None:
            os.environ.pop(key, None)
        else:
            os.environ[key] = value


class _PatchedChatAnthropic:
    def __new__(cls, *args: Any, **kwargs: Any) -> Any:
        model_name = os.environ["LITELLM_MODEL"]
        base_url = os.environ["LITELLM_BASE_URL"]
        api_key = os.environ["LITELLM_API_KEY"]
        os.environ["OPENAI_API_BASE"] = base_url
        os.environ["OPENAI_BASE_URL"] = base_url
        os.environ["OPENAI_API_KEY"] = api_key
        try:
            from langchain_openai import ChatOpenAI
        except Exception:
            from langchain_openai.chat_models import ChatOpenAI
        temperature = kwargs.get("temperature", 0)
        return ChatOpenAI(model=model_name, temperature=temperature, api_key=api_key, base_url=base_url)


def _configure_model_env(config: dict | None) -> str:
    config = config or {}
    model_name = config.get("model")
    if not model_name:
        raise ValueError("Promptfoo provider config.model is required")
    os.environ["LITELLM_MODEL"] = str(model_name)
    os.environ["OPENAI_API_BASE"] = os.environ["LITELLM_BASE_URL"]
    os.environ["OPENAI_BASE_URL"] = os.environ["LITELLM_BASE_URL"]
    os.environ["OPENAI_API_KEY"] = os.environ["LITELLM_API_KEY"]
    return str(model_name)


def _build_agent(config: dict | None) -> Any:
    _configure_model_env(config)
    patcher = patch.object(target_agent, "ChatAnthropic", _PatchedChatAnthropic)
    patcher.start()
    _PATCHERS.append(patcher)
    return target_agent.create_sql_agent()


def _extract_text_from_message_like(value: Any) -> str | None:
    if value is None:
        return None
    content = getattr(value, "content", None)
    if isinstance(content, str):
        return content
    if isinstance(content, list):
        parts: list[str] = []
        for item in content:
            if isinstance(item, str):
                parts.append(item)
            elif isinstance(item, dict):
                text = item.get("text") or item.get("content")
                if text:
                    parts.append(str(text))
        if parts:
            return "\n".join(parts)
    return None


def _coerce_answer(result: Any) -> str:
    direct = _extract_text_from_message_like(result)
    if direct:
        return direct
    if isinstance(result, str):
        return result
    if isinstance(result, dict):
        for key in ("output", "answer", "content"):
            if key in result and result[key] is not None:
                nested = _coerce_answer(result[key])
                if nested:
                    return nested
        messages = result.get("messages")
        if isinstance(messages, list) and messages:
            nested = _coerce_answer(messages[-1])
            if nested:
                return nested
    if isinstance(result, list) and result:
        nested = _coerce_answer(result[-1])
        if nested:
            return nested
    return str(result)


def _normalize_attr_value(value: Any) -> Any:
    if isinstance(value, (str, int, float, bool)) or value is None:
        return value
    if isinstance(value, (list, tuple)):
        return [_normalize_attr_value(v) for v in value]
    if isinstance(value, dict):
        return {str(k): _normalize_attr_value(v) for k, v in value.items()}
    return str(value)


def _map_genai_attributes(attributes: dict[str, Any]) -> dict[str, Any]:
    mapped: dict[str, Any] = {}
    alias_groups = {
        "gen_ai.system": ["gen_ai.system", "llm.system", "provider", "model.provider"],
        "gen_ai.request.model": [
            "gen_ai.request.model",
            "llm.request.model",
            "llm.model_name",
            "model",
            "response.model",
            "openinference.llm.model_name",
        ],
        "gen_ai.response.model": ["gen_ai.response.model", "llm.response.model", "response.model"],
        "gen_ai.operation.name": [
            "gen_ai.operation.name",
            "llm.operation.name",
            "openinference.span.kind",
            "gen_ai.span.kind",
        ],
        "gen_ai.prompt": [
            "gen_ai.prompt",
            "input.value",
            "llm.prompts",
            "prompt",
            "gen_ai.input.messages",
        ],
        "gen_ai.completion": [
            "gen_ai.completion",
            "output.value",
            "response",
            "completion",
            "gen_ai.output.messages",
        ],
        "gen_ai.usage.input_tokens": [
            "gen_ai.usage.input_tokens",
            "llm.token_count.prompt",
            "usage.prompt_tokens",
            "input_tokens",
            "prompt_tokens",
        ],
        "gen_ai.usage.output_tokens": [
            "gen_ai.usage.output_tokens",
            "llm.token_count.completion",
            "usage.completion_tokens",
            "output_tokens",
            "completion_tokens",
        ],
    }
    for target_key, aliases in alias_groups.items():
        for alias in aliases:
            if alias in attributes and attributes[alias] not in (None, "", [], {}):
                mapped[target_key] = _normalize_attr_value(attributes[alias])
                break
    return mapped


def _span_to_node(span: Any) -> dict[str, Any]:
    attrs = {str(k): _normalize_attr_value(v) for k, v in dict(span.attributes or {}).items()}
    parent_span_id = span.parent.span_id if span.parent is not None else None
    node = {
        "name": span.name,
        "span_id": str(span.context.span_id),
        "parent_span_id": None if parent_span_id is None else str(parent_span_id),
        "attributes": attrs,
        "gen_ai_attributes": _map_genai_attributes(attrs),
        "children": [],
    }
    return node


def _spans_to_tree(spans: list[Any], *, exclude_names: set[str]) -> list[dict[str, Any]]:
    filtered = sorted([s for s in spans if s.name not in exclude_names], key=lambda s: s.start_time or 0)
    nodes = {s.context.span_id: _span_to_node(s) for s in filtered}
    child_ids: dict[int, list[int]] = {}
    roots: list[int] = []
    span_ids = set(nodes)
    for s in filtered:
        sid = s.context.span_id
        parent = s.parent.span_id if s.parent is not None else None
        if parent is not None and parent in span_ids:
            child_ids.setdefault(parent, []).append(sid)
        else:
            roots.append(sid)

    def attach(span_id: int) -> dict[str, Any]:
        node = deepcopy(nodes[span_id])
        node["children"] = [attach(child_id) for child_id in child_ids.get(span_id, [])]
        return node

    return [attach(root_id) for root_id in roots]


def _build_trace(user_input: str, answer: str, spans: list[Any]) -> dict[str, Any]:
    return {
        "type": "user_input",
        "input": user_input,
        "output": answer,
        "children": _spans_to_tree(spans, exclude_names={"user_input"}),
    }


def _invoke_agent(prompt: str, config: dict | None) -> tuple[str, dict[str, Any]]:
    agent = _build_agent(config)
    _exporter.clear()
    tracer = trace.get_tracer("codevalid.promptfoo.agent_eval")
    with tracer.start_as_current_span("user_input") as root_span:
        root_span.set_attribute("input", prompt)
        result = agent.invoke({"messages": [{"role": "user", "content": prompt}]})
        answer = _coerce_answer(result)
        root_span.set_attribute("output", answer)
    spans = list(_exporter.get_finished_spans())
    trace_tree = _build_trace(prompt, answer, spans)
    return answer, trace_tree


def call_api(prompt: str, options: dict, context: dict) -> dict:
    options = options or {}
    context = context or {}
    config = options.get("config", {}) or {}
    test_case_id = _get_test_case_id(options, context)
    precondition = _get_precondition(options, context)
    setup_dependencies(test_case_id, precondition, config)
    try:
        answer, trace_tree = _invoke_agent(prompt, config)
        return {"output": json.dumps({"answer": answer, "trace": trace_tree}, ensure_ascii=False)}
    finally:
        cleanup_dependencies()
        if _INSTRUMENTED:
            try:
                _instrumentor.uninstrument()
            except Exception:
                pass
