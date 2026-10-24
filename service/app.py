#!/usr/bin/env python3
"""Local development recipient review service. Python standard library only."""
from __future__ import annotations

import argparse
import hashlib
import hmac
import html
import json
import os
from pathlib import Path
import re
import secrets
import sqlite3
import time
from contextlib import contextmanager
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs, urlparse
import uuid

from ai_analysis import AnalysisProblem, analyze


class Problem(Exception):
    def __init__(self, status: int, message: str):
        self.status, self.message = status, message


def digest(value: str) -> str:
    return hashlib.sha256(value.encode("utf-8")).hexdigest()


def now() -> int:
    return int(time.time())


def text(value, label: str, limit: int = 200, empty: bool = False) -> str:
    if not isinstance(value, str) or len(value) > limit or (not empty and not value.strip()):
        raise Problem(400, f"Invalid {label}.")
    return value.strip()


def integer(value, label: str, low: int = 1, high: int = 1_000_000) -> int:
    if isinstance(value, bool) or not isinstance(value, int) or not low <= value <= high:
        raise Problem(400, f"Invalid {label}.")
    return value


def identifier(value, label="identifier"):
    value = text(value, label, 64)
    if not re.fullmatch(r"[A-Za-z0-9_-]+", value):
        raise Problem(400, f"Invalid {label}.")
    return value


