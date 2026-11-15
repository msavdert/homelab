#!/usr/bin/env python3
"""Make sure the lab's wildcard DNS record exists in Cloudflare.

Ensures that zone savdert.com has exactly one A record *.lab.savdert.com
pointing at 10.0.6.20 (the Envoy Gateway address), not proxied, TTL
automatic. Reports "exists", "created" or "updated". It never deletes a
record and touches no other name.

The token comes from the environment variable CLOUDFLARE_API_TOKEN (the
dns:apply task injects it with `op run`) and is never printed. Python 3.11
or newer, standard library only.

Usage:
  infra/dns/apply.py            create or update the record
  infra/dns/apply.py --check    read only: report whether the record is correct
"""
import json
import os
import sys
import urllib.error
import urllib.parse
import urllib.request

API = "https://api.cloudflare.com/client/v4"
ZONE = "savdert.com"
NAME = "*.lab.savdert.com"
ADDRESS = "10.0.6.20"
TTL = 1  # automatic
PROXIED = False
COMMENT = "homelab Envoy Gateway (github.com/msavdert/homelab)"


def die(message):
    print(f"FAILED   {message}", file=sys.stderr)
    sys.exit(1)


def report(state, what):
    print(f"{state:<8} {what}", flush=True)


def api(method, path, body=None):
    """Call the Cloudflare API and return the "result" member. Stops on any error."""
    data = json.dumps(body).encode() if body is not None else None
    request = urllib.request.Request(
        f"{API}{path}", data=data, method=method,
        headers={
            # strip(): a trailing newline would make http.client raise an error
            # whose message contains the whole header.
            "Authorization": f"Bearer {os.environ['CLOUDFLARE_API_TOKEN'].strip()}",
            "Content-Type": "application/json",
        },
    )
    try:
        with urllib.request.urlopen(request, timeout=60) as response:
            payload = json.load(response)
    except urllib.error.HTTPError as error:
        detail = error.read().decode(errors="replace").strip()[:400]
        die(f"{method} {path}: HTTP {error.code} {error.reason} {detail}")
    except (urllib.error.URLError, TimeoutError, json.JSONDecodeError) as error:
        die(f"{method} {path}: {error}")
    if not payload.get("success"):
        die(f"{method} {path}: {payload.get('errors')}")
    return payload["result"]


def zone_id():
    zones = api("GET", f"/zones?name={urllib.parse.quote(ZONE)}")
    if len(zones) != 1:
        die(f"expected one zone named {ZONE}, found {len(zones)}")
    return zones[0]["id"]


def main():
    check = "--check" in sys.argv[1:]
    if any(arg != "--check" for arg in sys.argv[1:]):
        die("usage: apply.py [--check]")
    if not os.environ.get("CLOUDFLARE_API_TOKEN", "").strip():
        die("CLOUDFLARE_API_TOKEN is not set; run it through `mise run dns:apply`")
    zone = zone_id()
    query = urllib.parse.urlencode({"name": NAME, "type": "A"})
    records = api("GET", f"/zones/{zone}/dns_records?{query}")
    wanted = {"type": "A", "name": NAME, "content": ADDRESS, "ttl": TTL,
              "proxied": PROXIED, "comment": COMMENT}
    what = f"A {NAME} -> {ADDRESS}"
    if len(records) > 1:
        die(f"{len(records)} A records named {NAME}; remove the extra ones by hand")
    if not records:
        if check:
            report("missing", what)
            sys.exit(1)
        api("POST", f"/zones/{zone}/dns_records", wanted)
        report("created", what)
        return
    current = records[0]
    correct = (current["content"] == ADDRESS and current["ttl"] == TTL
               and current["proxied"] == PROXIED)
    if correct:
        report("exists", what)
    elif check:
        report("differs", f"A {NAME} is {current['content']}, "
               f"ttl {current['ttl']}, proxied {current['proxied']}; wanted {what}")
        sys.exit(1)
    else:
        api("PUT", f"/zones/{zone}/dns_records/{current['id']}", wanted)
        report("updated", what)


if __name__ == "__main__":
    try:
        main()
    except (KeyError, TypeError, AttributeError) as error:
        die(f"unexpected shape of an API response: {type(error).__name__}: {error}")
    except Exception as error:  # noqa: BLE001
        # Only the type: some messages (an invalid header) carry the token.
        die(f"unexpected error: {type(error).__name__}")
