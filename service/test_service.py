"""Workflow, isolation and HTTP security tests for the local review service."""
import concurrent.futures
import http.client
import json
from pathlib import Path
import re
import tempfile
import threading
import unittest
from unittest.mock import patch
from urllib.parse import urlencode, urlparse

from app import Problem, Store, digest, make_server, now
from run import local_owner_token


OWNER_TOKEN = "test-owner-credential-is-at-least-32-characters"


class WorkflowTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.store = Store(Path(self.directory.name) / "state.sqlite3", OWNER_TOKEN)
        self.project = self.store.create_project({
            "name": "Studio North", "owner_id": "alex",
            "participants": [{"id": "alex", "name": "Alex"}, {"id": "marta", "name": "Marta"}],
            "items": [{"id": "videos", "label": "Videos", "value": "2 videos"},
                      {"id": "fee", "label": "Total fee", "value": "EUR 600"},
                      {"id": "secret", "label": "Private account note", "value": "NOT SHARED"}]})

    def tearDown(self):
        self.directory.cleanup()

    def proposal(self, value="3 videos"):
        return self.store.propose(self.project["id"], {"base_version": 1, "changes": [
            {"item_id": "videos", "value": value, "excerpt": "Could you add a video?", "original": "¿Podrías añadir un vídeo?", "language": "es"},
            {"item_id": "fee", "value": "EUR 850", "excerpt": "EUR 850 total"}]})

    def link(self, revision, items=None):
        body = {"participant_id": "marta"}
        if items is not None:
            body["item_ids"] = items
        result = self.store.create_link(revision["revision_id"], body)
        return result, urlparse(result["url"]).path.rsplit("/", 1)[1]

    def recipient(self, token, version, action="confirm", comment=""):
        page = self.store.review(token)
        return self.store.respond(raw_token=token, origin=self.store.origin,
                                  body={"version": version, "action": action, "comment": comment, "csrf": page["csrf"]})

    def owner(self, revision, action="confirm"):
        return self.store.respond(revision_id=revision["revision_id"], body={"version": revision["version"], "action": action})

    def current(self):
        project = self.store.project_view(self.project["id"])
        return next(r for r in project["revisions"] if r["id"] == project["current_revision"])

    def test_publish_only_after_every_participant_confirms_exact_revision(self):
        revision = self.proposal()
        _, token = self.link(revision)
        self.assertEqual(self.current()["version"], 1)
        self.owner(revision)
        self.assertEqual(self.current()["version"], 1)
        result = self.recipient(token, revision["version"])
        self.assertEqual(result["status"], "published")
        current = self.current()
        self.assertEqual(current["version"], revision["version"])
        self.assertEqual(current["plan"][0]["value"], "3 videos")
        self.assertEqual(self.store.project_view(self.project["id"])["revisions"][0]["plan"][0]["value"], "2 videos")
        reloaded = Store(self.store.path, OWNER_TOKEN)
        self.assertEqual(reloaded.project_view(self.project["id"])["current_revision"], current["id"])

    def test_partial_link_never_confirms_unseen_items(self):
        revision = self.proposal()
        _, first = self.link(revision, ["videos"])
        _, second = self.link(revision, ["fee"])
        view = self.store.review(first)
        self.assertEqual([c["item_id"] for c in view["changes"]], ["videos"])
        self.assertNotIn("NOT SHARED", json.dumps(view))
        self.assertNotIn("Total fee", json.dumps(view))
        self.owner(revision)
        self.assertEqual(self.recipient(first, revision["version"])["status"], "pending")
        self.assertEqual(self.current()["version"], 1)
        self.assertEqual(self.recipient(second, revision["version"])["status"], "published")

    def test_correction_and_decline_never_publish(self):
        for action, expected in [("correction", "correction_requested"), ("decline", "declined")]:
            revision = self.proposal()
            _, token = self.link(revision)
            self.owner(revision)
            self.assertEqual(self.recipient(token, revision["version"], action, "Please revisit the date.")["status"], expected)
            self.assertEqual(self.current()["version"], 1)
            with self.assertRaises(Problem) as error:
                self.store.create_link(revision["revision_id"], {"participant_id": "marta"})
            self.assertEqual(error.exception.status, 409)

    def test_parallel_proposal_becomes_stale_after_publish(self):
        first, second = self.proposal("3 videos"), self.proposal("4 videos")
        _, first_token = self.link(first)
        _, second_token = self.link(second)
        self.owner(first)
        self.owner(second)
        self.recipient(first_token, first["version"])
        self.assertEqual(self.store.review(second_token)["status"], "stale")
        with self.assertRaises(Problem) as error:
            self.recipient(second_token, second["version"])
        self.assertEqual(error.exception.status, 409)
        with self.assertRaises(Problem):
            self.proposal()
        self.assertEqual(self.current()["plan"][0]["value"], "3 videos")

    def test_no_read_receipt_counts_as_confirmation(self):
        revision = self.proposal()
        _, token = self.link(revision)
        for _ in range(3):
            self.store.review(token)
        self.owner(revision)
        self.assertEqual(self.current()["version"], 1)
        self.assertEqual(len(self.store.project_view(self.project["id"])["revisions"][-1]["responses"]), 1)

    def test_duplicate_retries_are_idempotent_even_after_publish(self):
        revision = self.proposal()
        _, token = self.link(revision)
        self.owner(revision)
        self.assertTrue(self.owner(revision)["duplicate"])
        self.recipient(token, revision["version"])
        self.assertTrue(self.recipient(token, revision["version"])["duplicate"])
        self.assertEqual(len(self.store.project_view(self.project["id"])["revisions"][-1]["responses"]), 2)
        with self.assertRaises(Problem):
            self.recipient(token, revision["version"], "decline")

    def test_wrong_version_csrf_and_origin_rejected(self):
        revision = self.proposal()
        _, token = self.link(revision)
        view = self.store.review(token)
        for origin, csrf, version, status in [
            ("https://evil.invalid", view["csrf"], revision["version"], 403),
            (self.store.origin, "incorrect", revision["version"], 403),
            (self.store.origin, view["csrf"], revision["version"]+1, 409)]:
            with self.assertRaises(Problem) as error:
                self.store.respond(raw_token=token, origin=origin, body={"action": "confirm", "version": version, "csrf": csrf})
            self.assertEqual(error.exception.status, status)
        self.assertEqual(self.current()["version"], 1)

    def test_expiry_revocation_and_only_hashes_persist(self):
        revision = self.proposal()
        link, token = self.link(revision)
        self.store.review(token)
        with self.store.db() as db:
            data = " ".join(str(tuple(row)) for table in ["projects", "revisions", "links", "csrf"] for row in db.execute("SELECT * FROM " + table))
        self.assertNotIn(token, data)
        self.assertNotIn(OWNER_TOKEN, data)
        self.store.revoke(link["link_id"])
        with self.assertRaises(Problem) as error:
            self.store.review(token)
        self.assertEqual(error.exception.status, 410)
        _, expired = self.link(revision)
        with self.store.db(write=True) as db:
            db.execute("UPDATE links SET expires=? WHERE token_hash=?", (now()-1, digest(expired)))
        with self.assertRaises(Problem) as error:
            self.store.review(expired)
        self.assertEqual(error.exception.status, 410)

    def test_owner_authentication_and_invalid_scopes(self):
        for header in [None, "Bearer wrong", "Basic abc"]:
            with self.assertRaises(Problem):
                self.store.authenticate(header)
        self.store.authenticate("Bearer " + OWNER_TOKEN)
        revision = self.proposal()
        for body in [{"participant_id": "alex"}, {"participant_id": "unknown"}, {"participant_id": "marta", "item_ids": ["secret"]}]:
            with self.assertRaises(Problem):
                self.store.create_link(revision["revision_id"], body)

    def test_concurrent_duplicate_confirmation_publishes_once(self):
        revision = self.proposal()
        _, token = self.link(revision)
        self.owner(revision)
        with concurrent.futures.ThreadPoolExecutor(max_workers=4) as pool:
            results = list(pool.map(lambda _: self.recipient(token, revision["version"]), range(4)))
        self.assertEqual(sum(not r["duplicate"] for r in results), 1)
        self.assertEqual(self.current()["version"], revision["version"])

    def test_every_participant_is_required_and_payload_cannot_impersonate(self):
        project = self.store.create_project({"name": "Three people", "owner_id": "owner",
            "participants": [{"id": "owner", "name": "Owner"}, {"id": "one", "name": "One"}, {"id": "two", "name": "Two"}],
            "items": [{"id": "date", "label": "Date", "value": "October"}]})
        revision = self.store.propose(project["id"], {"base_version": 1, "changes": [{"item_id": "date", "value": "November"}]})
        self.store.respond(revision_id=revision["revision_id"], body={"version": revision["version"], "action": "confirm", "participant_id": "two"})
        links = [self.store.create_link(revision["revision_id"], {"participant_id": who}) for who in ("one", "two")]
        tokens = [urlparse(link["url"]).path.rsplit("/", 1)[1] for link in links]
        self.assertEqual(self.recipient(tokens[0], revision["version"])["status"], "pending")
        self.assertEqual(self.recipient(tokens[1], revision["version"])["status"], "published")
        responses = self.store.project_view(project["id"])["revisions"][-1]["responses"]
        self.assertEqual({r["actor"] for r in responses}, {"owner", "one", "two"})

    def test_private_runner_credential_is_persistent_and_symlinks_rejected(self):
        directory = Path(self.directory.name) / "runner"
        first = local_owner_token(directory)
        self.assertGreaterEqual(len(first), 32)
        self.assertEqual(local_owner_token(directory), first)
        path = directory / "owner-token.txt"
        self.assertEqual(path.stat().st_mode & 0o777, 0o600)
        path.unlink()
        path.symlink_to(self.store.path)
        with self.assertRaises(OSError):
            local_owner_token(directory)


