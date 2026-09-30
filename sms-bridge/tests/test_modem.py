from sms_bridge import modem

LIST_OUT = """\
modem.messaging.sms.length     : 2
modem.messaging.sms.value[1]   : /org/freedesktop/ModemManager1/SMS/0
modem.messaging.sms.value[2]   : /org/freedesktop/ModemManager1/SMS/2
"""

def test_list_message_ids_parses_paths():
    runner = lambda args: LIST_OUT
    assert modem.list_message_ids(runner) == ["0", "2"]


def test_list_message_ids_returns_empty_when_no_messages():
    runner = lambda args: "modem.messaging.sms : 0\n"
    assert modem.list_message_ids(runner) == []


DETAIL_OUT = """\
sms.content.number       : +79991234567
sms.content.text         : Привет мир
sms.properties.timestamp : 2026-09-13T10:00:00+03:00
sms.properties.state     : received
"""

def test_read_message_parses_fields():
    runner = lambda args: DETAIL_OUT
    sms = modem.read_message(runner, "0")
    assert sms.id == "0"
    assert sms.sender == "+79991234567"
    assert sms.text == "Привет мир"
    assert sms.timestamp.startswith("2026-09-13")


def test_read_message_raises_on_unparseable():
    import pytest
    runner = lambda args: "sms.properties.state : received\n"
    with pytest.raises(ValueError):
        modem.read_message(runner, "9")


def test_read_message_raises_on_empty_field():
    import pytest
    runner = lambda args: "sms.content.number : \nsms.content.text : hi\nsms.properties.timestamp : x\n"
    with pytest.raises(ValueError):
        modem.read_message(runner, "0")
