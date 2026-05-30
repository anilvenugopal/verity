# Contract — Binding grammar (Source Binding / Target Binding)

- **Status:** Draft
- **Date:** 2026-05-29
- **Related:** [[0005-schema-hardening]]

---

## Naming

v2 uses two consistently-named binding kinds:

| v2 name | v1 legacy name | Meaning |
|---|---|---|
| **Source Binding** | `source_binding` | Declarative resolution of an **input** before the entity runs |
| **Target Binding** | `write_target` | Declarative write of an **output** after the entity runs |

The v1 pair (`source_binding` / `write_target`) was inconsistent — one noun, one
verb-noun. v2 standardizes on **Source Binding** and **Target Binding** everywhere:
schema, models, API field names, UI, and docs. This is part of the schema-naming
hardening in [[0005-schema-hardening]].

## Bindings apply uniformly to Tasks and Agents

Both Source Bindings and Target Bindings apply **identically** to tasks and agents.
There is no separate binding mechanism per entity kind — an agent binds inputs and
writes outputs exactly the way a task does. This is "agent binder parity."

## Capability matrix — what differs between Tasks and Agents

Bindings are shared; **tools and MCP are agent-only.**

| Capability | Task | Agent |
|---|:---:|:---:|
| Source Binding (declarative input) | ✅ | ✅ |
| Target Binding (declarative output) | ✅ | ✅ |
| Structured input/output payload | ✅ | ✅ |
| **Tool calls** | ❌ | ✅ |
| **MCP integration** | ❌ | ✅ |

A **task** is a single bound LLM step: resolve Source Bindings → run → write Target
Bindings. It has no tools and no MCP.

An **agent** is a multi-step reasoning entity: same Source/Target Binding grammar, plus
the ability to call tools and MCP servers during its turns.

## Mapping onto the equity-research slice

- `extract_filing_metrics` (**task**) — Source Binding: vault filing PDF; Target
  Binding: structured metrics. No tools, no MCP.
- `assess_equity` (**agent**) — Source Binding: task output (nullable); MCP:
  AlphaVantage; tool: `compute_upside`; Target Binding: structured opinion payload.
- `write_research_report` (**task**) — Source Binding: HITL-edited opinion; Target
  Binding: `research_note.pdf` to vault. No tools, no MCP.

## Acceptance (tests, not demo)

The full matrix — every Source Binding source type and every Target Binding target
type, applied to **agents** as well as tasks — is proven by built-in project tests.
