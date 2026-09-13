def format_message(sms) -> str:
    return f"📩 SMS от {sms.sender}\n{sms.text}\n\n{sms.timestamp}"


def send(token: str, chat_id: str, text: str, poster=None) -> bool:
    if poster is None:
        import requests
        poster = requests.post
    r = poster(
        f"https://api.telegram.org/bot{token}/sendMessage",
        json={"chat_id": chat_id, "text": text},
        timeout=15,
    )
    return getattr(r, "status_code", 500) == 200
