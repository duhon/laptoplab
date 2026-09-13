from . import modem, telegram


def forward_new(runner, token, chat_id, sender=telegram.send) -> int:
    count = 0
    for msg_id in modem.list_message_ids(runner):
        try:
            sms = modem.read_message(runner, msg_id)
        except Exception as e:
            print(f"skip SMS {msg_id}: {e}", flush=True)
            continue
        if sender(token, chat_id, telegram.format_message(sms)):
            modem.delete_message(runner, msg_id)
            count += 1
    return count
