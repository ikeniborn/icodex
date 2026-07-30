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
import multiprocessing
import os
import shutil
import stat
import subprocess
import sys
import tempfile
import time
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


def manifest(registry_hash: str, topic: str = "demo") -> str:
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
topic: {topic}
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
import subprocess
import sys
import time
from pathlib import Path

record = Path(os.environ["FAKE_APP_SERVER_RECORD"])
transitions = json.loads(os.environ.get("FAKE_APP_SERVER_TRANSITIONS", '["needs_input"]'))
server_request_phase = os.environ.get("FAKE_SERVER_REQUEST_PHASE", "")
delay = float(os.environ.get("FAKE_APP_SERVER_DELAY", "0"))
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
    method = request.get("method")
    run_state_exists = False
    if method == "turn/start":
        prompt = request["params"]["input"][0]["text"]
        topic = prompt.rsplit("topic ", 1)[-1].removesuffix(".")
        run_state_exists = (
            Path(os.environ["FAKE_CODEX_HOME"])
            / "state"
            / "profile-routing"
            / "orchestration"
            / f"{topic}.json"
        ).is_file()
    with record.open("a", encoding="utf-8") as stream:
        stream.write(json.dumps({
            "request": request,
            "environment": {key: os.environ.get(key) for key in sorted(os.environ) if key.startswith("ICODEX_PROFILE_")},
            "argv": sys.argv[1:],
            "runStateExists": run_state_exists,
        }, sort_keys=True, separators=(",", ":")) + "\n")
    if method is None:
        continue
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
        if server_request_phase == "request":
            emit({"id": "server-request-1", "method": "item/commandExecution/requestApproval", "params": {"reason": "test"}})
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
        hook_payload = {
            "session_id": session,
            "cwd": os.environ["FAKE_TARGET_ROOT"],
            "hook_event_name": "PreToolUse",
            "model": request["params"]["model"],
            "tool_name": "Write",
            "tool_input": {"file_path": "protected.txt"},
        }
        hook_environment = dict(os.environ)
        hook_environment.update({
            "CODEX_HOME": os.environ["FAKE_CODEX_HOME"],
            "ICODEX_ROOT": os.environ["FAKE_ICODEX_ROOT"],
        })
        hook = subprocess.run(
            [sys.executable, str(Path(os.environ["FAKE_ICODEX_ROOT"]) / ".codex-isolated" / "hooks" / "profile-transition.py")],
            input=json.dumps(hook_payload),
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            env=hook_environment,
            check=False,
        )
        with record.open("a", encoding="utf-8") as stream:
            stream.write(json.dumps({
                "hook": {"returncode": hook.returncode, "stdout": hook.stdout, "stderr": hook.stderr},
            }, sort_keys=True, separators=(",", ":")) + "\n")
        if hook.returncode != 0 or '"permissionDecision": "allow"' not in hook.stdout:
            emit({"id": request_id, "error": {"code": 403, "message": "profile hook denied"}})
            continue
        if mode == "crash":
            sys.stderr.write("fake App Server crash\n")
            sys.stderr.flush()
            raise SystemExit(9)
        emit({"id": request_id, "result": {"turn": {"id": turn_id, "status": "inProgress", "items": [], "error": None}}})
        if server_request_phase == "turn":
            emit({"id": 9001, "method": "item/tool/requestUserInput", "params": {"questions": []}})
        if delay:
            time.sleep(delay)
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
    return [
        str(item["request"]["method"])
        for item in requests(fixture)
        if isinstance(item.get("request"), dict) and "method" in item["request"]
    ]


def orchestration_run_path(state_root: Path, topic: str = "demo") -> Path:
    return state_root / "orchestration" / f"{topic}.json"


