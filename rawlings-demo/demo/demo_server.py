from http.server import HTTPServer, BaseHTTPRequestHandler
import os

OUTBOUND_DIR = os.path.expanduser("~/Desktop/sftp-demo/outbound")


class FileReceiver(BaseHTTPRequestHandler):
    def do_POST(self):
        length = int(self.headers.get('Content-Length', 0))
        body = self.rfile.read(length).decode('utf-8')
        filename = self.headers.get('X-Filename', 'response.csv')
        os.makedirs(OUTBOUND_DIR, exist_ok=True)
        filepath = os.path.join(OUTBOUND_DIR, filename)
        with open(filepath, 'w') as f:
            f.write(body)
        print(f"Written: {filename}")
        self.send_response(200)
        self.end_headers()
        self.wfile.write(b'OK')

    def log_message(self, format, *args):
        pass  # suppress per-request console noise


if __name__ == '__main__':
    print(f"Listening on :8765 -> {OUTBOUND_DIR}")
    HTTPServer(('0.0.0.0', 8765), FileReceiver).serve_forever()
