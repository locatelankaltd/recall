"""AI contract checks use in-memory mock HTTP responses only; never paid API calls."""
import copy
from http.client import IncompleteRead
import io
import json
import socket
import unittest
from unittest.mock import Mock, patch
from urllib.error import HTTPError, URLError

from ai_analysis import AnalysisProblem, DEFAULT_MODEL, ENDPOINT, NoRedirect, TIMEOUT_SECONDS, analyze


ENV = {"RECALL_AI_ENABLED": "1", "OPENAI_API_KEY": "test-fake-key-never-sent-to-a-network"}


def body():
    return {"consent": True, "source_text": "Please change the total fee to EUR 850. The date is not decided.",
        "current_items": [{"id": "fee", "label": "Total fee", "value": "EUR 600"},
                          {"id": "date", "label": "Delivery date", "value": "30 October 2026"}]}


def suggestion(**changes):
    result = {"item_id": "fee", "proposed_value": "EUR 850",
        "source_quote": "Please change the total fee to EUR 850.", "intent": "request",
        "needs_clarification": False, "question": None}
    result.update(changes)
    return result


def response(data=None, *, raw=None, status="completed", content=None):
    if raw is not None:
        return io.BytesIO(raw)
    if content is None:
        content = [{"type": "output_text", "text": json.dumps(data or {"suggestions": [suggestion()]})}]
    return io.BytesIO(json.dumps({"status": status, "output": [{"type": "message", "content": content}]}).encode())