def configure_fake(fixture: Fixture, transitions: list[str]) -> None:
    os.environ["FAKE_APP_SERVER_RECORD"] = str(fixture.record)
    os.environ["FAKE_APP_SERVER_TRANSITIONS"] = json.dumps(transitions)
    os.environ["FAKE_CODEX_HOME"] = str(fixture.home)
    os.environ["FAKE_TARGET_ROOT"] = str(fixture.target)
    os.environ["FAKE_ICODEX_ROOT"] = str(root)
    os.environ.pop("FAKE_SERVER_REQUEST_PHASE", None)
    os.environ.pop("FAKE_APP_SERVER_DELAY", None)


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
    fixture = make_fixture(Path(temporary))
    configure_fake(fixture, ["needs_input"])
    os.environ["FAKE_SERVER_REQUEST_PHASE"] = "request"
    child_env = dict(os.environ)
    child_env.update(
        {
            "ICODEX_PROFILE_RUN_ID": "server-request-run",
            "ICODEX_PROFILE_SEQUENCE": "1",
            "ICODEX_PROFILE_REQUEST_ID": "4",
        }
    )
    try:
        with app_server.AppServerClient(
            [str(fixture.binary), "app-server"], fixture.target, env=child_env
        ) as client:
            client.request("initialize", {})
            client.notify("initialized", {})
            model_result = client.request("model/list", {})
    except app_server.AppServerError:
        model_result = None
    server_responses = [
        item["request"]
        for item in requests(fixture)
        if isinstance(item.get("request"), dict)
        and item["request"].get("id") == "server-request-1"
        and "error" in item["request"]
    ]
    check("server request during request does not replace matching response", model_result is not None)
    check(
        "unsupported server request gets exact fail-closed response",
        server_responses == [{
            "id": "server-request-1",
            "error": {"code": -32601, "message": "Unsupported server request"},
        }],
    )

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
    turn_requests = [
        item for item in logged
        if isinstance(item.get("request"), dict) and item["request"].get("method") == "turn/start"
    ]
    check("cold one-shot succeeds", code == 0)
    check("one-shot starts exactly one turn", len(turn_requests) == 1)
    params = turn_requests[0]["request"]["params"]
    check("one-shot starts requested task", "review" in params["input"][0]["text"] and "build" not in params["input"][0]["text"])
    check("turn exact selected model", params["model"] == "gpt-engineering")
    check("turn exact selected effort", params["effort"] == "medium")
    check("turn exact canonical cwd", params["cwd"] == str(fixture.target.resolve()))
    check("turn strict output schema", params["outputSchema"] == EXPECTED_SCHEMA)
    check(
        "app server command exact",
        all(
            item["argv"] == ["app-server"]
            for item in logged
            if isinstance(item.get("request"), dict)
        ),
    )
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
    hook_records = [item["hook"] for item in logged if isinstance(item.get("hook"), dict)]
    check(
        "fake exercises real profile hook",
        len(hook_records) == 1
        and hook_records[0]["returncode"] == 0
        and '"permissionDecision": "allow"' in hook_records[0]["stdout"],
    )
    decisions = list((fixture.home / "state" / "profile-routing" / "decisions").glob("*.json"))
    check("real hook creates authorized decision", len(decisions) == 1 and json.loads(decisions[0].read_text())["authorized"] is True)

with tempfile.TemporaryDirectory() as temporary:
    fixture = make_fixture(Path(temporary))
    configure_fake(fixture, ["needs_input"])
    os.environ["FAKE_SERVER_REQUEST_PHASE"] = "turn"
    config = runner.RunnerConfig(fixture.target, fixture.home, fixture.shared_root, fixture.binary)
    code = runner.run_task(config, "demo", "build")
    server_responses = [
        item["request"]
        for item in requests(fixture)
        if isinstance(item.get("request"), dict)
        and item["request"].get("id") == 9001
        and "error" in item["request"]
    ]
    check("server request during wait preserves terminal handling", code != 0 and len(server_responses) == 1)
    check(
        "wait path never auto-approves server request",
        server_responses[0].get("error") == {"code": -32601, "message": "Unsupported server request"}
        if server_responses else False,
    )

