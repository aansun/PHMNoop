#!/usr/bin/env python3
"""Lets a debug build of PHMN in the iOS Simulator talk to Claude through the `claude` command on this Mac.

    python3 Tools/anya-bridge/bridge.py                 # then launch the simulator app with --anya-bridge http://127.0.0.1:8787

A development tool only. It answers a subset of the Anthropic Messages API on 127.0.0.1 and runs `claude -p` for each
conversation, signed in the way that command already is on this Mac; no key is read, stored or passed on. (The command itself attaches the
account's e-mail address to each conversation; see ACCOUNT_NOTE.) The command runs
with every built-in tool switched off, no settings, no MCP servers of the user's own, in an empty folder. The only tools the
model can call are the ones the app sends, and the app runs them: this server only carries the call there and the result back.

How tools work: the app's tool definitions are offered to `claude` through a small MCP server (this same file, started with
--mcp). When the model calls one, the HTTP reply ends with the usual `tool_use` blocks and the process is kept waiting. The
app's next request carries the `tool_result` blocks, they are handed to the waiting calls, and the reply continues.
"""

import argparse
import json
import os
import queue
import subprocess
import sys
import tempfile
import threading
import time
import urllib.request
import uuid
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

MCP_PREFIX = "mcp__anya__"
# The command attaches the e-mail address of the account it is signed in with, and has no switch to leave it out. The app never sends it, so the
# model is told not to use it: replies must be what the app would get, and carry nothing about whoever runs the bridge.
ACCOUNT_NOTE = ("\n\nA note with an account e-mail address may be attached to this conversation by the tool carrying it. It is not part of what the app "
                "tells you about the person: never use it, quote it, or take a name from it.")
MODELS = ["claude-haiku-5-5", "claude-sonnet-5-5", "claude-opus-5-5"]
IDLE_LIMIT = 180


# MARK: - The MCP side: a stdio server that forwards every call to the bridge

def run_mcp(url):
    out_lock = threading.Lock()

    def reply(message_id, result=None, error=None):
        body = {"jsonrpc": "2.0", "id": message_id}
        if error:
            body["error"] = {"code": -32601, "message": error}
        else:
            body["result"] = result
        with out_lock:
            sys.stdout.write(json.dumps(body) + "\n")
            sys.stdout.flush()

    def http(path, body=None):
        data = None if body is None else json.dumps(body).encode()
        request = urllib.request.Request(url + path, data=data, headers={"content-type": "application/json"})
        with urllib.request.urlopen(request, timeout=IDLE_LIMIT + 10) as response:
            return json.load(response)

    def call(message_id, params):
        try:
            answer = http("/call", {"name": params.get("name"), "arguments": params.get("arguments") or {}})
        except Exception as error:  # the app went away, or the conversation was dropped
            answer = {"content": "The tool could not be run: %s" % error, "is_error": True}
        reply(message_id, {"content": [{"type": "text", "text": answer.get("content", "")}], "isError": bool(answer.get("is_error"))})

    for line in sys.stdin:
        try:
            message = json.loads(line)
        except ValueError:
            continue
        method, message_id = message.get("method"), message.get("id")
        if message_id is None:
            continue
        if method == "initialize":
            version = (message.get("params") or {}).get("protocolVersion", "2025-06-18")
            reply(message_id, {"protocolVersion": version, "capabilities": {"tools": {}}, "serverInfo": {"name": "anya", "version": "1"}})
        elif method == "tools/list":
            tools = http("/tools")["tools"]
            reply(message_id, {"tools": [{"name": t["name"], "description": t.get("description", ""),
                                          "inputSchema": t.get("input_schema", {"type": "object"})} for t in tools]})
        elif method == "tools/call":
            threading.Thread(target=call, args=(message_id, message.get("params") or {}), daemon=True).start()
        elif method == "ping":
            reply(message_id, {})
        else:
            reply(message_id, error="unknown method %s" % method)


# MARK: - One conversation turn held by a `claude` process