def unique_json_object(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            raise ValueError("Duplicate JSON property")
        result[key] = value
    return result


def reject_json_constant(_):
    raise ValueError("Non-finite JSON number")


class Store:
    def __init__(self, path, owner_token: str, origin="http://127.0.0.1:8765"):
        if not isinstance(owner_token, str) or len(owner_token) < 32:
            raise ValueError("A service owner token of at least 32 characters is required.")
        self.path = Path(path)
        self.owner_hash = digest(owner_token)
        self.origin = origin.rstrip("/")
        self.path.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
        self.path.touch(mode=0o600, exist_ok=True)
        self.path.chmod(0o600)
        with self.db() as db:
            db.executescript("""
                PRAGMA journal_mode=WAL;
                CREATE TABLE IF NOT EXISTS projects (
                  id TEXT PRIMARY KEY, name TEXT NOT NULL, owner_id TEXT NOT NULL,
                  participants TEXT NOT NULL, current_revision TEXT, created INTEGER NOT NULL
                );
                CREATE TABLE IF NOT EXISTS revisions (
                  id TEXT PRIMARY KEY, project_id TEXT NOT NULL REFERENCES projects(id),
                  version INTEGER NOT NULL, base_version INTEGER NOT NULL,
                  status TEXT NOT NULL, plan TEXT NOT NULL, changes TEXT NOT NULL,
                  created INTEGER NOT NULL, UNIQUE(project_id, version)
                );
                CREATE TRIGGER IF NOT EXISTS immutable_revision_payload
                  BEFORE UPDATE OF plan,changes,version,base_version,project_id ON revisions
                  BEGIN SELECT RAISE(ABORT, 'Revision payloads are immutable'); END;
                CREATE TABLE IF NOT EXISTS links (
                  id TEXT PRIMARY KEY, token_hash TEXT UNIQUE NOT NULL,
                  revision_id TEXT NOT NULL REFERENCES revisions(id), participant_id TEXT NOT NULL,
                  item_ids TEXT NOT NULL, expires INTEGER NOT NULL, revoked INTEGER NOT NULL DEFAULT 0,
                  created INTEGER NOT NULL
                );
                CREATE TABLE IF NOT EXISTS csrf (
                  nonce_hash TEXT PRIMARY KEY, token_hash TEXT NOT NULL,
                  expires INTEGER NOT NULL
                );
                CREATE TABLE IF NOT EXISTS response_events (
                  id TEXT PRIMARY KEY, revision_id TEXT NOT NULL REFERENCES revisions(id),
                  actor TEXT NOT NULL, link_id TEXT UNIQUE,
                  action TEXT NOT NULL, item_ids TEXT NOT NULL, comment TEXT NOT NULL,
                  created INTEGER NOT NULL, payload_hash TEXT NOT NULL
                );
                CREATE UNIQUE INDEX IF NOT EXISTS owner_response_once
                  ON response_events(revision_id, actor) WHERE link_id IS NULL;
                CREATE TABLE IF NOT EXISTS item_confirmations (
                  revision_id TEXT NOT NULL REFERENCES revisions(id), participant_id TEXT NOT NULL,
                  item_id TEXT NOT NULL, event_id TEXT NOT NULL REFERENCES response_events(id),
                  PRIMARY KEY(revision_id, participant_id, item_id)
                );
            """)
        self.path.chmod(0o600)

    @contextmanager
    def db(self, write=False):
        connection = sqlite3.connect(self.path, timeout=10)
        connection.row_factory = sqlite3.Row
        connection.execute("PRAGMA foreign_keys=ON")
        try:
            if write:
                connection.execute("BEGIN IMMEDIATE")
            yield connection
            connection.commit()
        except Exception:
            connection.rollback()
            raise
        finally:
            connection.close()

    def authenticate(self, header):
        if not isinstance(header, str) or not header.startswith("Bearer "):
            raise Problem(401, "Owner authentication required.")
        if not hmac.compare_digest(digest(header[7:]), self.owner_hash):
            raise Problem(401, "Owner authentication required.")

    @staticmethod
    def project(db, project_id):
        row = db.execute("SELECT * FROM projects WHERE id=?", (project_id,)).fetchone()
        if not row:
            raise Problem(404, "Project not found.")
        return row

    @staticmethod
    def revision(db, revision_id):
        row = db.execute("SELECT * FROM revisions WHERE id=?", (revision_id,)).fetchone()
        if not row:
            raise Problem(404, "Revision not found.")
        return row

    def project_view(self, project_id):
        with self.db() as db:
            project = dict(self.project(db, project_id))
            project["participants"] = json.loads(project["participants"])
            project["revisions"] = []
            for row in db.execute("SELECT * FROM revisions WHERE project_id=? ORDER BY version", (project_id,)):
                revision = dict(row)
                revision["plan"], revision["changes"] = json.loads(row["plan"]), json.loads(row["changes"])
                revision["responses"] = [dict(r) for r in db.execute(
                    "SELECT actor, action, item_ids, comment, created, link_id FROM response_events WHERE revision_id=? ORDER BY created,id", (row["id"],))]
                for response in revision["responses"]:
                    response["item_ids"] = json.loads(response["item_ids"])
                    response["identity"] = "link-holder response; identity not verified" if response.pop("link_id") else "authenticated service owner"
                revision["links"] = [dict(r) for r in db.execute(
                    "SELECT id,participant_id,item_ids,expires,revoked FROM links WHERE revision_id=?", (row["id"],))]
                for link in revision["links"]:
                    link["item_ids"] = json.loads(link["item_ids"])
                project["revisions"].append(revision)
            return project

    def list_projects(self):
        with self.db() as db:
            return [dict(row) for row in db.execute("SELECT id,name,current_revision,created FROM projects ORDER BY created,id")]

    def create_project(self, body):
        name = text(body.get("name"), "project name")
        owner_id = identifier(body.get("owner_id"), "owner participant")
        participants = body.get("participants")
        items = body.get("items")
        if not isinstance(participants, list) or not 2 <= len(participants) <= 20 or not all(isinstance(p, dict) for p in participants):
            raise Problem(400, "Provide two to twenty participants including the owner.")
        participants = [{"id": identifier(p.get("id"), "participant id"), "name": text(p.get("name"), "participant name")} for p in participants if isinstance(p, dict)]
        ids = [p["id"] for p in participants]
        if len(set(ids)) != len(ids) or owner_id not in ids or len(ids) < 2:
            raise Problem(400, "Participant IDs must be unique and include the owner.")
        if not isinstance(items, list) or not 1 <= len(items) <= 100:
            raise Problem(400, "Provide one to one hundred plan items.")
        plan = []
        for item in items:
            if not isinstance(item, dict):
                raise Problem(400, "Invalid plan item.")
            plan.append({"id": identifier(item.get("id"), "item id"), "label": text(item.get("label"), "item label"), "value": text(item.get("value"), "item value", 2000)})
        if len({i["id"] for i in plan}) != len(plan):
            raise Problem(400, "Plan item IDs must be unique.")
        project_id, revision_id = uuid.uuid4().hex, uuid.uuid4().hex
        with self.db(write=True) as db:
            db.execute("INSERT INTO projects VALUES (?,?,?,?,?,?)", (project_id, name, owner_id, json.dumps(participants), revision_id, now()))
            db.execute("INSERT INTO revisions VALUES (?,?,?,?,?,?,?,?)", (revision_id, project_id, 1, 0, "published", json.dumps(plan), "[]", now()))
        return self.project_view(project_id)

    def propose(self, project_id, body):
        base_version = integer(body.get("base_version"), "base version")
        changes = body.get("changes")
        if not isinstance(changes, list) or not 1 <= len(changes) <= 100 or not all(isinstance(c, dict) for c in changes):
            raise Problem(400, "Provide one to one hundred changes.")
        changes = [{"item_id": identifier(c.get("item_id"), "item id"),
                    "value": text(c.get("value"), "new value", 2000),
                    "excerpt": text(c.get("excerpt", ""), "evidence excerpt", 1500, True),
                    "original": text(c.get("original", ""), "original wording", 1500, True),
                    "language": text(c.get("language", "und"), "source language", 40)}
                   for c in changes if isinstance(c, dict)]
        if not changes or len({c["item_id"] for c in changes}) != len(changes):
            raise Problem(400, "Changed item IDs must be unique.")
        revision_id = uuid.uuid4().hex
        with self.db(write=True) as db:
            project = self.project(db, project_id)
            current = self.revision(db, project["current_revision"])
            if current["version"] != base_version:
                raise Problem(409, "The base plan changed. Review the current plan and propose a new revision.")
            plan = json.loads(current["plan"])
            current_items = {item["id"]: item for item in plan}
            if not {c["item_id"] for c in changes} <= current_items.keys():
                raise Problem(400, "Only existing plan items may be changed in this local service.")
            for change in changes:
                if current_items[change["item_id"]]["value"] == change["value"]:
                    raise Problem(400, "A proposed change must change its value.")
                current_items[change["item_id"]]["value"] = change["value"]
            version = db.execute("SELECT MAX(version)+1 FROM revisions WHERE project_id=?", (project_id,)).fetchone()[0]
            db.execute("INSERT INTO revisions VALUES (?,?,?,?,?,?,?,?)", (revision_id, project_id, version, base_version, "pending", json.dumps(plan), json.dumps(changes), now()))
        return {"revision_id": revision_id, "version": version, "base_version": base_version, "status": "pending"}

    def pending(self, db, revision):
        if revision["status"] != "pending":
            raise Problem(409, f"This revision is {revision['status']}; it cannot receive new responses.")
        project = self.project(db, revision["project_id"])
        current = self.revision(db, project["current_revision"])
        if current["version"] != revision["base_version"]:
            raise Problem(409, "This revision is stale. Review a new proposal based on the current plan.")
        return project

    def create_link(self, revision_id, body):
        participant_id = identifier(body.get("participant_id"), "participant id")
        ttl = integer(body.get("ttl_seconds", 86400), "expiry duration", 60, 604800)
        link_id, raw_token = uuid.uuid4().hex, secrets.token_urlsafe(32)
        with self.db(write=True) as db:
            revision = self.revision(db, revision_id)
            project = self.pending(db, revision)
            if participant_id == project["owner_id"] or participant_id not in {p["id"] for p in json.loads(project["participants"])}:
                raise Problem(400, "Choose a non-owner project participant.")
            all_ids = [c["item_id"] for c in json.loads(revision["changes"])]
            selected = body.get("item_ids", all_ids)
            if not isinstance(selected, list) or not selected or not all(isinstance(i, str) and i in all_ids for i in selected) or len(selected) != len(set(selected)):
                raise Problem(400, "Select unique changed item IDs for this review link.")
            expires = now() + ttl
            db.execute("INSERT INTO links VALUES (?,?,?,?,?,?,0,?)", (link_id, digest(raw_token), revision_id, participant_id, json.dumps(selected), expires, now()))
        return {"link_id": link_id, "url": f"{self.origin}/review/{raw_token}", "expires": expires,
                "identity": "link-holder response; identity not verified"}

    def revoke(self, link_id):
        with self.db(write=True) as db:
            result = db.execute("UPDATE links SET revoked=1 WHERE id=?", (link_id,))
            if not result.rowcount:
                raise Problem(404, "Review link not found.")
        return {"revoked": True}

    @staticmethod
    def active_link(db, raw_token):
        link = db.execute("SELECT * FROM links WHERE token_hash=?", (digest(raw_token),)).fetchone()
        if not link:
            raise Problem(404, "Review link unavailable.")
        if link["revoked"] or link["expires"] <= now():
            raise Problem(410, "This review link has expired or was revoked. Ask the sender for a new link.")
        return link

    def review(self, raw_token):
        with self.db(write=True) as db:
            link = self.active_link(db, raw_token)
            revision = self.revision(db, link["revision_id"])
            project = self.project(db, revision["project_id"])
            current = self.revision(db, project["current_revision"])
            base = db.execute("SELECT plan FROM revisions WHERE project_id=? AND version=?", (project["id"], revision["base_version"])).fetchone()
            selected = set(json.loads(link["item_ids"]))
            fields = {i["id"]: i for i in json.loads(base["plan"])}
            current_fields = {i["id"]: i for i in json.loads(current["plan"])}
            changes = [{**c, "label": fields[c["item_id"]]["label"], "previous": fields[c["item_id"]]["value"],
                        "current": current_fields[c["item_id"]]["value"]}
                       for c in json.loads(revision["changes"]) if c["item_id"] in selected]
            participant = next(p for p in json.loads(project["participants"]) if p["id"] == link["participant_id"])
            response = db.execute("SELECT action,comment FROM response_events WHERE link_id=?", (link["id"],)).fetchone()
            csrf = secrets.token_urlsafe(32)
            db.execute("DELETE FROM csrf WHERE expires<=?", (now(),))
            db.execute("INSERT INTO csrf VALUES (?,?,?)", (digest(csrf), link["token_hash"], now()+900))
            return {"project": project["name"], "participant": participant["name"], "version": revision["version"],
                    "base_version": revision["base_version"], "current_version": current["version"],
                    "status": revision["status"], "changes": changes, "csrf": csrf,
                    "response": dict(response) if response else None,
                    "can_respond": revision["status"] == "pending" and revision["base_version"] == current["version"] and not response}

    def respond(self, revision_id=None, body=None, raw_token=None, origin=None):
        body = body or {}
        action = text(body.get("action"), "response action", 20)
        if action not in {"confirm", "correction", "decline"}:
            raise Problem(400, "Choose confirm, correction or decline.")
        comment = text(body.get("comment", ""), "comment", 2000, True)
        version = integer(body.get("version"), "reviewed version")
        with self.db(write=True) as db:
            link = None
            if raw_token:
                if origin != self.origin:
                    raise Problem(403, "Same-origin review submission required.")
                link = self.active_link(db, raw_token)
                csrf = body.get("csrf")
                if not isinstance(csrf, str) or not db.execute("SELECT 1 FROM csrf WHERE nonce_hash=? AND token_hash=? AND expires>?", (digest(csrf), link["token_hash"], now())).fetchone():
                    raise Problem(403, "Review session expired. Reopen the link and try again.")
                revision_id = link["revision_id"]
            revision = self.revision(db, revision_id)
            if revision["version"] != version:
                raise Problem(409, "Your answer does not match this review version.")
            project = self.project(db, revision["project_id"])
            actor = link["participant_id"] if link else project["owner_id"]
            selected = json.loads(link["item_ids"]) if link else [c["item_id"] for c in json.loads(revision["changes"])]
            payload_hash = digest(json.dumps({"action": action, "comment": comment, "version": version}, sort_keys=True))
            if link:
                existing = db.execute("SELECT payload_hash FROM response_events WHERE link_id=?", (link["id"],)).fetchone()
            else:
                existing = db.execute("SELECT payload_hash FROM response_events WHERE revision_id=? AND actor=? AND link_id IS NULL", (revision_id, actor)).fetchone()
            if existing:
                if existing["payload_hash"] != payload_hash:
                    raise Problem(409, "A response was already recorded. Ask for a new revision to change it.")
                return {"status": revision["status"], "version": version, "duplicate": True}
            self.pending(db, revision)
            event_id = uuid.uuid4().hex
            db.execute("INSERT INTO response_events VALUES (?,?,?,?,?,?,?,?,?)", (event_id, revision_id, actor, link["id"] if link else None, action, json.dumps(selected), comment, now(), payload_hash))
            status = "pending"
            if action in {"correction", "decline"}:
                status = "correction_requested" if action == "correction" else "declined"
                db.execute("UPDATE revisions SET status=? WHERE id=?", (status, revision_id))
            else:
                for item_id in selected:
                    db.execute("INSERT OR IGNORE INTO item_confirmations VALUES (?,?,?,?)", (revision_id, actor, item_id, event_id))
                expected = len(json.loads(project["participants"])) * len(json.loads(revision["changes"]))
                actual = db.execute("SELECT COUNT(*) FROM item_confirmations WHERE revision_id=?", (revision_id,)).fetchone()[0]
                if actual == expected:
                    # BEGIN IMMEDIATE serializes all responses and publication against the current base.
                    self.pending(db, revision)
                    db.execute("UPDATE revisions SET status='published' WHERE id=?", (revision_id,))
                    db.execute("UPDATE projects SET current_revision=? WHERE id=?", (revision_id, project["id"]))
                    db.execute("UPDATE revisions SET status='stale' WHERE project_id=? AND status='pending' AND id<>?", (project["id"], revision_id))
                    status = "published"
            return {"status": status, "version": version, "duplicate": False,
                    "identity": "link-holder response; identity not verified" if link else "authenticated service owner"}


COPY = {
    "en": {"review":"Review a proposed change", "current":"Current value", "previous":"Base plan value", "proposed":"Proposed value", "source":"Selected source excerpt", "original":"Original wording", "confirm":"Confirm these selected changes", "correction":"Request a correction", "decline":"Decline these changes", "comment":"Comment (optional)", "version":"Revision", "status":"Status", "identity":"Link-holder response; identity not verified", "scope":"Only the selected changes are shared here. Confirming them does not approve unseen items.", "wait":"The existing plan remains current until every required participant confirms every changed item in this exact revision.", "closed":"This proposal is closed or your response is already recorded. Ask the sender for a new proposal if something must change.", "local":"Local development preview · no email was sent · not an electronic signature service", "recorded":"Response recorded", "language":"Page language", "unchanged":"Values and original excerpts remain as supplied by the sender; switching page language does not translate or validate them."},
    "es": {"review":"Revisa un cambio propuesto", "current":"Valor actual", "previous":"Valor del plan base", "proposed":"Valor propuesto", "source":"Fragmento seleccionado", "original":"Texto original", "confirm":"Confirmar estos cambios seleccionados", "correction":"Solicitar una corrección", "decline":"Rechazar estos cambios", "comment":"Comentario (opcional)", "version":"Revisión", "status":"Estado", "identity":"Respuesta del titular del enlace; identidad no verificada", "scope":"Solo se comparten los cambios seleccionados. Confirmarlos no aprueba elementos que no has visto.", "wait":"El plan existente sigue vigente hasta que todas las personas requeridas confirmen cada cambio de esta revisión exacta.", "closed":"Esta propuesta está cerrada o tu respuesta ya está registrada. Solicita una nueva propuesta si hace falta cambiar algo.", "local":"Vista local de desarrollo · no se envió ningún correo · no es un servicio de firma electrónica", "recorded":"Respuesta registrada", "language":"Idioma de la página", "unchanged":"Los valores y textos originales se muestran como los proporcionó el remitente. Cambiar el idioma no los traduce ni los valida."},
    "fr": {"review":"Vérifiez une modification proposée", "current":"Valeur actuelle", "previous":"Valeur du plan de référence", "proposed":"Valeur proposée", "source":"Extrait sélectionné", "original":"Texte original", "confirm":"Confirmer ces modifications sélectionnées", "correction":"Demander une correction", "decline":"Refuser ces modifications", "comment":"Commentaire (facultatif)", "version":"Révision", "status":"État", "identity":"Réponse du détenteur du lien ; identité non vérifiée", "scope":"Seules les modifications sélectionnées sont partagées. Les confirmer n’approuve aucun élément non affiché.", "wait":"Le plan existant reste en vigueur jusqu’à ce que chaque participant requis confirme chaque modification de cette version exacte.", "closed":"Cette proposition est fermée ou votre réponse est déjà enregistrée. Demandez une nouvelle proposition si une modification est nécessaire.", "local":"Aperçu local de développement · aucun courriel envoyé · pas un service de signature électronique", "recorded":"Réponse enregistrée", "language":"Langue de la page", "unchanged":"Les valeurs et extraits originaux restent tels que fournis par l’expéditeur. Changer la langue ne les traduit pas et ne les valide pas."}
}

STATUS = {
    "en": {"pending": "Awaiting responses", "published": "Published as the current plan", "correction_requested": "A correction was requested", "declined": "Changes declined", "stale": "A newer plan is current", "confirm": "Selected changes confirmed", "correction": "Correction requested", "decline": "Changes declined"},
    "es": {"pending": "En espera de respuestas", "published": "Publicado como plan vigente", "correction_requested": "Se solicitó una corrección", "declined": "Cambios rechazados", "stale": "Hay un plan vigente más reciente", "confirm": "Cambios seleccionados confirmados", "correction": "Corrección solicitada", "decline": "Cambios rechazados"},
    "fr": {"pending": "En attente de réponses", "published": "Publié comme plan en vigueur", "correction_requested": "Une correction a été demandée", "declined": "Modifications refusées", "stale": "Un plan plus récent est en vigueur", "confirm": "Modifications sélectionnées confirmées", "correction": "Correction demandée", "decline": "Modifications refusées"}
}
STATUS["en"]["published_earlier"] = "Previously published revision; a newer plan is current"
STATUS["es"]["published_earlier"] = "Revisión publicada anteriormente; hay un plan vigente más reciente"
STATUS["fr"]["published_earlier"] = "Version publiée auparavant ; un plan plus récent est en vigueur"


CSS = """*{box-sizing:border-box}body{margin:0;background:#f6f3eb;color:#163e43;font:16px/1.55 system-ui,-apple-system,sans-serif}main{max-width:780px;margin:auto;padding:28px 20px 60px;overflow-wrap:anywhere}header{display:flex;align-items:center;justify-content:space-between;gap:16px;border-bottom:1px solid #cad5d1;padding-bottom:20px}.brand{font-size:25px;font-weight:750;letter-spacing:-1px}nav{display:flex}nav a{display:inline-flex;align-items:center;justify-content:center;min-width:44px;min-height:44px;color:#163e43;padding:8px;text-decoration:underline}nav a[aria-current]{background:#e6ede5;border-radius:8px;font-weight:700}h1{font:42px/1.1 Georgia,serif;letter-spacing:-1px;margin:32px 0 12px}h2{font-size:21px;margin-top:0}.sub{color:#536967;font-size:14px}.pill{display:inline-block;padding:6px 11px;border-radius:20px;background:#e6ede5;font-size:13px}article{padding:22px;background:#fffefa;border:1px solid #cad5d1;border-radius:18px;margin:20px 0}.values{display:grid;grid-template-columns:minmax(0,1fr) minmax(0,1fr);gap:14px}.value{padding:14px;border-radius:10px;background:#f2f4ef;overflow-wrap:anywhere}.value strong{display:block;margin-top:6px;white-space:pre-wrap}blockquote{white-space:pre-wrap;overflow-wrap:anywhere;border-left:3px solid #9fbba6;margin:12px 0;padding:10px 14px;background:#f5f6ef}.notice{padding:16px;background:#fff0ce;border-radius:12px}textarea{width:100%;min-height:100px;background:#fffefa;border:1px solid #819f98;border-radius:10px;padding:12px;font:inherit;color:inherit}button{border:1px solid #163e43;border-radius:12px;background:#163e43;color:white;padding:14px 18px;font:inherit;cursor:pointer;min-height:48px}.actions{display:flex;gap:10px;flex-wrap:wrap;margin:18px 0}.secondary{background:#fffefa;color:#163e43}a:focus-visible,button:focus-visible,textarea:focus-visible,summary:focus-visible{outline:3px solid #d29f3d;outline-offset:3px}.meta{display:flex;gap:12px;flex-wrap:wrap}.local{border-top:1px solid #cad5d1;margin-top:32px;padding-top:18px;font-size:12px;color:#536967}.status{font-weight:700}details{margin-top:14px}summary{cursor:pointer;min-height:44px;padding:10px 0}label{display:block;margin:18px 0 8px}@media(max-width:520px){h1{font-size:35px}.values{grid-template-columns:1fr}header{align-items:start}.actions{display:grid}.actions button{width:100%}}"""


def page_shell(title, content, language="en"):
    return f'<!doctype html><html lang="{language}"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>{html.escape(title)} · Recall</title><style>{CSS}</style><main>{content}</main></html>'.encode()


def render_review(view, raw_token, language="en", recorded=False):
    if language not in COPY:
        language = "en"
    t = COPY.get(language, COPY["en"])
    esc = html.escape
    nav = " ".join(f'<a href="?lang={code}" lang="{code}" aria-label="{name}"' + (' aria-current="page"' if code == language else '') + f'>{label}</a>' for code, label, name in [("en", "EN", "English"), ("es", "ES", "Español"), ("fr", "FR", "Français")])
    heading = t["recorded"] if recorded else t["review"]
    displayed_status = "published_earlier" if view["status"] == "published" and view["current_version"] > view["version"] else view["status"]
    parts = [f'<header><div class="brand">Recall</div><nav aria-label="{esc(t["language"])}">{nav}</nav></header>',
             f'<h1>{esc(heading)}</h1><h2 dir="auto">{esc(view["project"])}</h2>',
             f'<p class="sub"><bdi>{esc(view["participant"])}</bdi> · {esc(t["identity"])}</p>',
             f'<p class="meta"><span class="pill">{esc(t["version"])} {view["version"]}</span><span class="pill">{esc(t["status"])}: {esc(STATUS[language].get(displayed_status, displayed_status))}</span></p>',
             f'<p>{esc(t["scope"])}</p><p class="sub">{esc(t["unchanged"])}</p>']
    if recorded:
        parts.append(f'<p class="notice" role="status">{esc(t["recorded"])}</p>')
    for change in view["changes"]:
        parts.append(f'<article><h2 dir="auto">{esc(change["label"])}</h2><div class="values"><div class="value">{esc(t["previous"])}<strong dir="auto">{esc(change["previous"])}</strong></div><div class="value">{esc(t["proposed"])}<strong dir="auto">{esc(change["value"])}</strong></div></div>')
        if view["current_version"] != view["base_version"]:
            parts.append(f'<p class="sub">{esc(t["current"])} (v{view["current_version"]}): <bdi>{esc(change["current"])}</bdi></p>')
        if change["excerpt"]:
            parts.append(f'<p class="sub">{esc(t["source"])}</p><blockquote dir="auto">{esc(change["excerpt"])}</blockquote>')
        if change["original"]:
            parts.append(f'<details><summary>{esc(t["original"])} · {esc(change["language"])}</summary><blockquote dir="auto">{esc(change["original"])}</blockquote></details>')
        parts.append('</article>')
    if view["can_respond"]:
        parts.append(f'<p class="notice">{esc(t["wait"])}</p><form method="post" action="/review/{esc(raw_token)}"><input type="hidden" name="csrf" value="{esc(view["csrf"])}"><input type="hidden" name="version" value="{view["version"]}"><input type="hidden" name="lang" value="{language}"><label for="comment">{esc(t["comment"])}</label><textarea id="comment" name="comment" maxlength="2000"></textarea><div class="actions"><button name="action" value="confirm">{esc(t["confirm"])}</button><button class="secondary" name="action" value="correction">{esc(t["correction"])}</button><button class="secondary" name="action" value="decline">{esc(t["decline"])}</button></div></form>')
    else:
        parts.append(f'<p class="notice">{esc(t["closed"])}</p>')
        if view["response"]:
            parts.append(f'<p class="status">{esc(STATUS[language].get(view["response"]["action"], view["response"]["action"]))}</p><p dir="auto">{esc(view["response"]["comment"])}</p>')
    parts.append(f'<footer class="local">{esc(t["local"])}</footer>')
    return page_shell(heading, "".join(parts), language)


class Handler(BaseHTTPRequestHandler):
    server_version = "RecallLocal/1"

    @property
    def store(self):
        return self.server.store

    def log_message(self, *_):
        # Bearer links and participant content must never enter HTTP access logs.
        pass

    def send(self, status, body, content_type="application/json; charset=utf-8"):
        if not isinstance(body, bytes):
            body = json.dumps(body, ensure_ascii=False).encode()
        self.send_response(status)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        self.send_header("Referrer-Policy", "strict-origin")
        self.send_header("X-Content-Type-Options", "nosniff")
        self.send_header("X-Frame-Options", "DENY")
        self.send_header("Content-Security-Policy", "default-src 'none'; style-src 'unsafe-inline'; form-action 'self'; frame-ancestors 'none'; base-uri 'none'")
        self.end_headers()
        self.wfile.write(body)

    def read_body(self, form=False):
        if self.headers.get("Transfer-Encoding") or len(self.headers.get_all("Content-Length", [])) != 1:
            raise Problem(400, "Use a single Content-Length without transfer encoding.")
        try:
            length = int(self.headers.get("Content-Length", "0"))
        except ValueError:
            raise Problem(400, "Invalid request length.")
        if not 0 < length <= 65536:
            raise Problem(413, "Request must be at most 64 KB and nonempty.")
        kind = self.headers.get("Content-Type", "").split(";")[0]
        expected = "application/x-www-form-urlencoded" if form else "application/json"
        if kind != expected:
            raise Problem(415, "Unsupported request content type.")
        try:
            value = self.rfile.read(length).decode("utf-8")
            if form:
                fields = parse_qs(value, keep_blank_values=True, max_num_fields=10)
                if any(len(v) != 1 for v in fields.values()):
                    raise ValueError()
                result = {k: v[0] for k, v in fields.items()}
                result["version"] = int(result.get("version", "0"))
                return result
            result = json.loads(value, object_pairs_hook=unique_json_object, parse_constant=reject_json_constant)
            if not isinstance(result, dict):
                raise ValueError()
            return result
        except (ValueError, UnicodeDecodeError):
            raise Problem(400, "Invalid request body.")

    def do_GET(self):
        self.dispatch(False)

    def do_POST(self):
        self.dispatch(True)

    def dispatch(self, post):
        route = urlparse(self.path)
        try:
            if self.headers.get("Origin") not in (None, self.store.origin):
                raise Problem(403, "Cross-origin requests are not supported.")
            if not post and route.path == "/health":
                return self.send(200, {"ok": True, "mode": "local-development"})
            match = re.fullmatch(r"/review/([A-Za-z0-9_-]{40,64})", route.path)
            if match:
                token = match.group(1)
                if post:
                    body = self.read_body(form=True)
                    # Validate and capture the immutable review before committing. Reopening
                    # after commit could falsely report failure if the link then expires.
                    view = self.store.review(token)
                    result = self.store.respond(body=body, raw_token=token, origin=self.headers.get("Origin"))
                    language = body.get("lang", "en")
                    if language not in COPY:
                        language = "en"
                    view["status"] = result["status"]
                    view["can_respond"] = False
                    view["response"] = {"action": body["action"].strip(), "comment": body.get("comment", "").strip()}
                    if result["status"] == "published" and view["current_version"] <= result["version"]:
                        view["current_version"] = result["version"]
                        for change in view["changes"]:
                            change["current"] = change["value"]
                    return self.send(200, render_review(view, token, language, recorded=True), "text/html; charset=utf-8")
                language = parse_qs(route.query).get("lang", ["en"])[0]
                if language not in COPY:
                    language = "en"
                return self.send(200, render_review(self.store.review(token), token, language), "text/html; charset=utf-8")
            if route.path.startswith("/api/"):
                self.store.authenticate(self.headers.get("Authorization"))
                if post and route.path == "/api/analyze":
                    try:
                        return self.send(200, analyze(self.read_body()))
                    except AnalysisProblem as problem:
                        raise Problem(problem.status, problem.message) from None
                if not post and route.path == "/api/projects":
                    return self.send(200, {"projects": self.store.list_projects()})
                if not post and (match := re.fullmatch(r"/api/projects/([a-f0-9]{32})", route.path)):
                    return self.send(200, self.store.project_view(match.group(1)))
                if post and route.path == "/api/projects":
                    return self.send(201, self.store.create_project(self.read_body()))
                if post and (match := re.fullmatch(r"/api/projects/([a-f0-9]{32})/revisions", route.path)):
                    return self.send(201, self.store.propose(match.group(1), self.read_body()))
                if post and (match := re.fullmatch(r"/api/revisions/([a-f0-9]{32})/owner-response", route.path)):
                    return self.send(200, self.store.respond(revision_id=match.group(1), body=self.read_body()))
                if post and (match := re.fullmatch(r"/api/revisions/([a-f0-9]{32})/links", route.path)):
                    return self.send(201, self.store.create_link(match.group(1), self.read_body()))
                if post and (match := re.fullmatch(r"/api/links/([a-f0-9]{32})/revoke", route.path)):
                    return self.send(200, self.store.revoke(match.group(1)))
            raise Problem(404, "Route not found.")
        except Problem as problem:
            if route.path.startswith("/review/"):
                body = page_shell("Review unavailable", f'<div class="brand">Recall</div><h1>Review unavailable</h1><p>{html.escape(problem.message)}</p><p class="sub">No response was recorded by this failed request.</p>')
                return self.send(problem.status, body, "text/html; charset=utf-8")
            return self.send(problem.status, {"error": problem.message})
        except Exception:
            # No token, content, SQL or environment values are emitted to clients or logs.
            return self.send(500, {"error": "The local service could not complete this request."})


def make_server(store, host="127.0.0.1", port=8765):
    server = ThreadingHTTPServer((host, port), Handler)
    server.daemon_threads = True
    server.store = store
    store.origin = f"http://{host}:{server.server_address[1]}"
    return server


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--host", choices=["127.0.0.1", "localhost"], default="127.0.0.1", help="Loopback only; this service is not production-ready.")
    parser.add_argument("--port", type=int, default=8765)
    parser.add_argument("--db", default=str(Path(__file__).parent / "local-data" / "recall.sqlite3"))
    args = parser.parse_args()
    token = os.environ.get("RECALL_SERVICE_TOKEN", "")
    if len(token) < 32:
        parser.error("Set RECALL_SERVICE_TOKEN to a random owner token with at least 32 characters. Never share it with recipients.")
    store = Store(args.db, token)
    server = make_server(store, args.host, args.port)
    print(f"Recall local development service listening at {store.origin}. No review URLs or tokens are logged.", flush=True)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()


if __name__ == "__main__":
    main()