with tempfile.TemporaryDirectory() as temporary:
    fixture = make_fixture(Path(temporary))
    configure_fake(fixture, ["complete", "blocked"])
    config = runner.RunnerConfig(fixture.target, fixture.home, fixture.shared_root, fixture.binary)
    output = io.StringIO()
    with redirect_stdout(output):
        code = runner.orchestrate(config, "demo")
    logged = requests(fixture)
    turn_requests = [
        item for item in logged
        if isinstance(item.get("request"), dict) and item["request"].get("method") == "turn/start"
    ]
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
        turns = [
            item for item in requests(fixture)
            if isinstance(item.get("request"), dict) and item["request"].get("method") == "turn/start"
        ]
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
    second_turn = [
        item for item in requests(fixture)[len(first_log):]
        if isinstance(item.get("request"), dict) and item["request"].get("method") == "turn/start"
    ][0]
    check("cache hit request correlation uses shorter sequence", second_turn["environment"]["ICODEX_PROFILE_REQUEST_ID"] == str(second_turn["request"]["id"]))

    state_root = fixture.home / "state" / "profile-routing"
    baseline_root = Path(temporary) / "baseline-state"
    shutil.copytree(state_root, baseline_root)
    run_path = orchestration_run_path(state_root)
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
    run_path = orchestration_run_path(state_root)
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


def orchestrate_worker(config, queue) -> None:
    queue.put(runner.orchestrate(config, "demo"))


def orchestrate_topic_worker(config, topic: str, queue) -> None:
    queue.put((topic, runner.orchestrate(config, topic)))


with tempfile.TemporaryDirectory() as temporary:
    fixture = make_fixture(Path(temporary))
    configure_fake(fixture, ["blocked"])
    os.environ["FAKE_APP_SERVER_DELAY"] = "0.5"
    config = runner.RunnerConfig(fixture.target, fixture.home, fixture.shared_root, fixture.binary)
    context = multiprocessing.get_context("fork")
    queue = context.Queue()
    first = context.Process(target=orchestrate_worker, args=(config, queue))
    second = context.Process(target=orchestrate_worker, args=(config, queue))
    first.start()
    for _ in range(100):
        if "turn/start" in methods(fixture):
            break
        time.sleep(0.01)
    second.start()
    first.join(5)
    second.join(5)
    if first.is_alive():
        first.terminate()
        first.join()
    if second.is_alive():
        second.terminate()
        second.join()
    results = [queue.get(timeout=1) for _ in range(2)] if queue.qsize() == 2 else []
    turn_records = [
        item for item in requests(fixture)
        if isinstance(item.get("request"), dict) and item["request"].get("method") == "turn/start"
    ]
    check("concurrent cold orchestrators execute first task once", len(turn_records) == 1)
    check("second concurrent orchestrator fails cleanly", len(results) == 2 and all(code != 0 for code in results))
    check(
        "cold run ownership persists before turn start",
        len(turn_records) == 1 and turn_records[0]["runStateExists"] is True,
    )
    state_root = fixture.home / "state" / "profile-routing"
    run_path = orchestration_run_path(state_root)
    check(
        "per-topic orchestration namespace is restrictive",
        stat.S_IMODE(run_path.parent.stat().st_mode) == 0o700
        and stat.S_IMODE(run_path.stat().st_mode) == 0o600
        and not (state_root / "run.json").exists(),
    )