class Session:
    def __init__(self, tools):
        self.id = uuid.uuid4().hex
        self.tools = tools
        self.events = queue.Queue()
        self.condition = threading.Condition()
        self.asked = []      # tool_use blocks of the message just sent to the app: {id, name, input, taken}
        self.results = {}    # tool_use_id -> {content, is_error}
        self.process = None
        self.touched = time.time()
        self.closed = False

    def close(self):
        with self.condition:
            self.closed = True
            self.condition.notify_all()
        if self.process and self.process.poll() is None:
            self.process.kill()

    def wait_for_result(self, name, arguments):
        """Called for the MCP server: the result the app sends for this call, once it does."""
        deadline = time.time() + IDLE_LIMIT
        with self.condition:
            while not self.closed and time.time() < deadline:
                match = next((b for b in self.asked if not b["taken"] and b["name"] == name and b["input"] == arguments), None)
                if match is None:
                    match = next((b for b in self.asked if not b["taken"] and b["name"] == name), None)
                if match and match["id"] in self.results:
                    match["taken"] = True
                    return self.results.pop(match["id"])
                self.condition.wait(1)
        return {"content": "No result arrived from the app.", "is_error": True}


class Bridge:
    def __init__(self, port, show):
        self.port, self.show = port, show
        self.sessions = {}
        self.lock = threading.Lock()
        self.cwd = tempfile.mkdtemp(prefix="anya-bridge-")

    def log(self, text):
        print(time.strftime("%H:%M:%S"), text, flush=True)

    @staticmethod
    def text_of(content, note_images=True):
        if isinstance(content, str):
            return content
        parts = []
        for block in content or []:
            if block.get("type") == "text":
                parts.append(block.get("text", ""))
            elif block.get("type") == "image" and note_images:
                parts.append("[an image was attached to this earlier message]")
        return "\n".join(parts)

    def prompt_of(self, messages):
        """`claude -p` takes one prompt, so earlier turns are written out above the new one."""
        if len(messages) == 1:
            return self.text_of(messages[0]["content"], note_images=False)
        earlier = []
        for m in messages[:-1]:
            text = self.text_of(m["content"]).strip()
            if text:
                earlier.append(("Person: " if m["role"] == "user" else "You (Anya): ") + text)
        return ("<conversation_so_far>\n" + "\n\n".join(earlier) + "\n</conversation_so_far>\n\n"
                "Continue it: answer the person's new message below, as Anya.\n\n" + self.text_of(messages[-1]["content"], note_images=False))

    @staticmethod
    def images_of(messages):
        """The pictures sent with the new message. A picture from an earlier turn is only mentioned."""
        content = messages[-1].get("content") if messages else None
        return [b for b in content if b.get("type") == "image"] if isinstance(content, list) else []

    def start(self, body):
        tools = body.get("tools") or []
        session = Session(tools)
        system = self.text_of(body.get("system") or "") + ACCOUNT_NOTE
        model = body.get("model") or MODELS[0]
        effort = (body.get("output_config") or {}).get("effort") or "low"
        command = ["claude", "-p", "--model", model, "--effort", effort, "--system-prompt", system,
                   "--tools", "", "--strict-mcp-config", "--setting-sources", "", "--disable-slash-commands", "--no-session-persistence",
                   "--output-format", "stream-json", "--include-partial-messages", "--verbose"]
        messages = body.get("messages") or []
        images = self.images_of(messages)
        if images:
            # Pictures only travel as whole messages, one JSON line each.
            command += ["--input-format", "stream-json"]
        if tools:
            mcp = {"mcpServers": {"anya": {"command": sys.executable, "args": [
                os.path.abspath(__file__), "--mcp", "http://127.0.0.1:%d/_mcp/%s" % (self.port, session.id)]}}}
            command += ["--mcp-config", json.dumps(mcp), "--allowedTools", ",".join(MCP_PREFIX + t["name"] for t in tools)]
        # The command signs in the way it normally does; nothing set for this shell is allowed to send it elsewhere.
        env = {k: v for k, v in os.environ.items() if not k.startswith(("ANTHROPIC_", "CLAUDE_CODE_")) and k != "CLAUDECODE"}
        env.update({"ENABLE_TOOL_SEARCH": "false", "MCP_TOOL_TIMEOUT": str(IDLE_LIMIT * 1000)})
        session.process = subprocess.Popen(command, cwd=self.cwd, env=env, stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                                           stderr=subprocess.PIPE, text=True)
        with self.lock:
            self.sessions[session.id] = session
        prompt = self.prompt_of(messages)
        if self.show:
            sizes = ", ".join("%d KB" % (len((b.get("source") or {}).get("data", "")) * 3 // 4 // 1024) for b in images)
            self.log("--- system (%d chars)\n%s\n--- prompt%s\n%s" % (len(system), system, " (pictures: %s)" % sizes if images else "", prompt))
        if images:
            line = {"type": "user", "message": {"role": "user", "content": images + [{"type": "text", "text": prompt}]}}
            prompt = json.dumps(line) + "\n"

        def pump():
            errors = []
            threading.Thread(target=lambda: errors.extend(session.process.stderr.readlines()), daemon=True).start()
            try:
                session.process.stdin.write(prompt)
                session.process.stdin.close()
                for line in session.process.stdout:
                    try:
                        session.events.put(json.loads(line))
                    except ValueError:
                        pass
                session.process.wait()
            finally:
                session.events.put({"type": "_end", "error": "".join(errors)[-800:], "code": session.process.returncode})

        threading.Thread(target=pump, daemon=True).start()
        return session

    def resume(self, body):
        """The waiting session this request carries tool results for, with the results handed over; None for a new turn."""
        messages = body.get("messages") or []
        if not messages or messages[-1].get("role") != "user" or isinstance(messages[-1].get("content"), str):
            return None
        results = {b["tool_use_id"]: b for b in messages[-1]["content"] if b.get("type") == "tool_result"}
        if not results:
            return None
        with self.lock:
            found = next((s for s in self.sessions.values() if any(b["id"] in results for b in s.asked)), None)
        if not found:
            return False
        with found.condition:
            for tool_id, block in results.items():
                found.results[tool_id] = {"content": self.text_of(block.get("content")), "is_error": bool(block.get("is_error"))}
                if self.show:
                    self.log("--- result for %s\n%s" % (tool_id, found.results[tool_id]["content"][:2000]))
            found.touched = time.time()
            found.condition.notify_all()
        return found

    def drop(self, session):
        with self.lock:
            self.sessions.pop(session.id, None)
        session.close()

    def reap(self):
        while True:
            time.sleep(15)
            with self.lock:
                old = [s for s in self.sessions.values() if time.time() - s.touched > IDLE_LIMIT]
            for session in old:
                self.drop(session)


def handler_for(bridge):
    class Handler(BaseHTTPRequestHandler):
        def log_message(self, *args):
            pass

        def allowed(self):
            # Only a program on this Mac: a web page would send an Origin header, or reach the port under another name.
            host = (self.headers.get("host") or "").split(":")[0]
            if self.headers.get("origin") or host not in ("127.0.0.1", "localhost"):
                self.send_json(403, {"error": {"type": "permission_error", "message": "local programs only"}})
                return False
            return True

        def send_json(self, status, body):
            data = json.dumps(body).encode()
            self.send_response(status)
            self.send_header("content-type", "application/json")
            self.send_header("content-length", str(len(data)))
            self.end_headers()
            self.wfile.write(data)

        def body(self):
            return json.loads(self.rfile.read(int(self.headers.get("content-length") or 0)) or b"{}")

        def mcp_session(self):
            parts = self.path.split("/")
            if len(parts) == 4 and parts[1] == "_mcp":
                return bridge.sessions.get(parts[2]), parts[3]
            return None, None

        def do_GET(self):
            if not self.allowed():
                return
            session, what = self.mcp_session()
            if session and what == "tools":
                return self.send_json(200, {"tools": session.tools})
            if self.path.startswith("/v1/models"):
                return self.send_json(200, {"data": [{"id": m, "type": "model"} for m in MODELS]})
            self.send_json(404, {"error": {"message": "not found"}})

        def do_POST(self):
            if not self.allowed():
                return
            session, what = self.mcp_session()
            if session and what == "call":
                call = self.body()
                return self.send_json(200, session.wait_for_result(call.get("name"), call.get("arguments") or {}))
            if not self.path.startswith("/v1/messages"):
                return self.send_json(404, {"error": {"message": "not found"}})
            self.messages(self.body())

        def messages(self, body):
            session = bridge.resume(body)
            if session is False:
                return self.send_json(400, {"error": {"message": "That tool call is no longer waiting. Ask again."}})
            continuing = session is not None
            if session is None:
                session = bridge.start(body)
            stream, started, content, usage, stop, called = bool(body.get("stream")), False, [], {}, None, []
            began, keep = time.time(), False
            try:
                while True:
                    try:
                        event = session.events.get(timeout=IDLE_LIMIT)
                    except queue.Empty:
                        raise RuntimeError("claude gave no answer in time")
                    session.touched = time.time()
                    if event["type"] == "stream_event":
                        data = event["event"]
                        kind = data.get("type")
                        if kind == "content_block_start":
                            block = dict(data["content_block"])
                            if block.get("type") == "tool_use":
                                block["name"] = block["name"][len(MCP_PREFIX):] if block["name"].startswith(MCP_PREFIX) else block["name"]
                                block["_json"] = ""
                                data = dict(data, content_block={k: v for k, v in block.items() if k != "_json"})
                            content.append(block)
                        elif kind == "content_block_delta":
                            delta, block = data["delta"], content[-1]
                            if delta["type"] == "text_delta":
                                block["text"] = block.get("text", "") + delta["text"]
                            elif delta["type"] == "input_json_delta":
                                block["_json"] += delta.get("partial_json", "")
                        elif kind == "message_delta":
                            stop = data["delta"].get("stop_reason")
                            usage.update(data.get("usage") or {})
                        if kind == "message_stop" and stop == "tool_use":
                            asked = []
                            for block in content:
                                if block.get("type") == "tool_use":
                                    block["input"] = json.loads(block.pop("_json") or "{}")
                                    asked.append({"id": block["id"], "name": block["name"], "input": block["input"], "taken": False})
                                    called.append("%s%s" % (block["name"], json.dumps(block["input"], ensure_ascii=False)))
                            with session.condition:
                                session.asked = asked
                                session.condition.notify_all()
                            keep = True
                        if stream:
                            if not started:
                                self.send_response(200)
                                self.send_header("content-type", "text/event-stream")
                                self.send_header("connection", "close")
                                self.end_headers()
                                started = True
                            self.wfile.write(("event: %s\ndata: %s\n\n" % (kind, json.dumps(data))).encode())
                            self.wfile.flush()
                        if keep:
                            break
                    elif event["type"] == "result":
                        usage.update({k: v for k, v in (event.get("usage") or {}).items() if k.endswith("_tokens")})
                        if event.get("is_error"):
                            raise RuntimeError(str(event.get("result") or event.get("subtype")))
                        break
                    elif event["type"] == "_end":
                        if not content:
                            raise RuntimeError(event.get("error") or "claude ended with code %s" % event.get("code"))
                        break
                if not stream:
                    clean = [{k: v for k, v in b.items() if k != "_json"} for b in content]
                    self.send_json(200, {"id": "msg_" + session.id, "type": "message", "role": "assistant", "model": body.get("model"),
                                         "content": clean, "stop_reason": stop or "end_turn", "usage": usage})
                reply = "".join(b.get("text", "") for b in content if b.get("type") == "text")
                bridge.log("%s %s %.1fs in=%s cached=%s out=%s stop=%s%s" % (
                    "continue" if continuing else "ask", body.get("model"), time.time() - began, usage.get("input_tokens"),
                    usage.get("cache_read_input_tokens"), usage.get("output_tokens"), stop,
                    " tools: " + "; ".join(called) if called else ""))
                if bridge.show and reply:
                    bridge.log("--- reply\n" + reply)
            except (BrokenPipeError, ConnectionResetError):
                keep = False
                bridge.log("the app closed the connection")
            except Exception as error:
                keep = False
                bridge.log("failed: %s" % error)
                if not started:
                    self.send_json(500, {"type": "error", "error": {"type": "api_error", "message": "bridge: %s" % error}})
            finally:
                if not keep:
                    bridge.drop(session)

    return Handler


def main():
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    parser.add_argument("--port", type=int, default=8787)
    parser.add_argument("--show", action="store_true", help="also print what is sent and what comes back")
    parser.add_argument("--mcp", metavar="URL", help=argparse.SUPPRESS)
    args = parser.parse_args()
    if args.mcp:
        return run_mcp(args.mcp)
    bridge = Bridge(args.port, args.show)
    server = ThreadingHTTPServer(("127.0.0.1", args.port), handler_for(bridge))
    threading.Thread(target=bridge.reap, daemon=True).start()
    bridge.log("listening on http://127.0.0.1:%d (this Mac only)" % args.port)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        for session in list(bridge.sessions.values()):
            bridge.drop(session)


if __name__ == "__main__":
    main()
