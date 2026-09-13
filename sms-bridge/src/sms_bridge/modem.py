import re
from dataclasses import dataclass


@dataclass
class Sms:
    id: str
    sender: str
    text: str
    timestamp: str


def list_message_ids(runner) -> list[str]:
    out = runner(["mmcli", "-m", "any", "--messaging-list-sms", "-K"])
    return re.findall(r"/SMS/(\d+)", out)


def read_message(runner, msg_id: str) -> Sms:
    out = runner(["mmcli", "-m", "any", "-s", msg_id, "-K"])
    number = re.search(r"(?m)^[ \t]*sms\.content\.number[ \t]*:[ \t]*(\S+)", out)
    text = re.search(r"(?m)^[ \t]*sms\.content\.text[ \t]*:[ \t]*(.+?)[ \t]*$", out)
    ts = re.search(r"(?m)^[ \t]*sms\.properties\.timestamp[ \t]*:[ \t]*(\S+)", out)
    if not number or not text:
        raise ValueError(f"cannot parse SMS {msg_id} from mmcli -K output")
    return Sms(
        id=msg_id,
        sender=number.group(1),
        text=text.group(1).strip(),
        timestamp=ts.group(1) if ts else "",
    )


def delete_message(runner, msg_id: str) -> None:
    runner(["mmcli", "-m", "any", "--messaging-delete-sms", msg_id])
