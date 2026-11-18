#!/usr/bin/env python3
"""Gerania Hermes TUI-gateway probe.

Usage (any Python 3.10+; the script re-execs itself under Hermes's store Python when
``websockets`` is not importable):

    python3 tools/probe/gateway_probe.py --scenario handshake --record docs/protocol-samples/gateway-handshake.jsonl
    python3 tools/probe/gateway_probe.py --scenario simple --prompt "Reply with exactly: OK"
    python3 tools/probe/gateway_probe.py --scenario tool --prompt "Use the terminal tool to run: date -u"
    python3 tools/probe/gateway_probe.py --scenario interrupt --interrupt-after 2.0
    python3 tools/probe/gateway_probe.py --scenario approval --approval-choice deny

The probe never records the one-use gateway ticket. ``--record`` writes JSONL lines:
    {"t": <unix time>, "dir": "meta"|"send"|"recv", "name"?: str, "data"?: obj, "frame"?: obj}
"""

from __future__ import annotations

import argparse
import asyncio
import json
import os
import shutil
import socket
import subprocess
import sys
import time
import uuid
from pathlib import Path

HERMES_BIN = os.environ.get("HERMES_BIN") or shutil.which("hermes") or str(Path.home() / ".local/bin/hermes")
DEFAULT_SRC = Path(os.environ.get("HERMES_SRC") or (Path.home() / ".hermes" / "hermes-agent"))
GATEWAY_PROTOCOL = "hermes-gateway-v1"
TICKET_PREFIX = "hermes-gateway-ticket."


def _reexec_with_runtime() -> None:
    try:
        import websockets  # noqa: F401
        return
    except ImportError:
        pass
    if os.environ.get("GERANIA_PROBE_REEXEC") == "1":
        raise SystemExit("websockets is not importable even after re-exec under Hermes's runtime")
    try:
        done = subprocess.run([HERMES_BIN, "--print-runtime-command"], capture_output=True, text=True, timeout=120)
        command = json.loads(done.stdout)
    except Exception as exc:  # noqa: BLE001
        raise SystemExit(f"cannot resolve the Hermes runtime command: {exc}") from exc
    python = command[0]
    code = (
        "import os,sys,runpy;"
        f"sys.path.insert(0,{str(DEFAULT_SRC)!r});"
        "import hermes_bootstrap;"
        "sys.argv=sys.argv[1:];"
        "runpy.run_path(sys.argv[0],run_name='__main__')"
    )
    env = dict(os.environ, GERANIA_PROBE_REEXEC="1")
    os.execve(python, [python, "-I", "-c", code, os.path.abspath(__file__), *sys.argv[1:]], env)


_reexec_with_runtime()

from websockets.asyncio.client import connect  # noqa: E402


class Recorder:
    def __init__(self, path: str | None) -> None:
        self._fh = open(path, "w", encoding="utf-8") if path else None

    def _write(self, **line: object) -> None:
        if self._fh is None:
            return
        line = {"t": round(time.time(), 6), **line}
        self._fh.write(json.dumps(line, ensure_ascii=False) + "\n")
        self._fh.flush()

    def meta(self, name: str, **data: object) -> None:
        self._write(dir="meta", name=name, data=data)

    def send(self, frame: object) -> None:
        self._write(dir="send", frame=frame)

    def recv(self, frame: object) -> None:
        self._write(dir="recv", frame=frame)

    def close(self) -> None:
        if self._fh is not None:
            self._fh.close()


def ensure_gateway(timeout: int, recorder: Recorder) -> dict:
    started = time.time()
    done = subprocess.run(
        [HERMES_BIN, "gateway", "ensure", "--json", "--timeout", str(timeout)],
        capture_output=True, text=True, timeout=timeout + 30,
    )
    recorder.meta(
        "gateway.ensure", command=[HERMES_BIN, "gateway", "ensure", "--json", "--timeout", str(timeout)],
        exit_code=done.returncode, stdout=done.stdout.strip(), stderr=done.stderr.strip(),
        duration_s=round(time.time() - started, 3),
    )
    if done.returncode != 0:
        raise SystemExit(f"`hermes gateway ensure --json` exited {done.returncode}: {done.stderr.strip()}")
    payload = json.loads(done.stdout)
    if payload.get("state") != "ready":
        raise SystemExit(f"gateway is not ready: {payload}")
    return payload


def control_socket_path(home: Path) -> Path:
    direct = home / "gateway.sock"
    if direct.exists():
        return direct
    pointer = home / "gateway.sock.path"
    if pointer.exists():
        return Path(pointer.read_text(encoding="utf-8").strip())
    raise SystemExit(f"no gateway control socket under {home}")


