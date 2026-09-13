import re
from dataclasses import dataclass


@dataclass
class Sms:
    id: str
    sender: str
    text: str
    timestamp: str


def list_message_ids(runner) -> list[str]:
    out = runner(["mmcli", "-m", "any", "--messaging-list-sms"])
    return re.findall(r"/SMS/(\d+)", out)


def read_message(runner, msg_id: str) -> Sms:
    out = runner(["mmcli", "-m", "any", "-s", msg_id])
    number = re.search(r"number:\s*(\S+)", out)
    text = re.search(r"text:\s*(.+)", out)
    ts = re.search(r"timestamp:\s*(\S+)", out)
    return Sms(
        id=msg_id,
        sender=number.group(1) if number else "?",
        text=text.group(1).strip() if text else "",
        timestamp=ts.group(1) if ts else "",
    )


def delete_message(runner, msg_id: str) -> None:
    runner(["mmcli", "-m", "any", "--messaging-delete-sms", msg_id])
