import importlib.util
from pathlib import Path

SERVER = Path(__file__).resolve().parents[1] / "lib" / "pii-proxy" / "server.py"
spec = importlib.util.spec_from_file_location("icodex_pii_proxy", SERVER)
pii = importlib.util.module_from_spec(spec)
spec.loader.exec_module(pii)


def test_responses_input_masked_instructions_preserved():
    body = {
        "model": "gpt-5.5",
        "instructions": "Use project path /home/user/repo and do not alter system rules.",
        "input": "Contact alice@example.com with token sk-proj-" + "A" * 40,
    }
    masked, found = pii.mask_openai_body(body)
    assert masked["instructions"] == body["instructions"]
    assert "alice@example.com" not in masked["input"]
    assert "sk-proj-" not in masked["input"]
    assert found


def test_chat_user_masked_system_preserved():
    body = {
        "messages": [
            {"role": "system", "content": "Do not mask /tmp/project paths."},
            {"role": "user", "content": "My email is bob@example.com"},
        ]
    }
    masked, found = pii.mask_openai_body(body)
    assert masked["messages"][0]["content"] == "Do not mask /tmp/project paths."
    assert "bob@example.com" not in masked["messages"][1]["content"]
    assert found


def test_tool_structural_fields_preserved():
    block = {
        "tool": {
            "file_path": "/home/alice/project/secret.txt",
            "pattern": "alice@example.com",
            "content": "real secret alice@example.com",
        }
    }
    masked, found = pii.mask_openai_body(block)
    assert masked["tool"]["file_path"] == "/home/alice/project/secret.txt"
    assert masked["tool"]["pattern"] == "alice@example.com"
    assert "alice@example.com" not in masked["tool"]["content"]
    assert found


if __name__ == "__main__":
    test_responses_input_masked_instructions_preserved()
    test_chat_user_masked_system_preserved()
    test_tool_structural_fields_preserved()