with tempfile.TemporaryDirectory() as temporary:
    fixture = make_fixture(Path(temporary))
    registry_hash = hashlib.sha256(REGISTRY.encode()).hexdigest()
    for topic in ("alpha", "beta"):
        (fixture.target / "docs" / "profiles" / f"{topic}.yaml").write_text(
            manifest(registry_hash, topic),
            encoding="utf-8",
        )
    git(fixture.target, "add", "docs/profiles/alpha.yaml", "docs/profiles/beta.yaml")
    git(fixture.target, "commit", "-qm", "two topics")
    configure_fake(fixture, ["blocked"])
    os.environ["FAKE_APP_SERVER_DELAY"] = "0.3"
    config = runner.RunnerConfig(fixture.target, fixture.home, fixture.shared_root, fixture.binary)
    context = multiprocessing.get_context("fork")
    queue = context.Queue()
    processes = [
        context.Process(target=orchestrate_topic_worker, args=(config, topic, queue))
        for topic in ("alpha", "beta")
    ]
    for process in processes:
        process.start()
    for process in processes:
        process.join(5)
        if process.is_alive():
            process.terminate()
            process.join()
    results = dict(queue.get(timeout=1) for _ in range(2)) if queue.qsize() == 2 else {}
    orchestration = fixture.home / "state" / "profile-routing" / "orchestration"
    topic_states = {
        topic: json.loads((orchestration / f"{topic}.json").read_text(encoding="utf-8"))
        for topic in ("alpha", "beta")
        if (orchestration / f"{topic}.json").is_file()
    }
    check(
        "different topics execute concurrently and keep separate state",
        set(results) == {"alpha", "beta"}
        and all(code != 0 for code in results.values())
        and set(topic_states) == {"alpha", "beta"}
        and topic_states["alpha"]["run_id"] != topic_states["beta"]["run_id"],
    )
    first_positions = {
        topic: (value["run_id"], value["task_id"], value["sequence"])
        for topic, value in topic_states.items()
    }
    os.environ.pop("FAKE_APP_SERVER_DELAY", None)
    for topic in ("alpha", "beta"):
        runner.orchestrate(config, topic)
    resumed_states = {
        topic: json.loads((orchestration / f"{topic}.json").read_text(encoding="utf-8"))
        for topic in ("alpha", "beta")
        if (orchestration / f"{topic}.json").is_file()
    }
    check(
        "each topic resumes its own run and task position",
        set(resumed_states) == {"alpha", "beta"}
        and all(
            resumed_states[topic]["run_id"] == first_positions[topic][0]
            and resumed_states[topic]["task_id"] == first_positions[topic][1]
            and resumed_states[topic]["sequence"] == first_positions[topic][2] + 1
            for topic in ("alpha", "beta")
        ),
    )

for failure_mode, evidence_directory in (
    ("server_error", "pending"),
    ("interrupted", "consumed"),
    ("crash", "consumed"),
):
    with tempfile.TemporaryDirectory() as temporary:
        fixture = make_fixture(Path(temporary))
        configure_fake(fixture, [failure_mode])
        config = runner.RunnerConfig(fixture.target, fixture.home, fixture.shared_root, fixture.binary)
        first_code = runner.orchestrate(config, "demo")
        state_root = fixture.home / "state" / "profile-routing"
        run_path = orchestration_run_path(state_root)
        first_run = json.loads(run_path.read_text()) if run_path.is_file() else None
        failed_evidence = (
            state_root
            / evidence_directory
            / f"{first_run['run_id']}.{first_run['sequence'] - 1}.json"
            if first_run is not None
            else None
        )
        retired_before_retry = failed_evidence is not None and not failed_evidence.exists()
        configure_fake(fixture, ["blocked"])
        second_code = runner.orchestrate(config, "demo")
        second_run = json.loads(run_path.read_text()) if run_path.is_file() else None
        turn_records = [
            item for item in requests(fixture)
            if isinstance(item.get("request"), dict) and item["request"].get("method") == "turn/start"
        ]
        check(f"{failure_mode} persists retry position", first_code != 0 and first_run is not None)
        check(
            f"{failure_mode} retry advances sequence once in same run",
            second_code != 0
            and first_run is not None
            and second_run is not None
            and second_run["run_id"] == first_run["run_id"]
            and second_run["sequence"] == first_run["sequence"] + 1,
        )
        check(
            f"{failure_mode} retry executes same task with fresh handoff",
            len(turn_records) == 2
            and all("build" in item["request"]["params"]["input"][0]["text"] for item in turn_records),
        )
        check(
            f"{failure_mode} retires failed attempt evidence",
            retired_before_retry and failed_evidence is not None and not failed_evidence.exists(),
        )

