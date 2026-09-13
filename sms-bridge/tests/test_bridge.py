from sms_bridge import bridge, modem


def make_runner(ids, details):
    def runner(args):
        if "--messaging-list-sms" in args:
            lines = ["modem.messaging.sms.length : %d" % len(ids)]
            for i, mid in enumerate(ids, 1):
                lines.append("modem.messaging.sms.value[%d] : /org/freedesktop/ModemManager1/SMS/%s" % (i, mid))
            return "\n".join(lines) + "\n"
        if "-s" in args:
            mid = args[args.index("-s") + 1]
            return details[mid]
        if "--messaging-delete-sms" in args:
            runner.deleted.append(args[-1]); return ""
        return ""
    runner.deleted = []
    return runner


def test_forward_new_sends_and_deletes():
    details = {"0": "sms.content.number : +7999\nsms.content.text : hi\nsms.properties.timestamp : 2026-09-13T10:00\n"}
    runner = make_runner(["0"], details)
    sent = []
    n = bridge.forward_new(runner, "TOK", "42",
                           sender=lambda t, c, txt: sent.append(txt) or True)
    assert n == 1
    assert sent and "hi" in sent[0]
    assert runner.deleted == ["0"]


def test_forward_new_keeps_sms_on_send_failure():
    details = {"0": "sms.content.number : +7999\nsms.content.text : hi\nsms.properties.timestamp : 2026-09-13T10:00\n"}
    runner = make_runner(["0"], details)
    n = bridge.forward_new(runner, "TOK", "42", sender=lambda t, c, txt: False)
    assert n == 0
    assert runner.deleted == []
