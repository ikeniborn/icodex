#!/usr/bin/env python3
"""LoEn result/evidence gate; reads LOEN_ARTIFACT_ROOT through loen_common."""
from loen_common import BLOCK, block_or_nudge, is_off, is_strict, read_event, read_loop_artifact, stderr, topic_dir

SCRIPT_NAME = "evidence-gate"


def main() -> int:
  if is_off():
    return 0
  event = read_event()
  read_loop_artifact()
  verdict = str(event.get("verdict") or event.get("decision") or "").strip().lower()
  message = str(event.get("message") or "").lower()
  event_name = str(event.get("hook_event_name") or event.get("event") or "").strip().lower()
  final_marker = str(event.get("final") or event.get("is_final") or "").strip().lower()
  non_final = verdict in {"continue", "pending", "not_done", "skip"} or final_marker in {"false", "0", "no"}
  wants_done = (
    not event
    or (event_name == "stop" and not non_final)
    or verdict in {"done", "ok", "success", "final"}
    or any(word in message for word in ("done", "ok", "success", "final"))
  )
  if not wants_done:
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
    if not worker_role or not verifier_role:
      stderr("LoEn: strict mode requires worker/verifier identity")
      return BLOCK
    if (worker_role and verifier_role and worker_role == verifier_role) or event.get("agent_role") == worker_role:
      stderr("LoEn: strict mode requires worker/verifier separation")
      return BLOCK
  if missing:
    return block_or_nudge("LoEn: done verdict missing evidence: " + ", ".join(missing))
  return 0


if __name__ == "__main__":
  raise SystemExit(main())
