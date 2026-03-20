#!/usr/bin/env python3
import argparse
import json
import os
import re
import subprocess
import sys
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from typing import List, Optional, Tuple


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Simulate upstream 429 for stream request and verify automatic failover."
    )
    parser.add_argument("--gateway-url", default="http://localhost:13030")
    parser.add_argument("--api-key", default=os.getenv("GATEWAY_TEST_API_KEY", "sk-gateway-demo-key-1"))
    parser.add_argument("--admin-token", default=os.getenv("GATEWAY_ADMIN_TOKEN", "change-me-admin-token"))
    parser.add_argument("--model", default="claw-primary")
    parser.add_argument("--mock-provider", default="provider-a")
    parser.add_argument("--fallback-provider", default="provider-b")
    parser.add_argument("--providers-file", default="configs/providers.yaml")
    parser.add_argument("--upstream-log", default="logs/upstream.log")
    parser.add_argument("--force-provider", default="provider-a")
    parser.add_argument("--mock-key-id", default="dashscope-coding-key-mock")
    parser.add_argument("--mock-port", type=int, default=18081)
    parser.add_argument("--reload-wait-sec", type=int, default=7)
    parser.add_argument("--timeout-sec", type=int, default=90)
    parser.add_argument("--restart-gateway", action="store_true")
    return parser.parse_args()


class Mock429Handler(BaseHTTPRequestHandler):
    def do_POST(self) -> None:
        _ = self.rfile.read(int(self.headers.get("Content-Length", "0")))
        payload = {
            "error": {
                "message": "mock rate limit",
                "type": "rate_limit_error",
                "code": "rate_limit_exceeded",
            }
        }
        body = json.dumps(payload).encode("utf-8")
        self.send_response(429)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, fmt: str, *args) -> None:
        return


def replace_provider_base_url(content: str, provider_name: str, new_base_url: str) -> str:
    lines = content.splitlines()
    in_provider = False
    provider_indent = "  "
    field_indent = "    "
    replaced = False

    for i, line in enumerate(lines):
        if re.match(r"^  [A-Za-z0-9._-]+:\s*$", line):
            in_provider = (line.strip() == f"{provider_name}:")
            continue
        if in_provider and line.startswith(provider_indent) and not line.startswith(field_indent):
            in_provider = False
        if in_provider and line.strip().startswith("base_url:"):
            lines[i] = f'{field_indent}base_url: "{new_base_url}"'
            replaced = True
            break

    if not replaced:
        raise RuntimeError(f"cannot find base_url for provider '{provider_name}'")
    return "\n".join(lines) + ("\n" if content.endswith("\n") else "")


def replace_provider_first_key_id(content: str, provider_name: str, new_key_id: str) -> str:
    lines = content.splitlines()
    in_provider = False
    provider_indent = "  "
    field_indent = "    "
    list_indent = "      "
    replaced = False

    for i, line in enumerate(lines):
        if re.match(r"^  [A-Za-z0-9._-]+:\s*$", line):
            in_provider = (line.strip() == f"{provider_name}:")
            continue
        if in_provider and line.startswith(provider_indent) and not line.startswith(field_indent):
            in_provider = False
        if in_provider and line.strip().startswith("- id:"):
            lines[i] = f'{list_indent}- id: "{new_key_id}"'
            replaced = True
            break

    if not replaced:
        raise RuntimeError(f"cannot find first key id for provider '{provider_name}'")
    return "\n".join(lines) + ("\n" if content.endswith("\n") else "")


def run_curl_stream(
    gateway_url: str,
    api_key: str,
    model: str,
    force_provider: str,
    trace_id: str,
    timeout_sec: int,
) -> Tuple[int, str, str]:
    payload = json.dumps(
        {
            "model": model,
            "provider": force_provider,
            "stream": True,
            "max_tokens": 16,
            "messages": [{"role": "user", "content": f"请只回复 ok；trace={trace_id}"}],
        },
        ensure_ascii=False,
    )
    cmd = [
        "curl",
        "-sS",
        "-N",
        "-i",
        "-X",
        "POST",
        f"{gateway_url}/v1/chat/completions",
        "-H",
        "Content-Type: application/json",
        "-H",
        f"x-api-key: {api_key}",
        "--data",
        payload,
    ]
    proc = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout_sec, check=False)
    output = proc.stdout

    # curl -i returns headers + body
    split = output.split("\r\n\r\n", 1)
    if len(split) == 2:
        raw_headers, body = split
    else:
        split = output.split("\n\n", 1)
        raw_headers, body = (split[0], split[1]) if len(split) == 2 else (output, "")

    status = 0
    req_id = None
    for line in raw_headers.splitlines():
        line_stripped = line.strip()
        if line_stripped.startswith("HTTP/"):
            parts = line_stripped.split()
            if len(parts) >= 2 and parts[1].isdigit():
                status = int(parts[1])
        if line_stripped.lower().startswith("x-request-id:"):
            req_id = line_stripped.split(":", 1)[1].strip()
    return proc.returncode, raw_headers, body


