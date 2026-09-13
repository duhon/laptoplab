from sms_bridge import telegram
from sms_bridge.modem import Sms

def test_format_message_includes_sender_and_text():
    sms = Sms(id="0", sender="+7999", text="Привет", timestamp="2026-09-13T10:00")
    msg = telegram.format_message(sms)
    assert "+7999" in msg and "Привет" in msg


class FakeResp:
    status_code = 200

def test_send_posts_to_telegram_api():
    calls = {}
    def poster(url, json, timeout):
        calls["url"] = url; calls["json"] = json
        return FakeResp()
    ok = telegram.send("TOK", "42", "hi", poster=poster)
    assert ok is True
    assert "botTOK/sendMessage" in calls["url"]
    assert calls["json"] == {"chat_id": "42", "text": "hi"}
