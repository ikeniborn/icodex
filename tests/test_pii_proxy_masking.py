import importlib.util
from pathlib import Path

SERVER = Path(__file__).resolve().parents[1] / "lib" / "pii-proxy" / "server.py"
spec = importlib.util.spec_from_file_location("icodex_pii_proxy", SERVER)
pii = importlib.util.module_from_spec(spec)
spec.loader.exec_module(pii)


def test_rules_mask_secrets_and_pii():
    text = (
        "email alice@example.com token github_pat_" + "A" * 90 +
        " password=supersecret1234 card 4111111111111111"
    )
    masked, found = pii.rules_mask(text, mask_token="REDACTED")
    assert "alice@example.com" not in masked
    assert "github_pat_" not in masked
    assert "supersecret1234" not in masked
    assert "4111111111111111" not in masked
    assert "REDACTED" in masked
    assert found


def test_rules_preserve_plain_urls_and_placeholders():
    text = "Visit https://example.com/docs and keep password=${DB_PASSWORD}"
    masked, found = pii.rules_mask(text, mask_token="REDACTED")
    assert "https://example.com/docs" in masked
    assert "${DB_PASSWORD}" in masked
    assert found == []


def test_credentials_in_url_masked():
    masked, found = pii.rules_mask("https://user:secret@example.com/path", mask_token="REDACTED")
    assert "secret" not in masked
    assert "https://REDACTED@example.com/path" == masked
    assert found


if __name__ == "__main__":
    test_rules_mask_secrets_and_pii()
    test_rules_preserve_plain_urls_and_placeholders()
    test_credentials_in_url_masked()