class HTTPTests(unittest.TestCase):
    proposal = WorkflowTests.proposal
    link = WorkflowTests.link
    current = WorkflowTests.current

    def setUp(self):
        WorkflowTests.setUp(self)
        self.server = make_server(self.store, port=0)
        self.thread = threading.Thread(target=self.server.serve_forever, daemon=True)
        self.thread.start()

    def tearDown(self):
        self.server.shutdown()
        self.server.server_close()
        self.thread.join()
        WorkflowTests.tearDown(self)

    def request(self, method, path, body=None, headers=None):
        connection = http.client.HTTPConnection("127.0.0.1", self.server.server_address[1], timeout=5)
        connection.request(method, path, body, headers or {})
        response = connection.getresponse()
        result = response.status, dict(response.getheaders()), response.read().decode()
        connection.close()
        return result

    def test_http_auth_browser_scoping_and_html_escaping(self):
        self.assertEqual(self.request("GET", "/api/projects")[0], 401)
        self.assertEqual(self.request("GET", "/api/projects", headers={"Authorization": "Bearer " + OWNER_TOKEN})[0], 200)
        revision = self.proposal('<script>alert("bad")</script>')
        _, token = self.link(revision, ["videos"])
        status, headers, body = self.request("GET", f"/review/{token}?lang=es")
        self.assertEqual(status, 200)
        self.assertIn("Revisa un cambio propuesto", body)
        self.assertIn("&lt;script&gt;", body)
        self.assertNotIn('<script>alert', body)
        self.assertNotIn("NOT SHARED", body)
        self.assertEqual(headers["Referrer-Policy"], "strict-origin")
        self.assertEqual(headers["Cache-Control"], "no-store")
        csrf = re.search(r'name="csrf" value="([^"]+)"', body).group(1)
        form = urlencode({"csrf": csrf, "version": revision["version"], "action": "confirm", "lang": "fr"})
        status, _, _ = self.request("POST", f"/review/{token}", form, {"Content-Type": "application/x-www-form-urlencoded"})
        self.assertEqual(status, 403)
        status, _, body = self.request("POST", f"/review/{token}", form, {"Content-Type": "application/x-www-form-urlencoded", "Origin": self.store.origin})
        self.assertEqual(status, 200)
        self.assertIn("Réponse enregistrée", body)
        self.assertEqual(self.current()["version"], 1)

    def test_http_cross_origin_and_json_contract(self):
        status, _, _ = self.request("GET", "/api/projects", headers={"Authorization": "Bearer " + OWNER_TOKEN, "Origin": "https://evil.invalid"})
        self.assertEqual(status, 403)
        status, _, _ = self.request("POST", "/api/projects", "{}", {"Authorization": "Bearer " + OWNER_TOKEN, "Content-Type": "text/plain"})
        self.assertEqual(status, 415)
        self.assertEqual(self.request("GET", "/health")[0], 200)

    def test_ambiguous_json_cannot_create_a_project(self):
        headers = {"Authorization": "Bearer " + OWNER_TOKEN, "Content-Type": "application/json"}
        for body in ['{"name":"first","name":"second"}', '{"value":NaN}', '{"nested":{"id":"one","id":"two"}}']:
            self.assertEqual(self.request("POST", "/api/projects", body, headers)[0], 400)
        self.assertEqual(len(self.store.list_projects()), 1)

    def test_receipt_survives_link_revocation_after_a_committed_response(self):
        revision = self.proposal()
        link, token = self.link(revision)
        page = self.store.review(token)
        form = urlencode({"csrf": page["csrf"], "version": revision["version"], "action": "confirm", "lang": "en"})
        original_respond = self.store.respond

        def revoke_after_commit(**kwargs):
            result = original_respond(**kwargs)
            self.store.revoke(link["link_id"])
            return result

        with patch.object(self.store, "respond", side_effect=revoke_after_commit):
            status, _, body = self.request("POST", f"/review/{token}", form,
                {"Content-Type": "application/x-www-form-urlencoded", "Origin": self.store.origin})
        self.assertEqual(status, 200)
        self.assertIn("<h1>Response recorded</h1>", body)
        self.assertIn("Selected changes confirmed", body)
        self.assertNotIn("No response was recorded", body)
        self.assertEqual(len(self.store.project_view(self.project["id"])["revisions"][-1]["responses"]), 1)
        self.assertEqual(self.request("GET", f"/review/{token}")[0], 410)

    def test_analysis_http_auth_consent_and_configuration_never_change_a_plan(self):
        headers = {"Authorization": "Bearer " + OWNER_TOKEN, "Content-Type": "application/json"}
        payload = {"consent": True, "source_text": "Please change to 3 videos.",
            "current_items": [{"id": "videos", "label": "Videos", "value": "2 videos"}]}
        with patch("ai_analysis._open") as network, patch.dict("os.environ", {}, clear=True):
            self.assertEqual(self.request("POST", "/api/analyze", json.dumps(payload), {"Content-Type": "application/json"})[0], 401)
            without_consent = {**payload, "consent": False}
            self.assertEqual(self.request("POST", "/api/analyze", json.dumps(without_consent), headers)[0], 400)
            self.assertEqual(self.request("POST", "/api/analyze", json.dumps(payload), headers)[0], 503)
            with patch.dict("os.environ", {"RECALL_AI_ENABLED": "1"}):
                self.assertEqual(self.request("POST", "/api/analyze", json.dumps(payload), headers)[0], 503)
            network.assert_not_called()
        with patch("app.analyze", return_value={"status": "review_required", "suggestions": []}) as analysis:
            status, _, result = self.request("POST", "/api/analyze", json.dumps(payload), headers)
            self.assertEqual(status, 200)
            self.assertEqual(json.loads(result)["status"], "review_required")
            analysis.assert_called_once()
        self.assertEqual(self.current()["version"], 1)
        self.assertEqual(len(self.store.project_view(self.project["id"])["revisions"]), 1)

    def test_old_published_link_and_duplicate_receipt_show_newer_current_plan(self):
        revision = self.proposal()
        _, token = self.link(revision)
        self.store.respond(revision_id=revision["revision_id"], body={"version": revision["version"], "action": "confirm"})
        page = self.store.review(token)
        self.store.respond(raw_token=token, origin=self.store.origin,
            body={"version": revision["version"], "action": "confirm", "csrf": page["csrf"]})
        newer = self.store.propose(self.project["id"], {"base_version": revision["version"],
            "changes": [{"item_id": "videos", "value": "4 videos"}]})
        self.store.respond(revision_id=newer["revision_id"], body={"version": newer["version"], "action": "confirm"})
        _, newer_token = self.link(newer)
        newer_page = self.store.review(newer_token)
        self.store.respond(raw_token=newer_token, origin=self.store.origin,
            body={"version": newer["version"], "action": "confirm", "csrf": newer_page["csrf"]})
        status, _, html = self.request("GET", f"/review/{token}")
        self.assertEqual(status, 200)
        self.assertIn("Previously published revision", html)
        csrf = re.search(r'name="csrf" value="([^"]+)"', html)
        self.assertIsNone(csrf)  # The historical page cannot submit a new response.
        page = self.store.review(token)
        form = urlencode({"csrf": page["csrf"], "version": revision["version"], "action": "confirm", "lang": "en"})
        status, _, html = self.request("POST", f"/review/{token}", form,
            {"Content-Type": "application/x-www-form-urlencoded", "Origin": self.store.origin})
        self.assertEqual(status, 200)
        self.assertIn("Previously published revision", html)
        self.assertIn("Current value (v3): <bdi>4 videos</bdi>", html)
        self.assertEqual(self.current()["version"], newer["version"])


if __name__ == "__main__":
    unittest.main()
