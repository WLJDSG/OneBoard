"""本地假上游验证代理的非流式、流式 Token 事件，不调用真实供应商。"""
import http.server
import json
import os
import queue
import subprocess
import threading
import time
import urllib.request
import uuid
from pathlib import Path


api_format = os.environ.get("ONEBOARD_TEST_FORMAT", "anthropic")


class Upstream(http.server.BaseHTTPRequestHandler):
    def log_message(self, *args):
        pass

    def do_POST(self):
        request = json.loads(self.rfile.read(int(self.headers['Content-Length'])))
        usage = {'input_tokens': 100, 'output_tokens': 20,
                 'cache_read_input_tokens': 50, 'cache_creation_input_tokens': 10}
        message = {'id': 'msg_' + uuid.uuid4().hex, 'type': 'message', 'role': 'assistant',
                   'model': 'test-model', 'content': [{'type': 'text', 'text': 'hello'}],
                   'stop_reason': 'end_turn', 'usage': usage}
        if api_format == 'openai_chat':
            deepseek_usage = {'prompt_tokens': 100, 'completion_tokens': 20, 'total_tokens': 120,
                              'prompt_cache_hit_tokens': 80, 'prompt_cache_miss_tokens': 20,
                              'prompt_tokens_details': {'cached_tokens': 80}}
            base = {'id': 'chatcmpl-' + uuid.uuid4().hex, 'model': 'test-model', 'created': 1800000000}
            if request.get('stream'):
                assert request.get('stream_options', {}).get('include_usage') is True
                chunks = [
                    {**base, 'object': 'chat.completion.chunk', 'choices': [{'index': 0, 'delta': {'role': 'assistant', 'content': 'hello'}, 'finish_reason': None}]},
                    {**base, 'object': 'chat.completion.chunk', 'choices': [{'index': 0, 'delta': {}, 'finish_reason': 'stop'}]},
                    {**base, 'object': 'chat.completion.chunk', 'choices': [], 'usage': deepseek_usage}]
                data = (''.join('data: ' + json.dumps(chunk) + '\n\n' for chunk in chunks) + 'data: [DONE]\n\n').encode()
                content_type = 'text/event-stream'
            else:
                data = json.dumps({**base, 'object': 'chat.completion', 'choices': [{'index': 0, 'message': {'role': 'assistant', 'content': 'hello'}, 'finish_reason': 'stop'}], 'usage': deepseek_usage}).encode()
                content_type = 'application/json'
        elif request.get('stream'):
            chunks = [
                ('message_start', {'type': 'message_start', 'message': {**message, 'content': [], 'usage': {**usage, 'output_tokens': 0}}}),
                ('content_block_start', {'type': 'content_block_start', 'index': 0, 'content_block': {'type': 'text', 'text': ''}}),
                ('content_block_delta', {'type': 'content_block_delta', 'index': 0, 'delta': {'type': 'text_delta', 'text': 'hello'}}),
                ('content_block_stop', {'type': 'content_block_stop', 'index': 0}),
                ('message_delta', {'type': 'message_delta', 'delta': {'stop_reason': 'end_turn'}, 'usage': {'output_tokens': 20}}),
                ('message_stop', {'type': 'message_stop'})]
            data = ''.join(f'event: {event}\ndata: {json.dumps(body)}\n\n' for event, body in chunks).encode()
            content_type = 'text/event-stream'
        else:
            data = json.dumps(message).encode()
            content_type = 'application/json'
        self.send_response(200)
        self.send_header('Content-Type', content_type)
        self.send_header('Content-Length', str(len(data)))
        self.end_headers()
        self.wfile.write(data)


server = http.server.ThreadingHTTPServer(('127.0.0.1', 0), Upstream)
threading.Thread(target=server.serve_forever, daemon=True).start()
root = Path(__file__).resolve().parents[2]
binary = os.environ.get('ONEBOARD_TEST_PROXY', str(root / 'ProxySidecar/target/debug/oneboard-ai-proxy'))
payload = {'listenPort': 0, 'enableLogging': True, 'providers': [{
    'appType': 'claude', 'current': True, 'provider': {
        'id': 'test-provider', 'name': 'Fixture',
        'settingsConfig': {'env': {'ANTHROPIC_BASE_URL': f'http://127.0.0.1:{server.server_port}',
                                  'ANTHROPIC_AUTH_TOKEN': 'fixture-key', 'ANTHROPIC_MODEL': 'test-model'}},
        'meta': {'apiFormat': api_format}, 'inFailoverQueue': False}}]}
process = subprocess.Popen([binary], stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True)
lines = queue.Queue()
threading.Thread(target=lambda: [lines.put(line) for line in process.stdout], daemon=True).start()
try:
    process.stdin.write(json.dumps(payload))
    process.stdin.close()
    ready = json.loads(lines.get(timeout=15))
    assert ready['status'] == 'ready', ready
    for stream in [False, True]:
        req = urllib.request.Request(f"http://127.0.0.1:{ready['port']}/v1/messages",
            data=json.dumps({'model': 'test-model', 'messages': [{'role': 'user', 'content': 'hello'}],
                             'max_tokens': 100, 'stream': stream}).encode(),
            headers={'Content-Type': 'application/json', 'Authorization': 'Bearer PROXY_MANAGED', 'anthropic-version': '2023-06-01'})
        with urllib.request.urlopen(req, timeout=20) as response:
            assert response.status == 200
            response.read()
    events = []
    deadline = time.monotonic() + 15
    while len(events) < 2 and time.monotonic() < deadline:
        try:
            event = json.loads(lines.get(timeout=15))
        except queue.Empty:
            break
        if event.get('status') == 'usage': events.append(event)
    assert len(events) == 2, events
    for event in events:
        assert event['providerID'] == 'test-provider', event
        assert (event['input'], event['output'], event['cacheRead'], event['cacheCreation']) == ((20, 20, 80, 0) if api_format == 'openai_chat' else (100, 20, 50, 10)), event
    assert events[0]['id'] != events[1]['id'], events
    print(api_format + ': PASS: non-streaming and SSE emit exact input/output/cache usage once per request')
finally:
    process.terminate()
    process.wait(timeout=15)
    server.shutdown()