class AnalysisTests(unittest.TestCase):
    def test_explicit_true_consent_is_required_before_any_network(self):
        for consent in [None, False, "true", 1]:
            payload = body()
            payload["consent"] = consent
            network = Mock()
            with self.assertRaises(AnalysisProblem) as problem:
                analyze(payload, environ=ENV, transport=network)
            self.assertEqual(problem.exception.status, 400)
            network.assert_not_called()

    def test_disabled_or_missing_key_fails_without_network(self):
        for env in [{}, {"OPENAI_API_KEY": ENV["OPENAI_API_KEY"]}, {"RECALL_AI_ENABLED": "1"}]:
            network = Mock()
            with self.assertRaises(AnalysisProblem) as problem:
                analyze(body(), environ=env, transport=network)
            self.assertEqual(problem.exception.status, 503)
            network.assert_not_called()
            self.assertNotIn(ENV["OPENAI_API_KEY"], problem.exception.message)

    def test_input_size_schema_and_selection_bounds_precede_network(self):
        payloads = []
        for change in [{"source_text": "x" * 12001}, {"source_text": ""}, {"source_text": "\x00text"},
                       {"source_text": "😀" * 9000}, {"extra": "not allowed"}, {"current_items": []}]:
            payload = body()
            payload.update(change)
            payloads.append(payload)
        payload = body()
        payload["current_items"].append(copy.deepcopy(payload["current_items"][0]))
        payloads.append(payload)
        payload = body()
        payload["current_items"][0]["value"] = 850
        payloads.append(payload)
        for payload in payloads:
            network = Mock()
            with self.assertRaises(AnalysisProblem) as problem:
                analyze(payload, environ=ENV, transport=network)
            self.assertIn(problem.exception.status, {400, 413})
            network.assert_not_called()

    def test_response_request_is_bounded_private_and_strict(self):
        network = Mock(return_value=response())
        result = analyze(body(), environ=ENV, transport=network)
        req = network.call_args.args[0]
        payload = json.loads(req.data)
        self.assertEqual(req.full_url, ENDPOINT)
        self.assertEqual(req.method, "POST")
        self.assertEqual(network.call_args.kwargs["timeout"], TIMEOUT_SECONDS)
        self.assertFalse(payload["store"])
        self.assertEqual(payload["model"], DEFAULT_MODEL)
        self.assertLessEqual(payload["max_output_tokens"], 4096)
        self.assertTrue(payload["text"]["format"]["strict"])
        self.assertFalse(payload["text"]["format"]["schema"]["additionalProperties"])
        self.assertNotIn("tools", payload)
        self.assertNotIn(ENV["OPENAI_API_KEY"], req.data.decode())
        self.assertIn("source_text", payload["input"][0]["content"][0]["text"])
        self.assertEqual(result["status"], "review_required")
        self.assertEqual(result["suggestions"][0]["proposed_value"], "EUR 850")
        self.assertEqual(len(result["source_sha256"]), 64)
        self.assertNotIn("source_text", result)
        self.assertEqual(result["suggestions"][1]["item_id"], "date")
        self.assertIsNone(result["suggestions"][1]["proposed_value"])
        self.assertIsNone(result["suggestions"][1]["source_quote"])
        self.assertTrue(result["suggestions"][1]["needs_clarification"])

    def test_source_quote_must_be_exact_and_value_must_be_inside_quote(self):
        for row in [suggestion(source_quote="The agreed fee is EUR 850."),
                    suggestion(proposed_value="EUR 1450"), suggestion(source_quote=None),
                    suggestion(proposed_value="€850")]:
            result = analyze(body(), environ=ENV, transport=Mock(return_value=response({"suggestions": [row]})))
            output = result["suggestions"][0]
            self.assertIsNone(output["proposed_value"])
            self.assertTrue(output["needs_clarification"])
            self.assertTrue(result["warnings"])
        result = analyze(body(), environ=ENV, transport=Mock(return_value=response({"suggestions": [
            suggestion(source_quote="The agreed fee is EUR 850.")]})))
        self.assertIsNone(result["suggestions"][0]["source_quote"])

    def test_uncertain_withdrawn_or_questioned_values_remain_null(self):
        rows = [suggestion(intent=intent) for intent in ["tentative", "withdrawal", "unclear"]]
        rows += [suggestion(needs_clarification=True), suggestion(question="Does this include the additional video?"),
                 suggestion(intent="no_change", needs_clarification=True)]
        for row in rows:
            result = analyze(body(), environ=ENV, transport=Mock(return_value=response({"suggestions": [row]})))
            self.assertIsNone(result["suggestions"][0]["proposed_value"])
            self.assertTrue(result["suggestions"][0]["needs_clarification"])
            self.assertIsNotNone(result["suggestions"][0]["question"])

    def test_unknown_duplicate_or_malformed_output_is_rejected(self):
        invalid = [{"suggestions": [suggestion(item_id="unselected")]},
                   {"suggestions": [suggestion(), suggestion()]}, {"suggestions": "not an array"},
                   {"suggestions": [suggestion(verified=True)]}, {"suggestions": [suggestion(intent="agreed")]},
                   {"suggestions": [suggestion(needs_clarification="false")]},
                   {"suggestions": [suggestion(question="x" * 301)]}, {"suggestions": [], "publish": True}]
        for data in invalid:
            with self.assertRaises(AnalysisProblem) as problem:
                analyze(body(), environ=ENV, transport=Mock(return_value=response(data)))
            self.assertEqual(problem.exception.status, 502)

    def test_incomplete_refused_invalid_or_oversized_provider_output(self):
        fixtures = [response(status="incomplete"), response(raw=b"not json"), response(raw=b"x" * 131073),
            response(content=[{"type": "refusal", "refusal": "Provider private message"}]),
            response(content=[{"type": "output_text", "text": '{"suggestions": [], "suggestions": []}'}])]
        for fixture in fixtures:
            with self.assertRaises(AnalysisProblem) as problem:
                analyze(body(), environ=ENV, transport=Mock(return_value=fixture))
            self.assertIn(problem.exception.status, {422, 502})
            self.assertNotIn("Provider private message", problem.exception.message)

    def test_network_errors_do_not_expose_secrets_or_retry(self):
        for failure, expected in [(socket.timeout(), 504), (URLError(socket.timeout()), 504),
                (URLError("private transport detail"), 502),
                (IncompleteRead(b"private partial body"), 502),
                (HTTPError(ENDPOINT, 401, "private error", {}, io.BytesIO(b"private body")), 503),
                (HTTPError(ENDPOINT, 429, "private error", {}, io.BytesIO(b"private body")), 503),
                (HTTPError(ENDPOINT, 400, "private error", {}, io.BytesIO(b"private body")), 503),
                (HTTPError(ENDPOINT, 500, "private error", {}, io.BytesIO(b"private body")), 502)]:
            network = Mock(side_effect=failure)
            with self.assertRaises(AnalysisProblem) as problem:
                analyze(body(), environ=ENV, transport=network)
            self.assertEqual(problem.exception.status, expected)
            self.assertNotIn("private", problem.exception.message)
            self.assertNotIn(ENV["OPENAI_API_KEY"], problem.exception.message)
            self.assertEqual(network.call_count, 1)

    def test_model_is_configurable_but_endpoint_cannot_be_overridden(self):
        network = Mock(return_value=response())
        result = analyze(body(), environ={**ENV, "RECALL_AI_MODEL": "gpt-5.4-mini-2026-03-17"}, transport=network)
        self.assertEqual(result["model"], "gpt-5.4-mini-2026-03-17")
        self.assertEqual(network.call_args.args[0].full_url, ENDPOINT)
        with self.assertRaises(AnalysisProblem):
            analyze(body(), environ={**ENV, "RECALL_AI_MODEL": "https://evil.invalid"}, transport=network)
        self.assertEqual(network.call_count, 1)
        self.assertIsNone(NoRedirect().redirect_request(None, None, 302, "redirect", {}, "https://evil.invalid"))

    def test_relative_date_cannot_be_silently_converted_to_a_calendar_date(self):
        payload = body()
        payload["source_text"] = "Could we deliver next Friday?"
        row = suggestion(item_id="date", proposed_value="30 October 2026", source_quote="Could we deliver next Friday?")
        result = analyze(payload, environ=ENV, transport=Mock(return_value=response({"suggestions": [row]})))
        date = next(item for item in result["suggestions"] if item["item_id"] == "date")
        self.assertIsNone(date["proposed_value"])
        self.assertTrue(date["needs_clarification"])


if __name__ == "__main__":
    unittest.main()
