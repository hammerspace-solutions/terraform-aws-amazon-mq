#!/usr/bin/env python3
import argparse
import base64
import json
import sys

import requests


def main() -> int:
    parser = argparse.ArgumentParser(
        description=(
            "Configure central Amazon MQ RabbitMQ broker (vhost, exchanges, "
            "queues, bindings) from a base64-encoded site config JSON."
        )
    )
    parser.add_argument("--base-url", required=True, help="RabbitMQ management base URL (console_url)")
    parser.add_argument("--user", required=True, help="RabbitMQ admin username")
    parser.add_argument("--password", required=True, help="RabbitMQ admin password")
    parser.add_argument("--config-b64", required=True, help="Base64-encoded site config JSON")
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="If set, do not call the RabbitMQ API; just print what would be done.",
    )
    args = parser.parse_args()

    # Decode the config JSON
    cfg = json.loads(base64.b64decode(args.config_b64).decode("utf-8"))

    # Expected schema (per site JSON):
    #
    # {
    #   "vhost": "kade",
    #
    #   "telemetry": {
    #       "exchange": "telemetry",
    #       "queues": [
    #           { "name": "hammerspace.to-aws", "routing_key": "hammerspace.#" },
    #           { "name": "catalog.to-aws",     "routing_key": "catalog.#" }
    #       ]
    #       // or legacy:
    #       // "queue": "telemetry.to-aws",
    #       // "routing_key": "#"
    #   },
    #
    #   "events": { ... },
    #   "performance": { ... },
    #   "commands": {
    #       "exchange": "commands",
    #       "queues": [
    #           { "name": "hammerspace.from-aws", "routing_key": "hammerspace.#" },
    #           { "name": "catalog.from-aws",     "routing_key": "catalog.#" }
    #       ]
    #       // NOTE: On the CENTRAL broker we *do not* create these queues.
    #   }
    # }
    #
    # Central-side role:
    #   - telemetry/events/performance: exchanges + queues + bindings
    #   - commands: exchange only (queues live on the site broker)
    #

    vhost = cfg["vhost"]

    sections = {
        "telemetry": cfg.get("telemetry"),
        "events": cfg.get("events"),
        "performance": cfg.get("performance"),
        "commands": cfg.get("commands"),
    }

    base = args.base_url.rstrip("/") + "/api"
    auth = (args.user, args.password)
    dry_run = args.dry_run

    # -------------------------------------------------------------------------
    # Helper functions
    # -------------------------------------------------------------------------

    def log(msg: str) -> None:
        # Simple logger; could be improved later
        print(msg)

    def req(method: str, url: str, **kwargs):
        """
        Wrapper around requests.request that honors --dry-run.

        In dry-run mode:
          - Print the intended call
          - Do not hit the API
        """
        if dry_run:
            payload = kwargs.get("json")
            if payload is not None:
                log(f"[DRY-RUN] {method} {url} json={json.dumps(payload)}")
            else:
                log(f"[DRY-RUN] {method} {url}")
            return None

        r = requests.request(method, url, auth=auth, **kwargs)
        r.raise_for_status()
        return r

    def ensure_vhost(name: str) -> None:
        # PUT /api/vhosts/{vhost}
        log(f"Ensuring vhost '{name}'")
        req("PUT", f"{base}/vhosts/{name}")

    def ensure_exchange(block: dict | None) -> None:
        if not block:
            return
        ex = block.get("exchange")
        if not ex:
            return
        log(f"Ensuring exchange '{ex}' in vhost '{vhost}'")
        # PUT /api/exchanges/{vhost}/{exchange}
        req(
            "PUT",
            f"{base}/exchanges/{vhost}/{ex}",
            json={"type": "topic", "durable": True},
        )

    def queues_for_block(name: str, block: dict | None) -> list[tuple[str, str, str]]:
        """
        Return a list of (exchange_name, queue_name, routing_key) tuples
        for blocks that should have queues on the CENTRAL broker.

        - telemetry/events/performance:
            use cfg.queues[] if present, else fall back to cfg.queue + cfg.routing_key
        - commands:
            return [] (queues live on the site broker only)
        """
        if not block:
            return []

        ex = block.get("exchange")
        if not ex:
            return []

        # Central broker: no commands queues
        if name == "commands":
            return []

        result: list[tuple[str, str, str]] = []

        # Prefer new-style "queues" array
        queues = block.get("queues")
        if isinstance(queues, list) and queues:
            for q in queues:
                q_name = q.get("name")
                if not q_name:
                    continue
                rk = q.get("routing_key", "#")
                result.append((ex, q_name, rk))
            return result

        # Fallback: legacy single queue + routing_key
        q_name = block.get("queue")
        if q_name:
            rk = block.get("routing_key", "#")
            result.append((ex, q_name, rk))

        return result

    def ensure_queues_and_bindings(name: str, block: dict | None) -> None:
        tuples = queues_for_block(name, block)
        for ex, q_name, rk in tuples:
            log(f"Ensuring queue '{q_name}' (vhost '{vhost}') and binding from exchange '{ex}' with routing_key='{rk}'")
            # PUT /api/queues/{vhost}/{queue}
            req(
                "PUT",
                f"{base}/queues/{vhost}/{q_name}",
                json={"durable": True},
            )
            # POST /api/bindings/{vhost}/e/{exchange}/q/{queue}
            req(
                "POST",
                f"{base}/bindings/{vhost}/e/{ex}/q/{q_name}",
                json={"routing_key": rk},
            )

    # -------------------------------------------------------------------------
    # Apply configuration to central broker
    # -------------------------------------------------------------------------

    log(f"Configuring central broker for site vhost '{vhost}' (dry_run={dry_run})")

    # 1. Ensure vhost
    ensure_vhost(vhost)

    # 2. Ensure all exchanges
    for block in sections.values():
        ensure_exchange(block)

    # 3. Ensure queues + bindings for telemetry/events/performance only
    for name, block in sections.items():
        ensure_queues_and_bindings(name, block)

    log("Configuration complete.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
