---
description: Run the task-executor pytest suite locally (sources the common .env, pulls the S3 boxes.json fixture).
allowed-tools: Bash(make *), Bash(pytest *), Bash(python3 *), Bash(cd *), Bash(ls *), Bash(find *), Bash(source *), Bash(git status:*), Bash(aws s3 *), Read, Glob
---

## Context

- Current directory: !`pwd`
- `ROS_WS`: !`echo "${ROS_WS:-<unset>}"`
- Common `.env` present: !`test -f ../unloading_robot_common/.env && echo yes || echo "no (AWS creds for the S3 fixture may be missing)"`
- Arguments: $ARGUMENTS (optional: a test path, `-k <pattern>`, `e2e`, or `cov`)

## Your task

Run the `unloading_robot_task_executor` pytest suite locally and report results.

### Step 0: Locate the repo root

Tests must run from the `unloading_robot_task_executor` root (where `pyproject.toml` + `Makefile` live). If the current directory isn't it, find it (`find "$ROS_WS/src" -maxdepth 2 -name Makefile -path '*task_executor*'`) and `cd` there.

### Step 1: Check prerequisites

- **`ROS_WS` must be set** — `conftest.py` raises `EnvironmentError` without it. Usually already `~/ros_ws`. If unset, set it and stop to confirm with the user.
- **ROS + catkin workspace must be sourced** — the tests import `rospy` and `unloading_robot_msgs`. If those imports fail, tell the user to `source /opt/ros/noetic/setup.bash && source "$ROS_WS/devel/setup.bash"` (this can't be done from inside the command's shell).
- **`../unloading_robot_common/.env`** supplies AWS credentials used to download the S3 fixture (see Step 3). Source it if present; if absent, warn that `test_real_box_pickup_dropoff.py` may fail to fetch `boxes.json` on a cold cache.

### Step 2: Pick scope from `$ARGUMENTS`

- **empty** → full suite (all of `tests/`).
- **`cov`** → coverage run.
- **`e2e`, `boxes`, or `real`** → the S3-backed end-to-end test `tests/test_real_box_pickup_dropoff.py`.
- **anything else** → pass through verbatim as a pytest selector (a `tests/...` path, or `-k <pattern>`).

### Step 3: Run pytest

Source the env and run pytest **directly** (not the `| ldsp` pipe from the Makefile — that hides pytest's exit code and reformats output). `pyproject.toml` already sets `-vsx` (verbose, `--exitfirst`, `--capture=no`) via `addopts`, so no extra flags are needed for the default run.

```bash
set -a; [ -f ../unloading_robot_common/.env ] && . ../unloading_robot_common/.env; set +a
pytest <scope>                 # e.g. (empty) | tests/test_real_box_pickup_dropoff.py | -k blend
```

For **`cov`**, use the Makefile target instead: `make dev-tests-cov` (adds `--cov` + term-missing + HTML report under `coverage_html/`).

**The S3 fixture:** `tests/test_real_box_pickup_dropoff.py` downloads
`s3://contoro-unloading-robot/unloading_robot_task_executor/tests/end_to_end/boxes.json`
at import time via `AssetFactory`, caching it to `tests/test_data/end_to_end/boxes.json`. First run needs AWS creds (from `.env`) + network; subsequent runs use the cache. To regenerate the fixture after pulling fresh logs:

```bash
python3 tests/_extract_real_boxes.py
aws s3 cp tests/boxes.json s3://contoro-unloading-robot/unloading_robot_task_executor/tests/end_to_end/boxes.json
```

### Step 4: Report

- On green: state how many passed and the scope run.
- On red: `--exitfirst` stops at the first failure — show the failing test name and traceback. Offer to re-run the full suite without `-x` (`pytest tests -o addopts="-vs"`) to see every failure.
- If the run aborted at *collection* on the S3 download (`botocore`/credentials/network error), that's the fixture, not a test failure — point the user at Step 1's `.env` note.

### Rules

- Don't commit changes to `tests/test_data/end_to_end/boxes.json` — it's the cached S3 fixture, regenerated via the command above, not hand-edited.
- Don't pipe pytest through `ldsp` when running it yourself; it's a human log pretty-printer that swallows the exit code.
- Never guess whether tests passed — read pytest's actual summary line before reporting.
