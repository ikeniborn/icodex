#!/usr/bin/env bash
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

python3 - "$ROOT" <<'PY'
from __future__ import annotations

import dataclasses
import hashlib
import importlib.util
import io
import json
import os
import shutil
import subprocess
import sys
import tempfile
from contextlib import redirect_stdout
from pathlib import Path


root = Path(sys.argv[1])
sys.path.insert(0, str(root / "lib" / "profile"))

PASS = 0
FAIL = 0


def check(name: str, condition: object) -> None:
    global PASS, FAIL
    if condition:
        print(f"PASS [{name}]")
        PASS += 1
    else:
        print(f"FAIL [{name}]")
        FAIL += 1


def load_module(name: str, path: Path):
    spec = importlib.util.spec_from_file_location(name, path)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"cannot load {path}")
    module = importlib.util.module_from_spec(spec)
    sys.modules[name] = module
    spec.loader.exec_module(module)
    return module


def git(repo: Path, *args: str) -> str:
    result = subprocess.run(
        ["git", "-C", str(repo), *args],
        check=True,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    return result.stdout.strip()


def init_git(repo: Path) -> None:
    git(repo, "init", "-q", "-b", "main")
    git(repo, "config", "user.email", "test@example.com")
    git(repo, "config", "user.name", "Test")


REGISTRY = """schema_version: 1
registry_version: 7
dimensions:
  capability:
    comparator: gte
    tiers:
      - baseline
      - strong
  context:
    comparator: gte
    tiers:
      - small
      - medium
  latency:
    comparator: lte
    tiers:
      - low
      - high
  cost:
    comparator: lte
    tiers:
      - low
      - high
  throughput:
    comparator: gte
    tiers:
      - low
      - high
profiles:
  engineering:
    model: gpt-engineering
    effort: medium
    capacities:
      capability: strong
      context: medium
      latency: low
      cost: low
      throughput: high
"""


def manifest(registry_hash: str) -> str:
    task = """    requirements:
      capability: strong
      context: medium
      latency: high
      cost: high
      throughput: low
    live_remaining_context: false
    preferred_profiles:
      - engineering
"""
    return f"""schema_version: 1
topic: demo
status: approved
registry:
  authority: icodex-shared
  path: profiles/registry.yaml
  sha256: {registry_hash}
context_inputs:
  - docs/context.md
tasks:
  - id: build
{task}  - id: review
{task}"""


FAKE_SERVER = r'''#!/usr/bin/env python3
import json
import os
import sys
from pathlib import Path

record = Path(os.environ["FAKE_APP_SERVER_RECORD"])
transitions = json.loads(os.environ.get("FAKE_APP_SERVER_TRANSITIONS", '["needs_input"]'))
available = [{
    "id": "gpt-engineering",
    "model": "gpt-engineering",
    "supportedReasoningEfforts": [{"reasoningEffort": "medium"}],
}]
turn_number = int(os.environ["ICODEX_PROFILE_SEQUENCE"]) - 1
session = None

def emit(value):
    sys.stdout.write(json.dumps(value, sort_keys=True, separators=(",", ":")) + "\n")
    sys.stdout.flush()

for line in sys.stdin:
    request = json.loads(line)
    with record.open("a", encoding="utf-8") as stream:
        stream.write(json.dumps({
            "request": request,
            "environment": {key: os.environ.get(key) for key in sorted(os.environ) if key.startswith("ICODEX_PROFILE_")},
            "argv": sys.argv[1:],
        }, sort_keys=True, separators=(",", ":")) + "\n")
    method = request.get("method")
    if method == "initialized":
        continue
    request_id = request["id"]
    if method == "initialize":
        emit({
            "method": "remoteControl/status/changed",
            "params": {"status": "disabled"},
            "emittedAtMs": 1785399248485,
        })
        emit({"id": request_id, "result": {"userAgent": "fake"}})
    elif method == "model/list":
        emit({"id": request_id, "result": {"data": available, "nextCursor": None}})
    elif method == "thread/start":
        session = f"session-{os.environ['ICODEX_PROFILE_RUN_ID']}-{os.environ['ICODEX_PROFILE_SEQUENCE']}"
        emit({"id": request_id, "result": {"thread": {"id": session, "sessionId": session}}})
    elif method == "turn/start":
        turn_number += 1
        turn_id = f"turn-{turn_number}"
        mode = transitions[min(turn_number - 1, len(transitions) - 1)]
        if mode == "server_error":
            emit({"id": request_id, "error": {"code": 500, "message": "fake failure"}})
            continue
        state_root = Path(os.environ["FAKE_CODEX_HOME"]) / "state" / "profile-routing"
        name = f"{os.environ['ICODEX_PROFILE_RUN_ID']}.{os.environ['ICODEX_PROFILE_SEQUENCE']}"
        pending = state_root / "pending" / f"{name}.json"
        consumed = state_root / "consumed" / f"{name}.json"
        handoff = json.loads(pending.read_text(encoding="utf-8"))
        consumed.parent.mkdir(parents=True, exist_ok=True)
        pending.replace(consumed)
        decision = {**handoff, "session_id": session, "authorized": True, "observed_model": request["params"]["model"]}
        decision_path = state_root / "decisions" / f"{session}.json"
        decision_path.parent.mkdir(parents=True, exist_ok=True)
        decision_path.write_text(json.dumps(decision, sort_keys=True, separators=(",", ":")) + "\n", encoding="utf-8")
        emit({"id": request_id, "result": {"turn": {"id": turn_id, "status": "inProgress", "items": [], "error": None}}})
        if mode == "interrupted":
            emit({
                "method": "turn/completed",
                "params": {"turn": {
                    "id": turn_id,
                    "status": "interrupted",
                    "items": [],
                    "error": None,
                }},
                "emittedAtMs": 1785399248486,
            })
            continue
        if mode == "malformed":
            text = '{"transition":"complete"}'
        else:
            text = json.dumps({"transition": mode, "summary": mode, "evidence": []}, sort_keys=True, separators=(",", ":"))
        emit({"method": "turn/completed", "params": {"turn": {
            "id": turn_id,
            "status": "completed",
            "items": [{"type": "agentMessage", "id": "message-1", "text": text}],
            "error": None,
        }}, "emittedAtMs": 1785399248487})
'''


@dataclasses.dataclass
class Fixture:
    base: Path
    shared_repo: Path
    shared_root: Path
    target: Path
    home: Path
    binary: Path
    record: Path


def make_fixture(base: Path) -> Fixture:
    shared_repo = base / "shared"
    shared_root = shared_repo / ".codex-isolated"
    registry = shared_root / "profiles" / "registry.yaml"
    target = base / "target"
    home = base / "home"
    binary = base / "fake-codex"
    record = base / "requests.jsonl"
    registry.parent.mkdir(parents=True)
    registry.write_text(REGISTRY, encoding="utf-8")
    init_git(shared_repo)
    git(shared_repo, "add", ".codex-isolated/profiles/registry.yaml")
    git(shared_repo, "commit", "-qm", "registry")
    (target / "docs" / "profiles").mkdir(parents=True)
    (target / "docs" / "context.md").write_text("# Context\n", encoding="utf-8")
    registry_hash = hashlib.sha256(REGISTRY.encode()).hexdigest()
    (target / "docs" / "profiles" / "demo.yaml").write_text(manifest(registry_hash), encoding="utf-8")
    init_git(target)
    git(target, "add", "docs")
    git(target, "commit", "-qm", "manifest")
    home.mkdir()
    (home / "profiles").symlink_to(shared_root / "profiles", target_is_directory=True)
    binary.write_text(FAKE_SERVER, encoding="utf-8")
    binary.chmod(0o755)
    return Fixture(base, shared_repo, shared_root, target, home, binary, record)


def requests(fixture: Fixture) -> list[dict[str, object]]:
    if not fixture.record.exists():
        return []
    return [json.loads(line) for line in fixture.record.read_text(encoding="utf-8").splitlines()]


def methods(fixture: Fixture) -> list[str]:
    return [str(item["request"]["method"]) for item in requests(fixture)]


def configure_fake(fixture: Fixture, transitions: list[str]) -> None:
    os.environ["FAKE_APP_SERVER_RECORD"] = str(fixture.record)
    os.environ["FAKE_APP_SERVER_TRANSITIONS"] = json.dumps(transitions)
    os.environ["FAKE_CODEX_HOME"] = str(fixture.home)


try:
    app_server = load_module("profile_app_server", root / "lib" / "profile" / "app_server.py")
    runner = load_module("profile_runner", root / "lib" / "profile" / "runner.py")
except FileNotFoundError as exc:
    print(f"FAIL [runner modules exist]: {exc}")
    print("---")
    print("PASS=0 FAIL=1")
    raise SystemExit(1)


EXPECTED_SCHEMA = {
    "additionalProperties": False,
    "properties": {
        "evidence": {"items": {"type": "string"}, "type": "array"},
        "summary": {"type": "string"},
        "transition": {"enum": ["complete", "needs_input", "blocked"], "type": "string"},
    },
    "required": ["transition", "summary", "evidence"],
    "type": "object",
}
check("transition schema exact", runner.TRANSITION_SCHEMA == EXPECTED_SCHEMA)
try:
    accepted_metadata = app_server.AppServerClient._validate_notification(
        {"method": "notice", "params": {}, "emittedAtMs": 1785399248485}
    ) == ("notice", {})
except app_server.AppServerError:
    accepted_metadata = False
check("notification accepts integer emittedAtMs metadata", accepted_metadata)
for name, notification in (
    (
        "notification rejects non-integer emittedAtMs",
        {"method": "notice", "params": {}, "emittedAtMs": "now"},
    ),
    (
        "notification rejects unknown envelope metadata",
        {"method": "notice", "params": {}, "unexpected": 1},
    ),
):
    try:
        app_server.AppServerClient._validate_notification(notification)
    except app_server.AppServerError:
        rejected = True
    else:
        rejected = False
    check(name, rejected)

with tempfile.TemporaryDirectory() as temporary:
    fixture = make_fixture(Path(temporary))
    configure_fake(fixture, ["needs_input"])
    child_env = dict(os.environ)
    child_env.update(
        {
            "ICODEX_PROFILE_RUN_ID": "callback-run",
            "ICODEX_PROFILE_SEQUENCE": "1",
            "ICODEX_PROFILE_REQUEST_ID": "4",
        }
    )
    callback_requests: list[tuple[int, dict[str, object]]] = []
    with app_server.AppServerClient(
        [str(fixture.binary), "app-server"], fixture.target, env=child_env
    ) as client:
        first = client.request("initialize", {})

        def reject_before_send(request_id: int, request: dict[str, object]) -> None:
            callback_requests.append((request_id, request))
            raise RuntimeError("reject write")

        try:
            client.request("model/list", {}, before_send=reject_before_send)
        except RuntimeError:
            callback_failed = True
        else:
            callback_failed = False
    recorded = requests(fixture)
    check("request returns matching result", first == {"userAgent": "fake"})
    check("request IDs increase monotonically", callback_requests[0][0] == 2)
    check(
        "callback receives exact unsent request",
        callback_requests[0][1] == {"method": "model/list", "id": 2, "params": {}},
    )
    check("callback failure propagates", callback_failed)
    check("callback failure writes nothing", methods(fixture) == ["initialize"])

with tempfile.TemporaryDirectory() as temporary:
    base = Path(temporary)
    failing = base / "failing-server"
    failing.write_text(
        "#!/usr/bin/env python3\nimport sys\nsys.stdin.readline()\nsys.stderr.write('captured failure\\n')\nsys.stderr.flush()\n",
        encoding="utf-8",
    )
    failing.chmod(0o755)
    try:
        with app_server.AppServerClient([str(failing)], base) as client:
            client.request("initialize", {})
    except app_server.AppServerError as exc:
        captured_error = str(exc)
    else:
        captured_error = ""
    check("server stderr is captured", "captured failure" in captured_error)

with tempfile.TemporaryDirectory() as temporary:
    fixture = make_fixture(Path(temporary))
    configure_fake(fixture, ["complete"])
    config = runner.RunnerConfig(fixture.target, fixture.home, fixture.shared_root, fixture.binary)
    code = runner.run_task(config, "demo", "review")
    logged = requests(fixture)
    turn_requests = [item for item in logged if item["request"]["method"] == "turn/start"]
    check("cold one-shot succeeds", code == 0)
    check("one-shot starts exactly one turn", len(turn_requests) == 1)
    params = turn_requests[0]["request"]["params"]
    check("one-shot starts requested task", "review" in params["input"][0]["text"] and "build" not in params["input"][0]["text"])
    check("turn exact selected model", params["model"] == "gpt-engineering")
    check("turn exact selected effort", params["effort"] == "medium")
    check("turn exact canonical cwd", params["cwd"] == str(fixture.target.resolve()))
    check("turn strict output schema", params["outputSchema"] == EXPECTED_SCHEMA)
    check("app server command exact", all(item["argv"] == ["app-server"] for item in logged))
    routed_environment = turn_requests[0]["environment"]
    check(
        "child gets only correlation routing variables",
        set(routed_environment) == {"ICODEX_PROFILE_REQUEST_ID", "ICODEX_PROFILE_RUN_ID", "ICODEX_PROFILE_SEQUENCE"},
    )
    check("request environment matches turn request id", routed_environment["ICODEX_PROFILE_REQUEST_ID"] == str(turn_requests[0]["request"]["id"]))
    check("cold one-shot creates fresh run id", bool(routed_environment["ICODEX_PROFILE_RUN_ID"]))
    check("home manifest absent", not (fixture.home / "profiles" / "demo.yaml").exists())
    handoffs = list((fixture.home / "state" / "profile-routing" / "pending").glob("*.json"))
    if not handoffs:
        handoffs = list((fixture.home / "state" / "profile-routing" / "consumed").glob("*.json"))
    handoff = json.loads(handoffs[0].read_text(encoding="utf-8"))
    canonical_request = json.dumps(turn_requests[0]["request"], sort_keys=True, separators=(",", ":")).encode()
    check("handoff hashes exact turn request", handoff["request_hash"] == hashlib.sha256(canonical_request).hexdigest())

with tempfile.TemporaryDirectory() as temporary:
    fixture = make_fixture(Path(temporary))
    configure_fake(fixture, ["complete", "blocked"])
    config = runner.RunnerConfig(fixture.target, fixture.home, fixture.shared_root, fixture.binary)
    output = io.StringIO()
    with redirect_stdout(output):
        code = runner.orchestrate(config, "demo")
    logged = requests(fixture)
    turn_requests = [item for item in logged if item["request"]["method"] == "turn/start"]
    check("cold orchestrate stops on blocked", code != 0)
    check("complete advances exactly once", len(turn_requests) == 2)
    check("orchestrate starts first declared task", "build" in turn_requests[0]["request"]["params"]["input"][0]["text"])
    check("cold orchestrate announces first task", "Starting new run from first task: build" in output.getvalue())
    check("orchestrate advances to successor", "review" in turn_requests[1]["request"]["params"]["input"][0]["text"])

for mode in ("needs_input", "blocked", "malformed", "interrupted", "server_error"):
    with tempfile.TemporaryDirectory() as temporary:
        fixture = make_fixture(Path(temporary))
        configure_fake(fixture, [mode, "complete"])
        config = runner.RunnerConfig(fixture.target, fixture.home, fixture.shared_root, fixture.binary)
        code = runner.orchestrate(config, "demo")
        turns = [item for item in requests(fixture) if item["request"]["method"] == "turn/start"]
        check(f"{mode} returns nonzero", code != 0)
        check(f"{mode} never advances", len(turns) == 1 and "build" in turns[0]["request"]["params"]["input"][0]["text"])

with tempfile.TemporaryDirectory() as temporary:
    fixture = make_fixture(Path(temporary))
    configure_fake(fixture, ["needs_input"])
    config = runner.RunnerConfig(fixture.target, fixture.home, fixture.shared_root, fixture.binary)
    runner.orchestrate(config, "demo")
    first_log = requests(fixture)
    first_model_lists = methods(fixture).count("model/list")
    first_handoffs = sum(
        len(list((fixture.home / "state" / "profile-routing" / directory).glob("*.json")))
        for directory in ("pending", "consumed")
    )
    runner.orchestrate(config, "demo")
    check("exact authorized cache adds no model-list", methods(fixture).count("model/list") == first_model_lists)
    check(
        "exact authorized cache creates next handoff",
        sum(
            len(list((fixture.home / "state" / "profile-routing" / directory).glob("*.json")))
            for directory in ("pending", "consumed")
        ) > first_handoffs,
    )
    second_turn = [item for item in requests(fixture)[len(first_log):] if item["request"]["method"] == "turn/start"][0]
    check("cache hit request correlation uses shorter sequence", second_turn["environment"]["ICODEX_PROFILE_REQUEST_ID"] == str(second_turn["request"]["id"]))

    state_root = fixture.home / "state" / "profile-routing"
    baseline_root = Path(temporary) / "baseline-state"
    shutil.copytree(state_root, baseline_root)
    run_path = state_root / "run.json"
    baseline_run = json.loads(run_path.read_text(encoding="utf-8"))
    selection_fields = list(baseline_run["selection"])
    for index, field in enumerate(selection_fields):
        shutil.rmtree(state_root)
        shutil.copytree(baseline_root, state_root)
        cache_path = next((state_root / "cache").glob("*.json"))
        cache = json.loads(cache_path.read_text(encoding="utf-8"))
        value = cache["selection"][field]
        if isinstance(value, int):
            cache["selection"][field] = value + 1
        elif field in {"registry_commit", "manifest_commit"}:
            cache["selection"][field] = ("f" if value[0] != "f" else "e") * len(value)
        elif field.endswith("hash") or field == "requirement_fingerprint":
            cache["selection"][field] = ("f" if value[0] != "f" else "e") * 64
        elif field == "target_root":
            alternate = Path(temporary) / f"alternate-{index}"
            alternate.mkdir(exist_ok=True)
            cache["selection"][field] = str(alternate.resolve())
        else:
            cache["selection"][field] = f"changed-{index}"
        cache_path.write_text(json.dumps(cache, sort_keys=True, separators=(",", ":")) + "\n", encoding="utf-8")
        before = methods(fixture).count("model/list")
        runner.orchestrate(config, "demo")
        check(f"changed cache tuple field {field} rechecks", methods(fixture).count("model/list") == before + 1)

    shutil.rmtree(state_root)
    before = methods(fixture).count("model/list")
    runner.orchestrate(config, "demo")
    check("deleted state rechecks", methods(fixture).count("model/list") == before + 1)

with tempfile.TemporaryDirectory() as temporary:
    fixture = make_fixture(Path(temporary))
    configure_fake(fixture, ["needs_input"])
    config = runner.RunnerConfig(fixture.target, fixture.home, fixture.shared_root, fixture.binary)
    runner.orchestrate(config, "demo")
    state_root = fixture.home / "state" / "profile-routing"
    run_path = state_root / "run.json"
    run_state = json.loads(run_path.read_text(encoding="utf-8"))
    cache_path = next((state_root / "cache").glob("*.json"))
    cache = json.loads(cache_path.read_text(encoding="utf-8"))
    decision_path = state_root / "decisions" / f"{cache['session_id']}.json"
    decision = json.loads(decision_path.read_text(encoding="utf-8"))
    decision["observed_model"] = "gpt-changed"
    decision_path.write_text(json.dumps(decision, sort_keys=True, separators=(",", ":")) + "\n", encoding="utf-8")
    before = methods(fixture).count("model/list")
    runner.orchestrate(config, "demo")
    check("changed observed model rechecks", methods(fixture).count("model/list") == before + 1)

    run_state["run_id"] = "changed-run"
    run_path.write_text(json.dumps(run_state, sort_keys=True, separators=(",", ":")) + "\n", encoding="utf-8")
    before = methods(fixture).count("model/list")
    runner.orchestrate(config, "demo")
    check("changed run id rechecks", methods(fixture).count("model/list") == before + 1)

print("---")
print(f"PASS={PASS} FAIL={FAIL}")
raise SystemExit(1 if FAIL else 0)
PY
