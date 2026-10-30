"""Loopback stand-in for an OpenAI-compatible chat service (SiliconFlow shape).

Serves /v1/chat/completions and /v1/models, records each request to a JSON
lines file, and never contacts the network. Used by run-chat-advisor-preview.sh.
"""
import json
import sys
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

KEY = "test-key-123"
ADVICE = {
    "summary": "这句更像随口一说，不用过度解读，顺着接一句就好。",
    "strategy": "承接",
    "intents": [{"label": "随口闲聊", "percent": 60}, {"label": "求回应求陪伴", "percent": 25},
                {"label": "想确认你在不在乎", "percent": 15}],
    "risk_level": 2, "risk_label": "轻微", "reply_timing": "立刻回",
    "actions": ["轻松带过不深聊"],
    "replies": ["嗯嗯，我在呢", "怎么啦", "刚看到，你说"],
}


class Handler(BaseHTTPRequestHandler):
    def log_message(self, *args):
        pass

    def record(self, body):
        with open(self.server.log_path, "a", encoding="utf-8") as log:
            log.write(json.dumps({"path": self.path, "method": self.command,
                                  "authorization": self.headers.get("Authorization"), "body": body},
                                 ensure_ascii=False) + "\n")

    def reply(self, status, payload):
        data = json.dumps(payload, ensure_ascii=False).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def authorized(self):
        return self.headers.get("Authorization") == "Bearer " + KEY

    def do_GET(self):
        self.record(None)
        if not self.path.startswith("/v1/models"):
            return self.reply(404, {"message": "not found"})
        if not self.authorized():
            return self.reply(401, {"message": "Invalid token"})
        self.reply(200, {"object": "list", "data": [{"id": "deepseek-ai/DeepSeek-V3"}, {"id": "Qwen/Qwen3-8B"}]})

    def do_POST(self):
        length = int(self.headers.get("Content-Length") or 0)
        body = json.loads(self.rfile.read(length) or b"{}")
        self.record(body)
        if self.path != "/v1/chat/completions":
            return self.reply(404, {"message": "not found"})
        if not self.authorized():
            return self.reply(401, {"message": "Invalid token"})
        if body.get("model") == "reject-json-mode" and "response_format" in body:
            return self.reply(400, {"message": "response_format is not supported"})
        content = "<think>先判断语气</think>\n```json\n" + json.dumps(ADVICE, ensure_ascii=False) + "\n```"
        self.reply(200, {"choices": [{"index": 0, "message": {"role": "assistant", "content": content}}]})


if __name__ == "__main__":
    server = ThreadingHTTPServer(("127.0.0.1", int(sys.argv[1])), Handler)
    server.log_path = sys.argv[2]
    server.serve_forever()
