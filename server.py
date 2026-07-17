"""
Minimal HTTP server that exposes GET /health on PORT (default 6713).
This is the CodeValid-required health seam; it does not alter any agent logic.
"""
import os
import json
from http.server import BaseHTTPRequestHandler, HTTPServer


class HealthHandler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == "/health":
            body = json.dumps({"status": "ok"}).encode()
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)
        else:
            self.send_response(404)
            self.end_headers()

    def log_message(self, fmt, *args):  # silence access log noise
        pass


def main():
    port = int(os.environ.get("PORT", 6713))
    server = HTTPServer(("0.0.0.0", port), HealthHandler)
    print(f"Listening on 0.0.0.0:{port}", flush=True)
    server.serve_forever()


if __name__ == "__main__":
    main()
