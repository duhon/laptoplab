from . import modem, telegram


def forward_new(runner, token, chat_id, sender=telegram.send) -> int:
    count = 0
    for msg_id in modem.list_message_ids(runner):
        sms = modem.read_message(runner, msg_id)
        if sender(token, chat_id, telegram.format_message(sms)):
            modem.delete_message(runner, msg_id)
            count += 1
    return count
