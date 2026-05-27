# Testing Strategy

## Purpose

The repository already has a broad shell-based contract suite. Keep that suite,
but add a clearer layered model so fast unit tests, repo policy checks,
operator-readable acceptance workflows, and CI artifacts each do the job they
are best suited for.

## Layered Test Model

| Layer | Primary Tool | Repository Path | Purpose | CI Gate |
| --- | --- | --- | --- | --- |
| Python unit tests | `unittest` | `tests/python/` | Directly exercise importable Python functions without shelling out. | required |
| Python examples | `doctest` | docstrings in `scripts/*.py` when useful | Keep tiny deterministic examples executable. | optional until examples exist |
| Shell contract tests | Bash | `tests/shell/` | Validate repository policy, generated files, Ansible role contracts, and shell entrypoints. | required |
| Robot Framework acceptance | Robot Framework | `tests/robot/` | Express operator-readable functional workflows and repo acceptance checks. | required for smoke suites |
| Jenkins orchestration | Jenkins Pipeline | `Jenkinsfile` | Run stages, preserve artifacts, and publish Robot/JUnit-style reports. | optional until Jenkins job is enabled |
| AI-assisted review | Jenkins AI Agent step | guarded Jenkins stage | Summarize failures and propose non-mutating next actions. | advisory only |

## Python Unit Tests

Use `unittest` for Python modules under `scripts/` when the behavior is pure or
can be isolated with temporary files and mocks. Prefer testing functions such as
parsers, validators, renderers, and plan builders directly instead of asserting
only on CLI output from shell.

Async Python code should use `unittest.IsolatedAsyncioTestCase` once ntfy/FCP or
service-watch helpers expose importable async functions. Python 3.14 adds more
asyncio introspection capability, but Python 3.14-only checks should remain
optional until the CI matrix deliberately includes that runtime.

`doctest` is acceptable for short examples with stable deterministic output. Do
not use doctest for live infrastructure, NetBox, DNS, SSH, or timing-sensitive
behavior.

## Shell Contract Tests

Shell tests stay responsible for repository structure, Ansible role contracts,
profile fragments, executable wrappers, and file-level policy. Shell tests
should call Python unit and Robot runners rather than duplicating their logic.

The full local contract entrypoint remains:

```bash
bash tests/shell/run-tests.sh
```

## Robot Framework Acceptance

Robot Framework acceptance tests should be used when the result needs to be
readable by operators and reviewers. Good candidates:

- NetBox source-of-truth exports and gap reports.
- DNS validation from NetBox or inventory snapshots.
- M70 canary lifecycle gates.
- VPP/OVS/LACP benchmark promotion gates.
- Backup and observability acceptance checks.

Use data-driven Robot tests for NetBox tables, device lists, VLAN/IP records,
and DNS records. Use BDD-style naming only where it improves operator review.
Robot tests must not mutate live infrastructure unless the suite name, tags,
and Jenkins stage make the apply gate explicit.

## Jenkins Pipeline

The root `Jenkinsfile` is a draft multistage pipeline for a Jenkins controller
or worker that can run this repository. It installs `requirements-dev.txt`, then
runs:

1. Python unit tests.
2. Shell contract tests.
3. Robot Framework acceptance tests.
4. Optional AI Agent review after failures or on manual request.

Robot output lands under `test-results/robot/` so Jenkins can archive the XML,
HTML log, and report artifacts. A Jenkins Robot plugin can publish the same
output if installed.

The optional AI Agent stage must stay advisory. Keep approvals enabled and do
not provide vault, NetBox write, production SSH, PDU, ATS, UPS, or live network
mutation credentials to that stage. It may summarize failures and suggest next
steps; it must not be a source of truth or a mutation authority.

## Promotion Rules

| Test Type | Add When | Required Evidence |
| --- | --- | --- |
| Python `unittest` | A Python script has importable parsing, rendering, validation, or planning logic. | `python3 -m unittest discover -s tests/python -p 'test_*.py' -v` passes. |
| `doctest` | A docstring example is clearer than prose and has stable output. | `python3 -m doctest <file>` passes or is wired into Python tests. |
| Shell test | A repo contract or generated file invariant must not drift. | Focused shell test prints `PASS`. |
| Robot test | A workflow should be readable as acceptance evidence. | Robot `output.xml`, `log.html`, and `report.html` are produced. |
| Jenkins stage | A test class needs artifact publishing or operational scheduling. | Jenkinsfile stage exists and archives relevant artifacts. |
| AI Agent review | Human wants failure triage or doc-gap analysis. | Stage has manual enablement and `requireApprovals: true`. |

## Current Baseline

- Python unit test runner: `tests/python/run-tests.sh`
- Robot runner: `tests/robot/run-tests.sh`
- Full shell entrypoint: `tests/shell/run-tests.sh`
- Jenkins draft pipeline: `Jenkinsfile`
- Pre-commit local prerequisite: the current `.pre-commit-config.yaml` requests
  `python3.11`; M70 local validation needs that interpreter installed or a
  separate change-control decision to update the repository default runtime.

## Reference Baseline

| Area | Reference | Local Decision |
| --- | --- | --- |
| Robot Framework | https://robot-framework.readthedocs.io/en/stable/ | Pin `robotframework==7.4.2` in `requirements-dev.txt` and keep acceptance suites under `tests/robot/`. |
| Robot BDD style | https://docs.robotframework.org/docs/testcase_styles/bdd | Use BDD-style names only where operator review benefits from narrative wording. |
| Robot data-driven style | https://docs.robotframework.org/docs/testcase_styles/datadriven | Prefer data-driven suites for NetBox, DNS, VLAN, IP address, and device inventory tables. |
| Robot reporting | https://docs.robotframework.org/docs/reporting_test_results/robot_framework_dashboard | Preserve `output.xml`, `xunit.xml`, `log.html`, and `report.html` under `test-results/robot/`. |
| Python `unittest` | https://docs.python.org/3/library/unittest.html | Use as the default Python unit test framework because it is in the standard library. |
| Python `doctest` | https://docs.python.org/3/library/doctest.html | Use sparingly for deterministic examples that double as executable documentation. |
| Async Python tests | https://docs.python.org/3/library/unittest.html#unittest.IsolatedAsyncioTestCase | Use `IsolatedAsyncioTestCase` once async FCP, ntfy, or watcher helpers become importable. |
| Python 3.14 asyncio introspection | https://docs.python.org/3/whatsnew/3.14.html#asyncio-introspection-capabilities | Treat as optional runtime-specific diagnostic coverage until the CI matrix includes Python 3.14. |
| Jenkins Pipeline | https://www.jenkins.io/doc/book/pipeline/jenkinsfile/ | Keep the repository pipeline in source control as `Jenkinsfile`. |
| Jenkins pyenv-pipeline | https://www.jenkins.io/doc/pipeline/steps/pyenv-pipeline/ | Wrap Python commands in `withPythonEnv('python3')` when the Jenkins plugin is installed. |
| Jenkins AI Agent | https://www.jenkins.io/doc/pipeline/steps/ai-agent/ | Keep AI Agent review gated, manual, approval-backed, and non-mutating. |
