import copy
import json
import os
import sys
from pathlib import Path
from typing import Any, Dict, List

WORKSPACE_ROOT = Path("/workspace/agents")
if str(WORKSPACE_ROOT) not in sys.path:
    sys.path.insert(0, str(WORKSPACE_ROOT))

os.environ.setdefault("OTEL_INSTRUMENTATION_GENAI_CAPTURE_MESSAGE_CONTENT", "SPAN_ONLY")

import agent as agent_module
from langchain_openai import ChatOpenAI
from opentelemetry import trace
from opentelemetry.instrumentation.genai.langchain import LangChainInstrumentor
from opentelemetry.sdk.trace import TracerProvider
from opentelemetry.sdk.trace.export import SimpleSpanProcessor
from opentelemetry.sdk.trace.export.in_memory_span_exporter import InMemorySpanExporter

_DB_PATH = WORKSPACE_ROOT / "chinook.db"
_DB_EXISTS_AT_IMPORT = _DB_PATH.exists()
_ORIGINAL_CHAT_ANTHROPIC = getattr(agent_module, "ChatAnthropic", None)
_PATCH_STATE: Dict[str, Any] = {"active": False, "patched": []}


def _seed_happy_path_simple_artist_query(test_case_id: str, precondition: Any, config: Dict[str, Any]) -> None:
    return


def _seed_happy_path_employee_revenue_query(test_case_id: str, precondition: Any, config: Dict[str, Any]) -> None:
    return


def _seed_happy_path_customer_count_query(test_case_id: str, precondition: Any, config: Dict[str, Any]) -> None:
    return


def _seed_tool_selection_similar_domain_queries(test_case_id: str, precondition: Any, config: Dict[str, Any]) -> None:
    return


def _seed_edge_case_query_returns_no_results(test_case_id: str, precondition: Any, config: Dict[str, Any]) -> None:
    return


def _seed_error_handling_invalid_column_reference(test_case_id: str, precondition: Any, config: Dict[str, Any]) -> None:
    return


def _seed_edge_case_complex_multi_table_join(test_case_id: str, precondition: Any, config: Dict[str, Any]) -> None:
    return


def _seed_validation_sql_injection_prevention(test_case_id: str, precondition: Any, config: Dict[str, Any]) -> None:
    return


def _seed_missing_info_ambiguous_question(test_case_id: str, precondition: Any, config: Dict[str, Any]) -> None:
    return


def _seed_happy_path_album_details_with_artist(test_case_id: str, precondition: Any, config: Dict[str, Any]) -> None:
    return


_SEED_DISPATCH = {
    "happy_path_simple_artist_query": _seed_happy_path_simple_artist_query,
    "happy_path_employee_revenue_query": _seed_happy_path_employee_revenue_query,
    "happy_path_customer_count_query": _seed_happy_path_customer_count_query,
    "tool_selection_similar_domain_queries": _seed_tool_selection_similar_domain_queries,
    "edge_case_query_returns_no_results": _seed_edge_case_query_returns_no_results,
    "error_handling_invalid_column_reference": _seed_error_handling_invalid_column_reference,
    "edge_case_complex_multi_table_join": _seed_edge_case_complex_multi_table_join,
    "validation_sql_injection_prevention": _seed_validation_sql_injection_prevention,
    "missing_info_ambiguous_question": _seed_missing_info_ambiguous_question,
    "happy_path_album_details_with_artist": _seed_happy_path_album_details_with_artist,
}


def setup_dependencies(test_case_id: str, precondition: Any, config: Dict[str, Any]) -> None:
    if not _DB_EXISTS_AT_IMPORT or not _DB_PATH.exists():
        raise FileNotFoundError(f"Expected SQLite database at {_DB_PATH}")
    seed_fn = _SEED_DISPATCH.get(test_case_id)
    if seed_fn is None:
        raise ValueError(f"Unknown test_case_id for setup: {test_case_id}")
    seed_fn(test_case_id, precondition, config)


def cleanup_dependencies() -> None:
    _restore_agent_factory()
    if _DB_EXISTS_AT_IMPORT and not _DB_PATH.exists():
        raise RuntimeError(f"SQLite database was unexpectedly removed: {_DB_PATH}")


def _build_llm(config: Dict[str, Any]) -> ChatOpenAI:
    model_name = config.get("model")
    if not model_name:
        raise ValueError("Missing required options.config.model")
    base_url = os.environ["LITELLM_BASE_URL"]
    api_key = os.environ["LITELLM_API_KEY"]
    return ChatOpenAI(
        model=model_name,
        temperature=0,
        api_key=api_key,
        base_url=base_url,
    )


class _PatchedChatAnthropic:
    def __new__(cls, *args: Any, **kwargs: Any) -> ChatOpenAI:
        config = copy.deepcopy(_PATCH_STATE.get("config") or {})
        return _build_llm(config)