def providers_for_trace(upstream_log: Path, trace_id: str) -> List[str]:
    out: List[str] = []
    if not upstream_log.exists():
        return out
    with upstream_log.open("r", encoding="utf-8", errors="ignore") as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            try:
                row = json.loads(line)
            except json.JSONDecodeError:
                continue
            req = row.get("request")
            req_body = req.get("body") if isinstance(req, dict) else None
            if not isinstance(req_body, str) or f"trace={trace_id}" not in req_body:
                continue
            provider = row.get("provider")
            event = row.get("event")
            if event == "upstream_request" and isinstance(provider, str):
                out.append(provider)
    return out


def main() -> int:
    args = parse_args()
    providers_path = Path(args.providers_file)
    upstream_log = Path(args.upstream_log)
    if not providers_path.exists():
        print(f"[FAIL] providers file not found: {providers_path}")
        return 2

    original = providers_path.read_text(encoding="utf-8")
    mock_url = f"http://host.docker.internal:{args.mock_port}"
    patched = replace_provider_base_url(original, args.mock_provider, mock_url)
    patched = replace_provider_first_key_id(patched, args.mock_provider, args.mock_key_id)
    if mock_url not in patched:
        raise RuntimeError("patch verification failed: mock_url not present in providers content")

    server = ThreadingHTTPServer(("0.0.0.0", args.mock_port), Mock429Handler)
    server_thread = threading.Thread(target=server.serve_forever, daemon=True)
    server_thread.start()

    print(f"[INFO] mock 429 server started at 127.0.0.1:{args.mock_port}")
    print(f"[INFO] patch provider '{args.mock_provider}' -> {mock_url}")

    try:
        providers_path.write_text(patched, encoding="utf-8")
        if args.restart_gateway:
            print("[INFO] restarting gateway container for deterministic config pickup")
            subprocess.run(
                ["docker", "compose", "restart", "llm-gateway"],
                check=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
            )
        print(f"[INFO] waiting up to {max(args.reload_wait_sec, 20)}s for gateway config reload")
        active_base = None
        deadline = time.time() + max(args.reload_wait_sec, 20)
        while time.time() < deadline:
            try:
                with subprocess.Popen(
                    [
                        "curl",
                        "-sS",
                        f"{args.gateway_url}/admin/catalog?admin_token={args.admin_token}",
                    ],
                    stdout=subprocess.PIPE,
                    stderr=subprocess.PIPE,
                    text=True,
                ) as p:
                    out, _ = p.communicate(timeout=20)
                obj = json.loads(out)
                active_base = None
                for item in obj.get("providers", []):
                    if item.get("name") == args.mock_provider:
                        active_base = item.get("base_url")
                        break
                if active_base == mock_url:
                    break
            except Exception:
                pass
            time.sleep(1)
        print(f"[INFO] active {args.mock_provider}.base_url={active_base}")
        if active_base != mock_url:
            print("[FAIL] gateway did not pick patched provider base_url in time")
            return 5

        trace_id = f"failover429-{int(time.time())}"
        curl_rc, headers, body = run_curl_stream(
            gateway_url=args.gateway_url,
            api_key=args.api_key,
            model=args.model,
            force_provider=args.force_provider,
            trace_id=trace_id,
            timeout_sec=args.timeout_sec,
        )
        print(f"[INFO] curl rc={curl_rc}")
        print("----- response headers -----")
        print(headers)
        print("----- stream body (first 400 chars) -----")
        print(body[:400])

        status_match = re.search(r"HTTP/\d(?:\.\d)?\s+(\d+)", headers)
        status = int(status_match.group(1)) if status_match else 0

        has_sse_chunk = "data:" in body
        has_done = "[DONE]" in body

        seq = providers_for_trace(upstream_log, trace_id)
        print(f"[INFO] trace_id={trace_id}")
        print(f"[INFO] upstream provider sequence={seq}")

        has_mock_first = len(seq) >= 1 and seq[0] == args.mock_provider
        has_fallback = args.fallback_provider in seq[1:]

        ok = (
            curl_rc == 0
            and status == 200
            and has_sse_chunk
            and has_done
            and has_mock_first
            and has_fallback
        )
        if ok:
            print(
                "[PASS] stream request got 429 on first upstream and auto-failed over to fallback provider."
            )
            print("[PASS] client still received normal 200 SSE stream (application no-awareness).")
            return 0

        print("[FAIL] validation failed:")
        print(
            json.dumps(
                {
                    "curl_rc": curl_rc,
                    "http_status": status,
                    "has_sse_chunk": has_sse_chunk,
                    "has_done": has_done,
                    "provider_sequence": seq,
                    "mock_first": has_mock_first,
                    "fallback_seen": has_fallback,
                },
                ensure_ascii=False,
            )
        )
        return 4
    finally:
        providers_path.write_text(original, encoding="utf-8")
        print("[INFO] provider config restored")
        if args.restart_gateway:
            print("[INFO] restarting gateway container to apply restored config")
            subprocess.run(
                ["docker", "compose", "restart", "llm-gateway"],
                check=False,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
            )
        print(f"[INFO] waiting {args.reload_wait_sec}s for restore reload")
        time.sleep(args.reload_wait_sec)
        server.shutdown()
        server.server_close()
        print("[INFO] mock server stopped")


if __name__ == "__main__":
    sys.exit(main())
