import os


def load():
    return (
        os.environ["TELEGRAM_BOT_TOKEN"],
        os.environ["TELEGRAM_CHAT_ID"],
        int(os.environ.get("POLL_INTERVAL", "30")),
    )
