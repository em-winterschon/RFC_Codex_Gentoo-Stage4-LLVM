# DeepEval Workflow Assessment

## Purpose

DeepEval is a candidate addition to the repository's testing strategy for
agentic and LLM-assisted development workflows. It should be treated as an
advisory evaluation layer for Forge/Atlas behavior, not as a replacement for
deterministic unit, shell, Robot, NetBox, DNS, QEMU, kernel, or infrastructure
validation gates.

## Source References

| Topic | Reference | Relevant Capability |
| --- | --- | --- |
| Vibe coding loop | https://deepeval.com/docs/vibe-coding | Iterative eval loop where an agent runs `deepeval test run`, reads scores and reasons, patches narrowly, and reruns. |
| Synthetic goldens from contexts | https://deepeval.com/docs/synthesizer-generate-from-contexts | Generates single-turn or conversational goldens from prepared context chunks. |
| Plan quality metric | https://deepeval.com/docs/metrics-plan-quality | Scores an agent plan from trace data and returns a reason for the score. Requires tracing. |
| Metrics catalog | https://deepeval.com/docs/metrics-introduction | Includes RAG, agentic, multi-turn, safety, JSON correctness, and custom metrics. |

## Fit For YukonSYS Workflows

| Workflow Area | Usefulness | Proposed Use | Gate Status |
| --- | --- | --- | --- |
| Forge/Atlas plan review | high | Score operator-request to action-plan traces with plan quality or a custom G-Eval rubric. | advisory |
| FCP and ntfy coordination | high | Evaluate whether proposed coordination messages preserve task state, next actions, and safety constraints. | advisory |
| MCP/control-plane tool behavior | medium-high | Add agentic metrics for tool correctness, argument correctness, step efficiency, and task completion once traces are available. | advisory until stable |
| Docs-grounded answers | high | Generate goldens from docs, wiki mirrors, FCP notes, and approved operational runbooks; evaluate answer relevancy and faithfulness. | canary first |
| PR/EOD summary quality | medium | Evaluate whether generated summaries mention commits, validation, risks, and open gates. | advisory |
| NetBox/DNS/inventory correctness | low as primary gate | Use only to review generated explanations or gap-analysis prose. Keep actual state validation deterministic. | never primary |
| Kernel, initramfs, QEMU, VPP, SLURM, PDU, ATS, UPS operations | low as primary gate | Use only to critique generated plans or runbooks before deterministic execution. | never primary |

## Candidate Local Layout

Do not add DeepEval to `requirements-dev.txt` until a separate change-control
decision approves the model endpoint, data handling, and runtime cost profile.
If approved, keep it isolated:

```text
tests/evals/
  datasets/
    docs-contexts.dataset.json
    fcp-coordination.dataset.json
  test_docs_grounding.py
  test_forge_plan_quality.py
  conftest.py
```

The initial pilot should avoid live infrastructure calls. It should evaluate
captured text artifacts only:

- `docs/`
- `docs/wiki/`
- sanitized FCP logs
- sanitized EOD reports
- approved runbooks
- static NetBox export snapshots

## Pilot Evaluation Targets

| Target | Metric Type | Example Question |
| --- | --- | --- |
| Plan quality | `PlanQualityMetric` or custom rubric | Does the proposed action plan account for dependencies, rollback, validation, and source-of-truth boundaries? |
| Grounded operational answers | RAG metrics such as answer relevancy and faithfulness | Does the answer cite only information available in approved docs and snapshots? |
| FCP message continuity | Conversational or custom G-Eval metric | Does the response preserve prior state, ownership, blockers, and next action? |
| Tool-call correctness | Agentic tool and argument metrics | Did the agent choose the right tool and arguments for a bounded workflow? |
| Summary completeness | Custom G-Eval or DAG metric | Does the EOD/PR summary include changed files, commits, tests, concerns, and follow-up gates? |

## Guardrails

- Do not use DeepEval as an authority for live infrastructure state.
- Do not feed secrets, vault material, private keys, production credentials, or
  raw sensitive NetBox exports into model-backed evals.
- Do not let an eval agent mutate NetBox, DNS, PDU, ATS, UPS, serial console,
  SSH, or package/build state.
- Do not lower thresholds to pass a failing eval without a documented review.
- Do not commit synthetic goldens until a human or deterministic sanitizer has
  reviewed them.
- Do not make Confident AI cloud reporting the default path. Keep local-first
  runs as the baseline and require explicit approval before sending private
  traces or datasets to a hosted service.

## Recommendation

DeepEval is useful enough to pilot, but only in an agentic-evaluation lane. The
first useful pilot is a non-mutating docs/FCP evaluation suite:

1. Generate a small reviewed dataset from approved docs and sanitized FCP
   contexts.
2. Add a `tests/evals/` suite that evaluates answer grounding, summary
   completeness, and plan quality on captured artifacts.
3. Run it manually first, then as an optional Jenkins stage.
4. Promote individual metrics to required CI only after they are stable,
   reproducible, and have known acceptable variance.

The practical target is better agent feedback during development: "which plan,
retrieval, tool-call, or summary behavior regressed?" That is valuable for
Forge/Atlas workflows. It should remain separate from deterministic
infrastructure correctness.