def mint_ticket(payload: dict, timeout: float = 5.0) -> str:
    endpoint = payload.get("endpoint", payload)
    home = Path(endpoint.get("control_home") or endpoint["profile_id"])
    sock_path = control_socket_path(home)
    params = {
        "profile_id": endpoint["profile_id"],
        "instance_id": endpoint["instance_id"],
        "purpose": "interactive",
    }
    request = {"protocol": 1, "id": 1, "verb": "session-ticket", "params": params}
    with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as peer:
        peer.settimeout(timeout)
        peer.connect(str(sock_path))
        peer.sendall(json.dumps(request).encode() + b"\n")
        data = bytearray()
        while b"\n" not in data:
            chunk = peer.recv(65536)
            if not chunk:
                break
            data.extend(chunk)
    answer = json.loads(bytes(data).split(b"\n", 1)[0])
    grant = answer.get("result") if answer.get("ok") is True else None
    if not isinstance(grant, dict) or not grant.get("ticket"):
        raise SystemExit(f"control socket refused the ticket: {answer}")
    if grant.get("instance_id") != endpoint["instance_id"] or grant.get("profile_id") != endpoint["profile_id"]:
        raise SystemExit(f"ticket grant identity mismatch: {grant}")
    return grant["ticket"]


def ws_url(payload: dict) -> str:
    endpoint = payload.get("endpoint", payload)
    origin = endpoint["api_origin"]
    return origin.replace("https:", "wss:").replace("http:", "ws:") + "/api/ws"


class GatewayClient:
    def __init__(self, ws, recorder: Recorder, approval_choice: str) -> None:
        self.ws = ws
        self.rec = recorder
        self.approval_choice = approval_choice
        self.pending: dict[int, asyncio.Future] = {}
        self.events: asyncio.Queue = asyncio.Queue()
        self.requests: asyncio.Queue = asyncio.Queue()
        self._next_id = 0
        self._reader_task: asyncio.Task | None = None

    def start(self) -> None:
        self._reader_task = asyncio.create_task(self._reader())

    async def _reader(self) -> None:
        try:
            async for raw in self.ws:
                frame = json.loads(raw)
                self.rec.recv(frame)
                method = frame.get("method")
                if method == "event":
                    await self.events.put(frame)
                elif method and "id" in frame:
                    await self.requests.put(frame)
                elif "id" in frame:
                    future = self.pending.pop(frame["id"], None)
                    if future is not None and not future.done():
                        future.set_result(frame)
        except Exception as exc:  # noqa: BLE001
            for future in self.pending.values():
                if not future.done():
                    future.set_exception(exc)

    def _id(self) -> int:
        self._next_id += 1
        return self._next_id

    async def rpc(self, method: str, params: dict | None = None, timeout: float = 60.0) -> dict:
        rid = self._id()
        frame = {"jsonrpc": "2.0", "id": rid, "method": method}
        if params is not None:
            frame["params"] = params
        future = asyncio.get_running_loop().create_future()
        self.pending[rid] = future
        await self.ws.send(json.dumps(frame, ensure_ascii=False))
        self.rec.send(frame)
        try:
            return await asyncio.wait_for(future, timeout)
        except asyncio.TimeoutError as exc:
            self.pending.pop(rid, None)
            raise TimeoutError(f"{method} did not answer within {timeout}s") from exc

    async def answer_request(self, frame: dict) -> None:
        method = frame.get("method")
        rid = frame.get("id")
        if method == "approval":
            result = {"choice": self.approval_choice}
        elif method == "clarify":
            result = {"answers": {}}
        elif method in {"sudo", "secret", "vault"}:
            result = {"value": ""}
        else:
            result = {"value": ""}
        answer = {"jsonrpc": "2.0", "id": rid, "result": result}
        await self.ws.send(json.dumps(answer, ensure_ascii=False))
        self.rec.send(answer)
        self.rec.meta("server_request.answer", request_id=rid, method=method, result=result)

    async def pump_requests(self) -> None:
        while True:
            frame = await self.requests.get()
            self.rec.meta(
                "server_request", request_id=frame.get("id"), method=frame.get("method"),
                params=frame.get("params"),
            )
            await self.answer_request(frame)


async def wait_event(client: GatewayClient, predicate, timeout: float) -> dict:
    deadline = time.monotonic() + timeout
    while True:
        remaining = deadline - time.monotonic()
        if remaining <= 0:
            raise TimeoutError("timed out waiting for event")
        frame = await asyncio.wait_for(client.events.get(), remaining)
        params = frame.get("params") or {}
        if predicate(params):
            return frame


def _event_type(frame: dict) -> str:
    return str((frame.get("params") or {}).get("type") or "")