with tempfile.TemporaryDirectory() as temporary:
    fixture = make_fixture(Path(temporary))
    configure_fake(fixture, ["blocked"])
    config = runner.RunnerConfig(fixture.target, fixture.home, fixture.shared_root, fixture.binary)
    runner.orchestrate(config, "demo")
    state_root = fixture.home / "state" / "profile-routing"
    run_path = orchestration_run_path(state_root)
    run_state = json.loads(run_path.read_text())
    selection = run_state["selection"]
    runner.create_handoff(
        state_root,
        {
            "run_id": run_state["run_id"],
            "sequence": run_state["sequence"],
            "target_root": selection["target_root"],
            "topic": selection["topic"],
            "task_id": selection["task_id"],
            "registry_commit": selection["registry_commit"],
            "registry_version": selection["registry_version"],
            "registry_hash": selection["registry_hash"],
            "manifest_commit": selection["manifest_commit"],
            "manifest_hash": selection["manifest_hash"],
            "profile": selection["profile"],
            "model": selection["model"],
            "effort": selection["effort"],
            "request_id": 3,
            "request_hash": "a" * 64,
        },
    )
    before_turns = methods(fixture).count("turn/start")
    before_sequence = run_state["sequence"]
    code = runner.orchestrate(config, "demo")
    after_run = json.loads(run_path.read_text())
    check("handoff callback failure returns nonzero", code != 0)
    check("handoff callback failure writes no turn request", methods(fixture).count("turn/start") == before_turns)
    check("handoff callback failure advances sequence once", after_run["sequence"] == before_sequence + 1)
    check(
        "handoff callback failure retires collision evidence",
        not (state_root / "pending" / f"{run_state['run_id']}.{before_sequence}.json").exists(),
    )

with tempfile.TemporaryDirectory() as temporary:
    fixture = make_fixture(Path(temporary))
    configure_fake(fixture, ["blocked"])
    config = runner.RunnerConfig(fixture.target, fixture.home, fixture.shared_root, fixture.binary)
    runner.orchestrate(config, "demo")
    state_root = fixture.home / "state" / "profile-routing"
    run_path = orchestration_run_path(state_root)
    baseline = json.loads(run_path.read_text())
    baseline_state = Path(temporary) / "position-baseline"
    shutil.copytree(state_root, baseline_state)

    forged = dict(baseline)
    forged["task_index"] = 1
    run_path.write_text(json.dumps(forged, sort_keys=True, separators=(",", ":")) + "\n")
    before = methods(fixture).count("turn/start")
    code = runner.orchestrate(config, "demo")
    check("forged task index fails before turn", code != 0 and methods(fixture).count("turn/start") == before)

    shutil.rmtree(state_root)
    shutil.copytree(baseline_state, state_root)
    forged = dict(baseline)
    forged["task_id"] = "review"
    run_path.write_text(json.dumps(forged, sort_keys=True, separators=(",", ":")) + "\n")
    before = methods(fixture).count("turn/start")
    code = runner.orchestrate(config, "demo")
    check("forged task id fails before turn", code != 0 and methods(fixture).count("turn/start") == before)

    shutil.rmtree(state_root)
    shutil.copytree(baseline_state, state_root)
    run_state = json.loads(run_path.read_text())
    run_state["selection"]["profile"] = "forged"
    run_path.write_text(json.dumps(run_state, sort_keys=True, separators=(",", ":")) + "\n")
    cache_path = next((state_root / "cache").glob("*.json"))
    cache = json.loads(cache_path.read_text())
    cache["selection"]["profile"] = "forged"
    cache_path.write_text(json.dumps(cache, sort_keys=True, separators=(",", ":")) + "\n")
    before_models = methods(fixture).count("model/list")
    runner.orchestrate(config, "demo")
    check("forged cached selection forces policy model recheck", methods(fixture).count("model/list") == before_models + 1)

    shutil.rmtree(state_root)
    shutil.copytree(baseline_state, state_root)
    forged = json.loads(run_path.read_text())
    external_stem = Path(temporary) / "forged-run-victim"
    victim = Path(f"{external_stem}.{forged['sequence']}.json")
    victim.write_text("preserve", encoding="utf-8")
    forged["run_id"] = str(external_stem)
    run_path.write_text(json.dumps(forged, sort_keys=True, separators=(",", ":")) + "\n")
    before = methods(fixture).count("turn/start")
    code = runner.orchestrate(config, "demo")
    check(
        "forged absolute run id fails before execution",
        code != 0 and methods(fixture).count("turn/start") == before,
    )
    check(
        "forged absolute run id cannot retire external victim",
        victim.is_file() and victim.read_text(encoding="utf-8") == "preserve",
    )