def _patch_agent_factory(config: Dict[str, Any]) -> None:
    _restore_agent_factory()
    _PATCH_STATE["config"] = copy.deepcopy(config or {})
    _PATCH_STATE["patched"] = []
    if hasattr(agent_module, "ChatAnthropic"):
        _PATCH_STATE["patched"].append((agent_module, "ChatAnthropic", getattr(agent_module, "ChatAnthropic")))
        agent_module.ChatAnthropic = _PatchedChatAnthropic
    _PATCH_STATE["active"] = True


def _restore_agent_factory() -> None:
    patched = _PATCH_STATE.get("patched") or []
    for module_obj, attr_name, original in reversed(patched):
        setattr(module_obj, attr_name, original)
    _PATCH_STATE["patched"] = []
    _PATCH_STATE["active"] = False
    _PATCH_STATE.pop("config", None)
    if _ORIGINAL_CHAT_ANTHROPIC is not None:
        agent_module.ChatAnthropic = _ORIGINAL_CHAT_ANTHROPIC


def _serialize_value(value: Any) -> Any:
    if value is None:
        return None
    if isinstance(value, (str, int, float, bool)):
        return value
    if isinstance(value, bytes):
        return value.decode("utf-8", errors="replace")
    if isinstance(value, dict):
        return {str(k): _serialize_value(v) for k, v in value.items()}
    if isinstance(value, (list, tuple, set)):
        return [_serialize_value(v) for v in value]
    content = getattr(value, "content", None)
    if content is not None:
        return _serialize_value(content)
    additional_kwargs = getattr(value, "additional_kwargs", None)
    if additional_kwargs is not None:
        return {
            "content": _serialize_value(content),
            "additional_kwargs": _serialize_value(additional_kwargs),
        }
    if hasattr(value, "model_dump"):
        try:
            return _serialize_value(value.model_dump())
        except Exception:
            pass
    if hasattr(value, "dict"):
        try:
            return _serialize_value(value.dict())
        except Exception:
            pass
    return str(value)


def _coerce_text(value: Any) -> str:
    if value is None:
        return ""
    if isinstance(value, str):
        return value
    if isinstance(value, list):
        parts: List[str] = []
        for item in value:
            if isinstance(item, str):
                parts.append(item)
            elif isinstance(item, dict):
                text_part = item.get("text") or item.get("content") or item.get("value")
                if text_part is not None:
                    parts.append(_coerce_text(text_part))
                else:
                    parts.append(json.dumps(_serialize_value(item), ensure_ascii=False))
            else:
                nested = getattr(item, "text", None)
                if nested is not None:
                    parts.append(_coerce_text(nested))
                else:
                    nested_content = getattr(item, "content", None)
                    if nested_content is not None and nested_content is not value:
                        parts.append(_coerce_text(nested_content))
                    else:
                        parts.append(str(item))
        return "\n".join(part for part in parts if part)
    if isinstance(value, dict):
        for key in ("answer", "output", "content", "text", "result"):
            if key in value:
                return _coerce_text(value[key])
        if "messages" in value and value["messages"]:
            return _coerce_text(value["messages"][-1])
        return json.dumps(_serialize_value(value), ensure_ascii=False)
    content = getattr(value, "content", None)
    if content is not None and content is not value:
        return _coerce_text(content)
    if hasattr(value, "text"):
        text = getattr(value, "text")
        if text is not None:
            return _coerce_text(text)
    return str(value)


def _extract_answer(result: Any) -> str:
    if isinstance(result, dict):
        messages = result.get("messages")
        if isinstance(messages, list) and messages:
            return _coerce_text(messages[-1]).strip()
        for key in ("output", "answer", "result", "content"):
            if key in result:
                text = _coerce_text(result[key]).strip()
                if text:
                    return text
    text = _coerce_text(result).strip()
    return text


def _map_gen_ai(attrs: Dict[str, Any]) -> Dict[str, Any]:
    candidates = {
        "system": ["gen_ai.system", "llm.system"],
        "operation_name": ["gen_ai.operation.name"],
        "request_model": ["gen_ai.request.model", "llm.request.model"],
        "prompt": ["gen_ai.prompt", "llm.prompts", "input.value", "input"],
        "completion": ["gen_ai.completion", "llm.output_messages", "output.value", "output"],
        "tool_name": ["gen_ai.tool.name", "tool.name"],
        "input": ["input.value", "input", "gen_ai.input.messages", "gen_ai.tool.call.arguments"],
        "output": ["output.value", "output", "gen_ai.output.messages", "gen_ai.tool.call.result"],
    }
    mapped: Dict[str, Any] = {}
    for stable_key, keys in candidates.items():
        for key in keys:
            if key in attrs and attrs[key] is not None:
                mapped[stable_key] = _serialize_value(attrs[key])
                break
    return mapped