async def collect_turn(client: GatewayClient, sid: str, timeout: float, recorder: Recorder,
                       *, interrupt_after: float | None = None) -> dict:
    text: list[str] = []
    reasoning: list[str] = []
    tool_calls: list[dict] = []
    interrupt_task: asyncio.Task | None = None
    deadline = time.monotonic() + timeout
    while True:
        remaining = deadline - time.monotonic()
        if remaining <= 0:
            raise TimeoutError("turn did not complete in time")
        frame = await asyncio.wait_for(client.events.get(), remaining)
        params = frame.get("params") or {}
        if params.get("session_id") and params.get("session_id") != sid:
            continue
        kind = params.get("type")
        payload = params.get("payload") or {}
        if kind == "message.start":
            generation = params.get("execution_generation")
            if interrupt_after is not None and isinstance(generation, int):
                async def interrupt_later() -> None:
                    await asyncio.sleep(interrupt_after)
                    interrupt_params = {"session_id": sid, "execution_generation": generation}
                    answer = await client.rpc("session.interrupt", interrupt_params, timeout=30)
                    recorder.meta("session.interrupt", request=interrupt_params, response=answer)
                interrupt_task = asyncio.create_task(interrupt_later())
        elif kind == "message.delta":
            text.append(payload.get("text") or "")
        elif kind in {"reasoning.delta", "thinking.delta"}:
            reasoning.append(payload.get("text") or "")
        elif kind == "tool.start":
            tool_calls.append({"phase": "start", "name": payload.get("name"), "id": payload.get("tool_id")})
        elif kind == "tool.complete":
            tool_calls.append({"phase": "complete", "name": payload.get("name"), "id": payload.get("tool_id")})
        elif kind == "error":
            recorder.meta("turn.error", payload=payload)
            return {"text": "".join(text), "reasoning": "".join(reasoning), "tools": tool_calls,
                    "status": "error", "error": payload.get("message")}
        elif kind == "message.complete":
            recorder.meta("turn.complete", payload=payload)
            return {"text": "".join(text), "final_text": payload.get("text"),
                    "reasoning": "".join(reasoning), "tools": tool_calls,
                    "status": payload.get("status"), "usage": payload.get("usage"),
                    "outcome": payload.get("outcome")}
        if interrupt_task is not None and interrupt_task.done():
            interrupt_task = None


def choose_source(create_result: dict, requested: str) -> str:
    info = create_result.get("info") or {}
    if info.get("source"):
        return str(info["source"])
    return requested


