import subprocess
import time

from . import bridge, config


def runner(args):
    return subprocess.run(args, capture_output=True, text=True).stdout


def main():
    token, chat_id, interval = config.load()
    while True:
        try:
            bridge.forward_new(runner, token, chat_id)
        except Exception as e:
            print("err:", e, flush=True)
        time.sleep(interval)


if __name__ == "__main__":
    main()
