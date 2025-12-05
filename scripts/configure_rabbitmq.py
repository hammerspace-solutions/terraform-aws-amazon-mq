#!/usr/bin/env python3
import argparse, base64, json, sys
import requests

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--base-url", required=True)
    parser.add_argument("--user", required=True)
    parser.add_argument("--password", required=True)
    parser.add_argument("--config-b64", required=True)
    args = parser.parse_args()

    cfg = json.loads(base64.b64decode(args.config_b64).decode("utf-8"))

    vhost = cfg["vhost"]
    telemetry = cfg.get("telemetry")
    events = cfg.get("events")
    performance = cfg.get("performance")
    commands = cfg.get("commands")
    
    base = args.base_url.rstrip("/") + "/api"
    auth = (args.user, args.password)

    # 1. vhost
    r = requests.put(f"{base}/vhosts/{vhost}", auth=auth)
    r.raise_for_status()

    def ensure_exchange_and_queue(block):
        if not block:
            return
        ex = block["exchange"]
        q  = block["queue"]
        rk = block["routing_key"]

        # exchange
        r = requests.put(f"{base}/exchanges/{vhost}/{ex}", auth=auth,
                         json={"type": "topic", "durable": True})
        r.raise_for_status()

        # queue
        r = requests.put(f"{base}/queues/{vhost}/{q}", auth=auth,
                         json={"durable": True})
        r.raise_for_status()

        # binding
        r = requests.post(f"{base}/bindings/{vhost}/e/{ex}/q/{q}",
                          auth=auth,
                          json={"routing_key": rk})
        r.raise_for_status()

    for block in (telemetry, events, performance, commands):
        ensure_exchange_and_queue(block)

if __name__ == "__main__":
    sys.exit(main())