async def scenario(args: argparse.Namespace, recorder: Recorder) -> int:
    endpoint = ensure_gateway(args.timeout, recorder)
    ticket = mint_ticket(endpoint)
    url = ws_url(endpoint)
    protocols = [GATEWAY_PROTOCOL, TICKET_PREFIX + ticket]
    recorder.meta("gateway.endpoint", endpoint=endpoint["endpoint"], state=endpoint.get("state"),
                  url=url, protocols=[GATEWAY_PROTOCOL, "<one-use ticket>"], ticket_ttl_hint_s=30)

    async with connect(url, subprotocols=protocols, open_timeout=10, max_size=8 * 1024 * 1024,
                       proxy=None) as ws:
        recorder.meta("gateway.ws.open", subprotocol=ws.subprotocol)
        if ws.subprotocol != GATEWAY_PROTOCOL:
            raise SystemExit(f"unexpected subprotocol: {ws.subprotocol!r}")
        client = GatewayClient(ws, recorder, args.approval_choice)
        client.start()
        requests_task = asyncio.create_task(client.pump_requests())
        try:
            ready = await wait_event(client, lambda p: p.get("type") == "gateway.ready", 15)
            recorder.meta("gateway.ready", params=ready.get("params"))
            caps = await client.rpc("client.capabilities", {"server_requests": True}, timeout=15)
            recorder.meta("client.capabilities", response=caps)
            runtime = await client.rpc("runtime.describe", {}, timeout=15)
            recorder.meta("runtime.describe", response=runtime)
            if args.scenario == "handshake":
                ping = await client.rpc("ping", {}, timeout=15)
                recorder.meta("ping", response=ping)
                gateway_caps = await client.rpc("gateway.capabilities", {}, timeout=15)
                recorder.meta("gateway.capabilities", response=gateway_caps)
                listing = await client.rpc("session.list", {"scope": args.scope, "limit": args.limit}, timeout=30)
                recorder.meta("session.list", response=listing)
                result = {"scenario": "handshake", "subprotocol": ws.subprotocol,
                          "ready": ready.get("params"), "runtime": runtime.get("result"),
                          "ping": ping.get("result"), "gateway_capabilities": gateway_caps.get("result"),
                          "list_error": listing.get("error"),
                          "sessions": len((listing.get("result") or {}).get("sessions") or [])}
                print(json.dumps(result, ensure_ascii=False))
                return 0

            create_params: dict = {
                "request_id": uuid.uuid4().hex,
                "source": args.source,
                "cwd": args.cwd,
                "title": f"gerania-probe-{args.scenario}-{int(time.time())}",
            }
            if args.model:
                create_params["model"] = args.model
            if args.provider:
                create_params["provider"] = args.provider
            create = await client.rpc("session.create", create_params, timeout=60)
            recorder.meta("session.create", request=create_params, response=create)
            if "error" in create:
                raise SystemExit(f"session.create failed: {create['error']}")
            created = create.get("result") or {}
            sid = created.get("session_id")
            if not sid:
                raise SystemExit(f"session.create returned no session_id: {created}")
            recorder.meta("session.identity", runtime_session_id=sid,
                          stored_session_id=created.get("stored_session_id"),
                          source=choose_source(created, args.source),
                          execution_generation=created.get("execution_generation"),
                          authority_epoch=created.get("authority_epoch"))

            prompt = args.prompt or {
                "simple": "Reply with exactly one word: OK",
                "markdown": ("Answer in Russian. Reply with a short markdown table with two columns "
                             "(Term, Meaning) and two rows, then a fenced python code block that prints OK. "
                             "Keep it under 15 lines."),
                "tool": ("Use the terminal tool to run exactly: date -u +%FT%TZ . "
                         "Then reply with the command output on one line."),
                "interrupt": ("Write a detailed 2000-word essay about the history of Unix. "
                              "Do not use tools."),
                "approval": ("Use the terminal tool to run exactly this command and nothing else: "
                             "rm -f /tmp/gerania-probe/does-not-exist.txt . "
                             "Then report what happened."),
            }.get(args.scenario, args.prompt or "Reply with exactly one word: OK")

            submit_params: dict = {"session_id": sid, "text": prompt, "submission_id": uuid.uuid4().hex}
            started = time.monotonic()
            submitted = await client.rpc("prompt.submit", submit_params, timeout=30)
            recorder.meta("prompt.submit.status", status=(submitted.get("result") or {}).get("status"))
            recorder.meta("prompt.submit", request=submit_params, response=submitted,
                          duration_ms=int((time.monotonic() - started) * 1000))
            if "error" in submitted:
                raise SystemExit(f"prompt.submit failed: {submitted['error']}")

            turn = await collect_turn(
                client, sid, args.answer_timeout, recorder,
                interrupt_after=(args.interrupt_after if args.scenario == "interrupt" else None),
            )
            print(json.dumps({"scenario": args.scenario, "session_id": sid, "turn": turn}, ensure_ascii=False))
            return 0 if turn.get("status") != "error" else 1
        finally:
            requests_task.cancel()
            with __import__("contextlib").suppress(asyncio.CancelledError):
                await requests_task
            if client._reader_task is not None:
                client._reader_task.cancel()
                with __import__("contextlib").suppress(asyncio.CancelledError):
                    await client._reader_task


def main() -> int:
    parser = argparse.ArgumentParser(description="Probe the Hermes TUI gateway over WebSocket.")
    parser.add_argument("--scenario", default="simple",
                        choices=["handshake", "simple", "markdown", "tool", "interrupt", "approval"])
    parser.add_argument("--prompt", default=None)
    parser.add_argument("--record", default=None, help="JSONL file for recorded frames")
    parser.add_argument("--source", default="gui", help="session.create source (gui/tui/cli/oneshot)")
    parser.add_argument("--cwd", default=str(Path.cwd()))
    parser.add_argument("--model", default=None)
    parser.add_argument("--provider", default=None)
    parser.add_argument("--approval-choice", default="deny", choices=["once", "session", "always", "deny"])
    parser.add_argument("--timeout", type=int, default=60, help="gateway ensure deadline, seconds")
    parser.add_argument("--answer-timeout", type=float, default=180.0)
    parser.add_argument("--interrupt-after", type=float, default=2.0)
    parser.add_argument("--limit", type=int, default=10)
    parser.add_argument("--scope", default="live", choices=["live", "stored"])
    args = parser.parse_args()

    recorder = Recorder(args.record)
    recorder.meta("probe.start", scenario=args.scenario, argv=sys.argv[1:],
                  hermes_bin=HERMES_BIN, python=sys.executable)
    try:
        return asyncio.run(scenario(args, recorder))
    finally:
        recorder.close()


if __name__ == "__main__":
    raise SystemExit(main())
