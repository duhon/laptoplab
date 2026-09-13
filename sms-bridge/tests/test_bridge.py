from sms_bridge import bridge, modem

def make_runner(ids, details):
    def runner(args):
        if "--messaging-list-sms" in args:
            return "\n".join(f"/SMS/{i} (received)" for i in ids)
        if "-s" in args:
            mid = args[args.index("-s") + 1]
            return details[mid]
        if "--messaging-delete-sms" in args:
            runner.deleted.append(args[-1]); return ""
        return ""
    runner.deleted = []
    return runner

def test_forward_new_sends_and_deletes():
    details = {"0": "number: +7999\ntext: hi\ntimestamp: 2026-09-13T10:00"}
    runner = make_runner(["0"], details)
    sent = []
    n = bridge.forward_new(runner, "TOK", "42",
                           sender=lambda t, c, txt: sent.append(txt) or True)
    assert n == 1
    assert sent and "hi" in sent[0]
    assert runner.deleted == ["0"]