def _span_kind(operation_name: str, span_name: str, gen_ai: Dict[str, Any]) -> str:
    op = (operation_name or "").lower()
    name = (span_name or "").lower()
    tool_name = str(gen_ai.get("tool_name") or "").lower()
    if "tool" in op or "tool" in name or tool_name:
        return "tool"
    if op in {"chat", "completion", "generate"} or "llm" in name or "chat" in name:
        return "llm"
    if "agent" in op or "workflow" in op or "agent" in name or "chain" in name:
        return "agent"
    return "span"


def _span_to_node(span: Any) -> Dict[str, Any]:
    attrs = dict(getattr(span, "attributes", {}) or {})
    serialized_attrs = {str(k): _serialize_value(v) for k, v in attrs.items()}
    gen_ai = _map_gen_ai(attrs)
    operation_name = str(gen_ai.get("operation_name") or attrs.get("gen_ai.operation.name") or "")
    node_type = _span_kind(operation_name, getattr(span, "name", ""), gen_ai)
    node: Dict[str, Any] = {
        "type": node_type,
        "name": getattr(span, "name", ""),
        "span_id": format(getattr(getattr(span, "context", None), "span_id", 0), "x"),
        "attributes": serialized_attrs,
        "gen_ai": gen_ai,
        "children": [],
    }
    if node_type == "tool":
        tool_name = gen_ai.get("tool_name") or serialized_attrs.get("gen_ai.tool.name") or serialized_attrs.get("tool.name")
        if tool_name:
            node["name"] = tool_name
    if gen_ai.get("input") is not None:
        node["input"] = gen_ai.get("input")
    elif gen_ai.get("prompt") is not None:
        node["input"] = gen_ai.get("prompt")
    if gen_ai.get("output") is not None:
        node["output"] = gen_ai.get("output")
    elif gen_ai.get("completion") is not None:
        node["output"] = gen_ai.get("completion")
    return node


def _spans_to_tree(spans: List[Any], *, exclude_names: set[str]) -> List[Dict[str, Any]]:
    filtered = sorted(
        [s for s in spans if getattr(s, "name", "") not in exclude_names],
        key=lambda s: getattr(s, "start_time", 0) or 0,
    )
    nodes = {s.context.span_id: _span_to_node(s) for s in filtered}
    child_ids: Dict[int, List[int]] = {}
    roots: List[int] = []
    span_ids = set(nodes)

    for s in filtered:
        sid = s.context.span_id
        parent = s.parent.span_id if getattr(s, "parent", None) is not None else None
        if parent is not None and parent in span_ids:
            child_ids.setdefault(parent, []).append(sid)
        else:
            roots.append(sid)

    def attach(sid: int) -> Dict[str, Any]:
        node = nodes[sid]
        node["children"] = [attach(cid) for cid in child_ids.get(sid, [])]
        return node

    return [attach(rid) for rid in roots]


def _build_trace(user_input: str, answer: str, spans: List[Any]) -> Dict[str, Any]:
    if not spans:
        return {"type": "user_input", "input": user_input, "output": answer, "children": [], "spans": []}
    return {
        "type": "user_input",
        "input": user_input,
        "output": answer,
        "children": _spans_to_tree(spans, exclude_names={"user_input"}),
    }


def _invoke_agent(prompt: str, config: Dict[str, Any], _exporter: InMemorySpanExporter) -> str:
    _patch_agent_factory(config)
    agent = agent_module.create_sql_agent()
    _exporter.clear()
    tracer = trace.get_tracer("promptfoo-eval")
    with tracer.start_as_current_span("user_input") as root:
        root.set_attribute("input", prompt)
        result = agent.invoke({"messages": [{"role": "user", "content": prompt}]})
        answer = _extract_answer(result)
        root.set_attribute("output", answer)
    return answer


def call_api(prompt: str, options: Dict[str, Any], context: Dict[str, Any]) -> Dict[str, str]:
    options = options or {}
    context = context or {}
    vars_dict = context.get("vars", {}) or {}
    test_case_id = vars_dict.get("test_case_id", "")
    precondition = vars_dict.get("precondition")
    config = options.get("config", {}) or {}

    _exporter = InMemorySpanExporter()
    _provider = TracerProvider()
    _provider.add_span_processor(SimpleSpanProcessor(_exporter))
    instrumentor = LangChainInstrumentor()
    instrumentation_enabled = False

    try:
        trace.set_tracer_provider(_provider)
    except Exception:
        pass

    try:
        instrumentor.instrument(tracer_provider=_provider)
        instrumentation_enabled = True
        setup_dependencies(test_case_id, precondition, config)
        answer = _invoke_agent(prompt, config, _exporter)
        spans = list(_exporter.get_finished_spans())
        trace_tree = _build_trace(prompt, answer, spans)
        return {"output": json.dumps({"answer": answer, "trace": trace_tree}, ensure_ascii=False)}
    finally:
        cleanup_dependencies()
        if instrumentation_enabled:
            try:
                instrumentor.uninstrument()
            except Exception:
                pass