with tempfile.TemporaryDirectory() as temporary:
    base = Path(temporary)
    state_root = base / "routing"
    state_root.mkdir()
    (state_root / "orchestration").mkdir()
    valid = {
        "run_id": "secure-run",
        "sequence": 1,
        "topic": "demo",
        "task_index": 0,
        "task_id": "build",
        "selection": None,
        "session_id": None,
    }
    target = base / "target.json"
    target.write_text(json.dumps(valid), encoding="utf-8")
    run_path = orchestration_run_path(state_root)
    run_path.symlink_to(target)
    try:
        runner._read_run(state_root, "demo")
    except runner.RunnerError:
        symlink_rejected = True
    else:
        symlink_rejected = False
    check("run state symlink rejected", symlink_rejected)

    run_path.unlink()
    shutil.copy2(target, run_path)
    run_path.chmod(0o644)
    try:
        runner._read_run(state_root, "demo")
    except runner.RunnerError:
        permissive_rejected = True
    else:
        permissive_rejected = False
    check("permissive run state rejected", permissive_rejected)

    run_path.unlink()
    os.mkfifo(run_path)
    queue = multiprocessing.get_context("fork").Queue()

    def read_fifo() -> None:
        try:
            runner._read_run(state_root, "demo")
        except runner.RunnerError:
            queue.put("rejected")
        else:
            queue.put("accepted")

    process = multiprocessing.get_context("fork").Process(target=read_fifo)
    process.start()
    process.join(0.5)
    fifo_blocked = process.is_alive()
    if fifo_blocked:
        process.terminate()
        process.join()
    result = queue.get(timeout=1) if not queue.empty() else "blocked"
    check("FIFO run state rejected without blocking", not fifo_blocked and result == "rejected")

with tempfile.TemporaryDirectory() as temporary:
    fixture = make_fixture(Path(temporary))
    orchestration = fixture.home / "state" / "profile-routing" / "orchestration"
    orchestration.mkdir(parents=True)
    external = Path(temporary) / "external-run-hardlink"
    external.write_text(
        json.dumps(
            {
                "run_id": "hardlink-run",
                "sequence": 1,
                "topic": "demo",
                "task_index": 0,
                "task_id": "build",
                "selection": None,
                "session_id": None,
            },
            sort_keys=True,
            separators=(",", ":"),
        ) + "\n",
        encoding="utf-8",
    )
    external.chmod(0o600)
    os.link(external, orchestration / "demo.json")
    configure_fake(fixture, ["blocked"])
    config = runner.RunnerConfig(fixture.target, fixture.home, fixture.shared_root, fixture.binary)
    code = runner.orchestrate(config, "demo")
    check(
        "per-topic state rejects hardlinked file without external mutation",
        code != 0
        and methods(fixture).count("turn/start") == 0
        and external.read_text(encoding="utf-8").endswith("\n")
        and stat.S_IMODE(external.stat().st_mode) == 0o600
        and external.stat().st_nlink == 2,
    )

