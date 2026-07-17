import copy
import json
import os
import sys
from pathlib import Path
from typing import Any, Dict, List, Optional

WORKSPACE_ROOT = Path("/private/var/folders/64/v39k3dlx3kl6dhmf1gjqpmr4rlcd68/T/test_gen_ltyeo56q")
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

_ORIGINAL_CHAT_ANTHROPIC = agent_module.ChatAnthropic
_PATCHES_APPLIED = False
_CURRENT_PROVIDER = None
_CURRENT_INSTRUMENTOR = None
_exporter = None
_PROVIDER_BASELINE = {
    "ChatAnthropic": _ORIGINAL_CHAT_ANTHROPIC,
}


def _seed_simple_count_query_execution(precondition, config):
    return None


def _seed_top_selling_artists_with_ordering(precondition, config):
    return None


def _seed_employee_revenue_performance_query(precondition, config):
    return None


def _seed_filtered_query_with_where_clause(precondition, config):
    return None


def _seed_query_without_hallucinated_columns(precondition, config):
    return None


def _seed_aggregate_query_with_group_by(precondition, config):
    return None


def _seed_schema_discovery_for_table_names(precondition, config):
    return None


def _seed_ambiguous_question_requires_clarification(precondition, config):
    return None


def _seed_schema_inspection_before_complex_query(precondition, config):
    return None


