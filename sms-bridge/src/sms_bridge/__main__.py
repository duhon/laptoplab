import subprocess
import time

from . import bridge, config


def runner(args):
    result = subprocess.run(args, capture_output=True, text=True)
    if result.returncode:
        detail = result.stderr.strip() or result.stdout.strip()
        raise RuntimeError(f"{args[0]} exited with status {result.returncode}: {detail}")
    return result.stdout


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
