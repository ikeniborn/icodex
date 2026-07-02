#!/usr/bin/env python3
"""LoEn result/evidence gate; reads LOEN_ARTIFACT_ROOT through loen_common."""
from loen_common import BLOCK, is_enforcing, is_strict, read_event, read_loop_artifact, stderr, topic_dir

SCRIPT_NAME = "evidence-gate"


def main() -> int:
  event = read_event()
  read_loop_artifact()
  verdict = str(event.get("verdict") or event.get("decision") or "").strip().lower()
  message = str(event.get("message") or "")
  wants_done = verdict in {"done", "ok", "success"} or "done" in message.lower()
  if not (is_enforcing() and wants_done):
    return 0

  base = topic_dir()
  missing = []
  for filename in ("5_check.md", "7_result.md", "verifier-verdict.md"):
    if not (base / filename).is_file():
      missing.append(filename)
  evidence_dir = base / "evidence"
  has_evidence = evidence_dir.is_dir() and any(path.is_file() for path in evidence_dir.iterdir())
  if not has_evidence:
    missing.append("evidence/*")
  if is_strict():
    worker_role = event.get("worker_role")
    verifier_role = event.get("verifier_role")
    if (worker_role and verifier_role and worker_role == verifier_role) or event.get("agent_role") == worker_role:
      stderr("LoEn: strict mode requires worker/verifier separation")
      return BLOCK
  if missing:
    stderr("LoEn: done verdict missing evidence: " + ", ".join(missing))
    return BLOCK
  return 0


if __name__ == "__main__":
  raise SystemExit(main())
