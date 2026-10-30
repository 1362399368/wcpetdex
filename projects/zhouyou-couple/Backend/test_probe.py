import asyncio
import unittest

from aiohttp.test_utils import TestServer

from probe import endpoints, probe
from server import STORE, create_app


class EndpointTests(unittest.TestCase):
    def test_requires_wss_and_exact_route_without_credentials(self):
        self.assertEqual(endpoints("wss://pet.example.com/v1/ws"), ("pet.example.com", 443, "https://pet.example.com/health"))
        for url in ("https://pet.example.com/v1/ws", "wss://user:secret@pet.example.com/v1/ws", "wss://pet.example.com/v1/ws?token=secret", "ws://pet.example.com/v1/ws", "wss://pet.example.com/other"):
            with self.assertRaises(ValueError):
                endpoints(url)
        with self.assertRaises(ValueError):
            endpoints("ws://192.168.1.1/v1/ws", True)


class ProbeTests(unittest.IsolatedAsyncioTestCase):
    async def test_ready_check_does_not_send_events_or_ack_queued_event(self):
        app = create_app("fake-admin-"+"a"*32)
        pair = app[STORE].create_pair()["devices"]
        store = app[STORE]
        import uuid
        sender, recipient = pair[1]["device_id"], pair[0]["device_id"]
        event_id = str(uuid.uuid4())
        store.accept(sender, recipient, event_id)
        server = TestServer(app)
        await server.start_server()
        try:
            url = str(server.make_url("/v1/ws")).replace("http:", "ws:")
            safe = await probe(url, allow_local_http=True)
            self.assertTrue(safe["ok"])
            self.assertEqual(safe["checks"][-1]["http_status"], 401)
            report = await probe(url, pair[0]["token"], True, websocket=True)
            self.assertTrue(report["ok"])
            self.assertEqual(store.status(sender, event_id)["acknowledged"], 0)
            self.assertEqual(store.db.execute("SELECT COUNT(*) FROM events").fetchone()[0], 1)
            denied = await probe(url, "incorrect", True, websocket=True)
            self.assertFalse(denied["ok"])
            self.assertEqual(denied["checks"][-1]["http_status"], 401)
        finally:
            await server.close()


if __name__ == "__main__":
    unittest.main()