with tempfile.TemporaryDirectory() as temporary:
    fixture = make_fixture(Path(temporary))
    external = Path(temporary) / "external-state"
    external.mkdir()
    (fixture.home / "state").symlink_to(external, target_is_directory=True)
    configure_fake(fixture, ["blocked"])
    config = runner.RunnerConfig(fixture.target, fixture.home, fixture.shared_root, fixture.binary)
    code = runner.orchestrate(config, "demo")
    check(
        "coordinator rejects symlinked state parent without external writes",
        code != 0
        and methods(fixture).count("turn/start") == 0
        and not (external / "profile-routing-coordinator").exists(),
    )

with tempfile.TemporaryDirectory() as temporary:
    fixture = make_fixture(Path(temporary))
    coordinator = fixture.home / "state" / "profile-routing-coordinator"
    coordinator.mkdir(parents=True)
    target = Path(temporary) / "external-lock"
    target.write_text("", encoding="utf-8")
    (coordinator / "demo.orchestrator.lock").symlink_to(target)
    configure_fake(fixture, ["blocked"])
    config = runner.RunnerConfig(fixture.target, fixture.home, fixture.shared_root, fixture.binary)
    code = runner.orchestrate(config, "demo")
    check("coordinator rejects symlink lock", code != 0 and methods(fixture).count("turn/start") == 0)

with tempfile.TemporaryDirectory() as temporary:
    fixture = make_fixture(Path(temporary))
    coordinator = fixture.home / "state" / "profile-routing-coordinator"
    coordinator.mkdir(parents=True)
    external = Path(temporary) / "external-hardlink-lock"
    external.write_text("preserve", encoding="utf-8")
    external.chmod(0o640)
    os.link(external, coordinator / "demo.orchestrator.lock")
    configure_fake(fixture, ["blocked"])
    config = runner.RunnerConfig(fixture.target, fixture.home, fixture.shared_root, fixture.binary)
    code = runner.orchestrate(config, "demo")
    check(
        "coordinator rejects hardlinked lock without external mutation",
        code != 0
        and methods(fixture).count("turn/start") == 0
        and external.read_text(encoding="utf-8") == "preserve"
        and stat.S_IMODE(external.stat().st_mode) == 0o640,
    )

with tempfile.TemporaryDirectory() as temporary:
    fixture = make_fixture(Path(temporary))
    coordinator = fixture.home / "state" / "profile-routing-coordinator"
    coordinator.mkdir(parents=True)
    os.mkfifo(coordinator / "demo.orchestrator.lock")
    configure_fake(fixture, ["blocked"])
    config = runner.RunnerConfig(fixture.target, fixture.home, fixture.shared_root, fixture.binary)
    started = time.monotonic()
    code = runner.orchestrate(config, "demo")
    check(
        "coordinator rejects FIFO lock without blocking",
        code != 0 and time.monotonic() - started < 1 and methods(fixture).count("turn/start") == 0,
    )

with tempfile.TemporaryDirectory() as temporary:
    fixture = make_fixture(Path(temporary))
    configure_fake(fixture, ["blocked"])
    config = runner.RunnerConfig(fixture.target, fixture.home, fixture.shared_root, fixture.binary)
    runner.orchestrate(config, "demo")
    lock_path = fixture.home / "state" / "profile-routing-coordinator" / "demo.orchestrator.lock"
    check("coordinator lock mode is 0600", stat.S_IMODE(lock_path.stat().st_mode) == 0o600)

print("---")
print(f"PASS={PASS} FAIL={FAIL}")
raise SystemExit(1 if FAIL else 0)
PY
