# Testing Strategy Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a layered test strategy with Python unit tests, Robot Framework acceptance smoke tests, and a Jenkins Pipeline draft.

**Architecture:** Keep shell tests as repository contract checks and add direct Python `unittest` coverage for importable script logic. Add Robot Framework for operator-readable acceptance workflows and Jenkins for staged execution/artifact publishing.

**Tech Stack:** Bash, Python `unittest`, Robot Framework, Jenkins Declarative Pipeline, optional Jenkins AI Agent step.

---

### Task 1: Define The Contract Test

**Files:**
- Create: `tests/shell/test_testing_strategy_scaffold.sh`

- [x] **Step 1: Add the shell contract test**

The shell test asserts that the strategy doc, Python unit runner, Robot runner,
Robot suite, Jenkinsfile, and requirements wiring exist.

- [x] **Step 2: Run the test and verify red**

Run:

```bash
bash tests/shell/test_testing_strategy_scaffold.sh
```

Expected: fail on missing `docs/TESTING-STRATEGY.md`.

### Task 2: Add The Minimal Implementation

**Files:**
- Create: `docs/TESTING-STRATEGY.md`
- Create: `tests/python/run-tests.sh`
- Create: `tests/python/test_service_validator.py`
- Create: `tests/robot/run-tests.sh`
- Create: `tests/robot/suites/repo_acceptance.robot`
- Create: `Jenkinsfile`
- Modify: `requirements-dev.txt`
- Modify: `tests/shell/run-tests.sh`

- [x] **Step 1: Add docs and runners**

Add the layered strategy doc and executable Python/Robot runner scripts.

- [x] **Step 2: Add the first Python unit test**

Add `tests/python/test_service_validator.py` using `unittest` against
`scripts/service_validator.py` parser and validation helpers.

- [x] **Step 3: Add Robot acceptance smoke test**

Add one Robot suite that verifies the strategy doc and runner wiring.

- [x] **Step 4: Add Jenkinsfile**

Add a draft Jenkinsfile with Python unit, shell contract, Robot acceptance, and
manual AI Agent review stages.

### Task 3: Verify And Publish

**Files:**
- Modify only if verification finds a defect in the files listed above.

- [x] **Step 1: Run focused tests**

```bash
bash tests/shell/test_testing_strategy_scaffold.sh
bash tests/python/run-tests.sh
bash tests/robot/run-tests.sh
```

- [x] **Step 2: Run formatting and shell syntax checks**

```bash
bash -n tests/shell/run-tests.sh tests/shell/test_testing_strategy_scaffold.sh tests/python/run-tests.sh tests/robot/run-tests.sh
python3 -m py_compile scripts/service_validator.py
git diff --check
```

- [x] **Step 3: Commit and open PR**

Commit on `codex/testing-strategy-robot-python-jenkins`, push, and open a PR
against the current integration base.

Published as draft PR: https://github.com/yukon-systems/RFC_Codex_Gentoo-Stage4-LLVM/pull/171

### Validation Notes

- `bash tests/shell/test_testing_strategy_scaffold.sh`: passed.
- `bash tests/python/run-tests.sh`: passed 5 Python unit tests.
- `env PATH=.venv/bin:$PATH bash tests/robot/run-tests.sh`: passed 3 Robot smoke tests and produced `test-results/robot/`.
- `env PATH=.venv/bin:$PATH bash tests/shell/run-tests.sh`: passed full shell contract suite.
- `bash -n tests/shell/run-tests.sh tests/shell/test_testing_strategy_scaffold.sh tests/python/run-tests.sh tests/robot/run-tests.sh`: passed.
- `python3 -m py_compile scripts/service_validator.py`: passed.
- `.venv/bin/black --check tests/python/test_service_validator.py scripts/service_validator.py`: passed.
- `.venv/bin/ruff check tests/python/test_service_validator.py scripts/service_validator.py`: passed.
- `git diff --check`: passed.
- Changed-file `pre-commit run --files ...`: blocked locally because `.pre-commit-config.yaml` requires `python3.11` and this M70 currently does not provide that interpreter.
