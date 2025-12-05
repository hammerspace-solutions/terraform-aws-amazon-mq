#!/usr/bin/env python3
import argparse
import base64
import json
import sys

import requests


def ensure_exchange_and_queues(base, auth, vhost, block):
  """
  Create:
    - 1 exchange (topic, durable)
    - N queues
    - N bindings (exchange -> queue with routing_key)

  Supports two shapes:

    NEW:
      {
        "exchange": "telemetry",
        "queues": [
          { "name": "telemetry.to-aws", "routing_key": "#" },
          { "name": "telemetry.to-analytics", "routing_key": "analytics.#" }
        ]
      }

    LEGACY:
      {
        "exchange": "telemetry",
        "queue": "telemetry.to-aws",
        "routing_key": "#"
      }
  """
  if not block:
    return

  ex = block.get("exchange")
  if not ex:
    return

  # Build list of (queue_name, routing_key) pairs
  queue_specs = []

  if isinstance(block.get("queues"), list) and block["queues"]:
    # New-style multi-queue config
    for q in block["queues"]:
      name = q.get("name")
      if not name:
        continue
      rk = q.get("routing_key", block.get("routing_key", "#"))
      queue_specs.append((name, rk))
  elif "queue" in block:
    # Legacy single-queue shape
    name = block["queue"]
    rk = block.get("routing_key", "#")
    queue_specs.append((name, rk))
  else:
    # Nothing usable
    return

  # 1) Ensure the exchange exists
  r = requests.put(
    f"{base}/exchanges/{vhost}/{ex}",
    auth=auth,
    json={"type": "topic", "durable": True},
  )
  r.raise_for_status()

  # 2) Ensure each queue + binding exists
  for q_name, rk in queue_specs:
    # Queue
    r = requests.put(
      f"{base}/queues/{vhost}/{q_name}",
      auth=auth,
      json={"durable": True},
    )
    r.raise_for_status()

    # Binding exchange -> queue
    r = requests.post(
      f"{base}/bindings/{vhost}/e/{ex}/q/{q_name}",
      auth=auth,
      json={"routing_key": rk},
    )
    r.raise_for_status()


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

  # 1. Ensure vhost exists
  r = requests.put(f"{base}/vhosts/{vhost}", auth=auth)
  r.raise_for_status()

  # 2. Exchanges, queues, bindings
  for block in (telemetry, events, performance, commands):
    ensure_exchange_and_queues(base, auth, vhost, block)


if __name__ == "__main__":
  sys.exit(main())
