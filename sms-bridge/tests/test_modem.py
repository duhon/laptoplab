from sms_bridge import modem

LIST_OUT = """\
/org/freedesktop/ModemManager1/SMS/0 (received)
/org/freedesktop/ModemManager1/SMS/2 (received)
"""

def test_list_message_ids_parses_paths():
    runner = lambda args: LIST_OUT
    assert modem.list_message_ids(runner) == ["0", "2"]


DETAIL_OUT = """\
  -----------------------------
  Content    |  number: +79991234567
             |    text: Привет мир
  -----------------------------
  Properties |    timestamp: 2026-09-13T10:00:00+03:00
"""

def test_read_message_parses_fields():
    runner = lambda args: DETAIL_OUT
    sms = modem.read_message(runner, "0")
    assert sms.id == "0"
    assert sms.sender == "+79991234567"
    assert sms.text == "Привет мир"
    assert sms.timestamp.startswith("2026-09-13")