def setup_dependencies(test_case_id, precondition, config):
    seeders = {
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
    seeder = seeders.get(test_case_id)
    if seeder is None:
        return None
    return seeder(precondition, config)


def cleanup_dependencies():
    global _PATCHES_APPLIED
    agent_module.ChatAnthropic = _PROVIDER_BASELINE["ChatAnthropic"]
    _PATCHES_APPLIED = False


class _PatchedChatAnthropic(ChatOpenAI):
    def __init__(self, *args, **kwargs):
        model_name = kwargs.pop("model", None) or os.environ.get("CODEVALID_EVAL_MODEL")
        temperature = kwargs.pop("temperature", 0)
        if not model_name:
            raise ValueError("Missing eval model. Expected options.config.model to be provided.")
        base_url = os.environ["LITELLM_BASE_URL"]
        api_key = os.environ["LITELLM_API_KEY"]
        super().__init__(
            model=model_name,
            temperature=temperature,
            base_url=base_url,
            api_key=api_key,
            **kwargs,
        )


def _patch_agent_factory(config):
    global _PATCHES_APPLIED
    model_name = (config or {}).get("model")
    if not model_name:
        raise ValueError("options.config.model is required")
    os.environ["CODEVALID_EVAL_MODEL"] = model_name
    agent_module.ChatAnthropic = _PatchedChatAnthropic
    _PATCHES_APPLIED = True


def _restore_agent_factory():
    cleanup_dependencies()
    os.environ.pop("CODEVALID_EVAL_MODEL", None)


def _serialize_value(value: Any) -> Any:
    if value is None:
        return None
    if isinstance(value, (str, int, float, bool)):
        return value
    if isinstance(value, bytes):
        try:
            return value.decode("utf-8")
        except Exception:
            return repr(value)
    if isinstance(value, dict):
        return {str(k): _serialize_value(v) for k, v in value.items()}
    if isinstance(value, (list, tuple, set)):
        return [_serialize_value(v) for v in value]
    content = getattr(value, "content", None)
    if content is not None:
        return _serialize_value(content)
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


def _extract_answer(result: Any) -> str:
    if result is None:
        return ""
    if isinstance(result, str):
        return result
    if isinstance(result, dict):
        messages = result.get("messages")
        if isinstance(messages, list) and messages:
            return _extract_answer(messages[-1])
        for key in ("output", "answer", "content", "text", "result"):
            if key in result:
                return _extract_answer(result.get(key))
        return json.dumps(_serialize_value(result), ensure_ascii=False)
    content = getattr(result, "content", None)
    if content is not None:
        if isinstance(content, list):
            parts = []
            for item in content:
                if isinstance(item, dict):
                    text = item.get("text") or item.get("content") or item.get("value")
                    if text:
                        parts.append(str(text))
                else:
                    parts.append(str(item))
            return "\n".join([p for p in parts if p]).strip()
        return str(content)
    if isinstance(result, list) and result:
        return _extract_answer(result[-1])
    return str(result)


def _candidate_attr(attributes: Dict[str, Any], keys: List[str]) -> Any:
    for key in keys:
        if key in attributes and attributes[key] not in (None, "", [], {}):
            return attributes[key]
    return None


def _span_kind(span_name: str, attributes: Dict[str, Any]) -> str:
    operation = _candidate_attr(attributes, ["gen_ai.operation.name", "operation.name", "langchain.span.kind"])
    if operation in {"execute_tool", "tool"}:
        return "tool"
    if operation in {"chat", "llm", "completion"}:
        return "llm"
    if operation in {"invoke_agent", "agent"}:
        return "agent"
    if operation in {"invoke_workflow", "workflow", "chain"}:
        return "workflow"
    if any(k in attributes for k in ["gen_ai.tool.name", "tool.name"]):
        return "tool"
    if any(k in attributes for k in ["gen_ai.request.model", "llm.request.model", "gen_ai.system", "llm.system"]):
        return "llm"
    lowered = (span_name or "").lower()
    if "tool" in lowered:
        return "tool"
    if "agent" in lowered:
        return "agent"
    if "llm" in lowered or "chat" in lowered:
        return "llm"
    return "span"


def _span_to_node(span) -> Dict[str, Any]:
    attrs = dict(getattr(span, "attributes", {}) or {})
    gen_ai = {
        "system": _serialize_value(_candidate_attr(attrs, ["gen_ai.system", "llm.system"])),
        "operation_name": _serialize_value(_candidate_attr(attrs, ["gen_ai.operation.name", "operation.name"])),
        "request_model": _serialize_value(_candidate_attr(attrs, ["gen_ai.request.model", "llm.request.model", "gen_ai.response.model"])),
        "prompt": _serialize_value(_candidate_attr(attrs, ["gen_ai.prompt", "llm.prompts", "gen_ai.input.messages", "input.value", "input"])),
        "completion": _serialize_value(_candidate_attr(attrs, ["gen_ai.completion", "llm.output_messages", "gen_ai.output.messages", "output.value", "output"])),
        "tool_name": _serialize_value(_candidate_attr(attrs, ["gen_ai.tool.name", "tool.name"])),
        "input": _serialize_value(_candidate_attr(attrs, ["input.value", "input", "gen_ai.tool.call.arguments", "gen_ai.input.messages", "llm.prompts"])),
        "output": _serialize_value(_candidate_attr(attrs, ["output.value", "output", "gen_ai.tool.call.result", "gen_ai.output.messages", "llm.output_messages"])),
    }
    node = {
        "name": span.name,
        "type": _span_kind(span.name, attrs),
        "span_id": format(span.context.span_id, "x"),
        "trace_id": format(span.context.trace_id, "x"),
        "gen_ai": {k: v for k, v in gen_ai.items() if v not in (None, "", [], {})},
        "attributes": {str(k): _serialize_value(v) for k, v in attrs.items()},
        "children": [],
    }
    if node["type"] == "tool":
        tool_name = node["gen_ai"].get("tool_name")
        if tool_name:
            node["name"] = tool_name
    input_value = node["gen_ai"].get("input") or node["gen_ai"].get("prompt")
    output_value = node["gen_ai"].get("output") or node["gen_ai"].get("completion")
    if input_value is not None:
        node["input"] = input_value
    if output_value is not None:
        node["output"] = output_value
    return node


def _spans_to_tree(spans: List[Any], exclude_names: Optional[set] = None) -> List[Dict[str, Any]]:
    exclude_names = exclude_names or set()
    filtered = sorted(
        [s for s in spans if s.name not in exclude_names],
        key=lambda s: getattr(s, "start_time", 0) or 0,
    )
    nodes = {s.context.span_id: _span_to_node(s) for s in filtered}
    child_ids: Dict[int, List[int]] = {}
    roots: List[int] = []
    span_ids = set(nodes.keys())

    for span in filtered:
        sid = span.context.span_id
        parent = span.parent.span_id if getattr(span, "parent", None) is not None else None
        if parent is not None and parent in span_ids:
            child_ids.setdefault(parent, []).append(sid)
        else:
            roots.append(sid)

    def attach(span_id: int) -> Dict[str, Any]:
        node = nodes[span_id]
        node["children"] = [attach(child_id) for child_id in child_ids.get(span_id, [])]
        return node

    return [attach(root_id) for root_id in roots]


def _build_trace(user_input: str, answer: str, spans: List[Any]) -> Dict[str, Any]:
    if not spans:
        return {"type": "user_input", "input": user_input, "output": answer, "children": [], "spans": []}
    children = _spans_to_tree(spans, exclude_names={"user_input"})
    return {
        "type": "user_input",
        "input": user_input,
        "output": answer,
        "children": children,
        "spans": [_span_to_node(s) for s in sorted(spans, key=lambda s: getattr(s, "start_time", 0) or 0)],
    }


def _start_instrumentation():
    global _exporter, _CURRENT_PROVIDER, _CURRENT_INSTRUMENTOR
    _exporter = InMemorySpanExporter()
    _CURRENT_PROVIDER = TracerProvider()
    _CURRENT_PROVIDER.add_span_processor(SimpleSpanProcessor(_exporter))
    trace.set_tracer_provider(_CURRENT_PROVIDER)
    _CURRENT_INSTRUMENTOR = LangChainInstrumentor()
    _CURRENT_INSTRUMENTOR.instrument(tracer_provider=_CURRENT_PROVIDER)


def _stop_instrumentation():
    global _CURRENT_INSTRUMENTOR, _CURRENT_PROVIDER
    if _CURRENT_INSTRUMENTOR is not None:
        try:
            _CURRENT_INSTRUMENTOR.uninstrument()
        except Exception:
            pass
    _CURRENT_INSTRUMENTOR = None
    _CURRENT_PROVIDER = None


def _invoke_agent(prompt: str, config: Dict[str, Any]) -> Any:
    _patch_agent_factory(config)
    agent = agent_module.create_sql_agent()
    tracer = trace.get_tracer("promptfoo-eval")
    _exporter.clear()
    with tracer.start_as_current_span("user_input") as root:
        root.set_attribute("input.value", prompt)
        result = agent.invoke({"messages": [{"role": "user", "content": prompt}]})
        answer = _extract_answer(result)
        root.set_attribute("output.value", answer)
    spans = list(_exporter.get_finished_spans())
    trace_tree = _build_trace(prompt, answer, spans)
    return answer, trace_tree


def call_api(prompt, options, context):
    options = options or {}
    context = context or {}
    vars_dict = context.get("vars", {}) or {}
    test_case_id = vars_dict.get("test_case_id", "")
    precondition = vars_dict.get("precondition")
    config = options.get("config", {}) or {}
    try:
        setup_dependencies(test_case_id, precondition, config)
        _start_instrumentation()
        answer, trace_tree = _invoke_agent(prompt, config)
        return {
            "output": json.dumps({"answer": answer, "trace": trace_tree}, ensure_ascii=False)
        }
    finally:
        _stop_instrumentation()
        _restore_agent_factory()
        cleanup_dependencies()
