# -*- coding: utf-8 -*-
"""
history_db.py
Tiện ích lưu/querry lịch sử chạy cho từng profile vào SQLite.
"""

from __future__ import annotations
import os
import sqlite3
import json
from typing import Any, Dict, List, Optional
from datetime import datetime, timezone


def _connect(db_path: str) -> sqlite3.Connection:
    os.makedirs(os.path.dirname(db_path) or ".", exist_ok=True)
    conn = sqlite3.connect(db_path, timeout=30)
    conn.row_factory = sqlite3.Row
    return conn


def init_db(db_path: str) -> None:
    """
    Tạo DB + bảng nếu chưa có. Bật WAL để ghi nhanh hơn.
    """
    with _connect(db_path) as conn:
        cur = conn.cursor()
        try:
            cur.execute("PRAGMA journal_mode=WAL;")
            cur.execute("PRAGMA synchronous=NORMAL;")
        except Exception:
            pass
        cur.execute(
            """
            CREATE TABLE IF NOT EXISTS search_click_history (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                ts TEXT NOT NULL,
                site TEXT,
                title TEXT,
                follow_title TEXT,
                profile TEXT,
                nav_url TEXT,
                used_coords TEXT,
                screenX INTEGER,
                screenY INTEGER,
                cursorX INTEGER,
                cursorY INTEGER,
                clicked INTEGER,
                ok INTEGER,
                error TEXT,
                dom_ready INTEGER,
                selector_ok INTEGER,
                active_is_input_q INTEGER,
                typed INTEGER,
                typed_text TEXT,
                pressed_enter INTEGER,
                dom_ready_after_enter INTEGER,
                follow_clicked INTEGER,
                follow_clicked_via TEXT,
                follow_forced INTEGER,
                follow_text TEXT,
                follow_aria TEXT,
                follow_e2e TEXT,
                follow_should_click INTEGER,
                follow_map TEXT,
                result_json TEXT
            );
            """
        )
        conn.commit()


def _now_iso_utc() -> str:
    return datetime.now(timezone.utc).isoformat().replace("+00:00", "Z")


def _b(v: Any) -> int:
    return 1 if bool(v) else 0


def insert_history(db_path: str, row: Dict[str, Any]) -> int:
    """
    Ghi 1 record lịch sử. Trả về id của dòng vừa insert.
    Bắt buộc các key chính phải có; phần thiếu sẽ được mặc định None.
    """
    fields = {
        "ts": row.get("ts") or _now_iso_utc(),
        "site": row.get("site"),
        "title": row.get("title"),
        "follow_title": row.get("follow_title"),
        "profile": row.get("profile"),
        "nav_url": row.get("nav_url"),
        "used_coords": row.get("used_coords"),
        "screenX": row.get("screenX"),
        "screenY": row.get("screenY"),
        "cursorX": row.get("cursorX"),
        "cursorY": row.get("cursorY"),
        "clicked": _b(row.get("clicked")),
        "ok": _b(row.get("ok")),
        "error": row.get("error"),
        "dom_ready": _b(row.get("dom_ready")),
        "selector_ok": _b(row.get("selector_ok")),
        "active_is_input_q": _b(row.get("active_is_input_q")),
        "typed": _b(row.get("typed")),
        "typed_text": row.get("typed_text"),
        "pressed_enter": _b(row.get("pressed_enter")),
        "dom_ready_after_enter": _b(row.get("dom_ready_after_enter")),
        "follow_clicked": _b(row.get("follow_clicked")),
        "follow_clicked_via": ",".join(row.get("follow_clicked_via") or []) if isinstance(row.get("follow_clicked_via"), list) else row.get("follow_clicked_via"),
        "follow_forced": _b(row.get("follow_forced")),
        "follow_text": row.get("follow_text"),
        "follow_aria": row.get("follow_aria"),
        "follow_e2e": row.get("follow_e2e"),
        "follow_should_click": _b(row.get("follow_should_click")),
        "follow_map": json.dumps(row.get("follow_map"), ensure_ascii=False) if isinstance(row.get("follow_map"), (dict, list)) else (row.get("follow_map") or None),
        "result_json": json.dumps(row.get("result_json"), ensure_ascii=False) if isinstance(row.get("result_json"), (dict, list)) else (row.get("result_json") or None),
    }

    with _connect(db_path) as conn:
        cur = conn.cursor()
        cur.execute(
            """
            INSERT INTO search_click_history (
                ts, site, title, follow_title, profile, nav_url, used_coords,
                screenX, screenY, cursorX, cursorY, clicked, ok, error,
                dom_ready, selector_ok, active_is_input_q, typed, typed_text, pressed_enter,
                dom_ready_after_enter, follow_clicked, follow_clicked_via, follow_forced,
                follow_text, follow_aria, follow_e2e, follow_should_click, follow_map, result_json
            ) VALUES (
                :ts, :site, :title, :follow_title, :profile, :nav_url, :used_coords,
                :screenX, :screenY, :cursorX, :cursorY, :clicked, :ok, :error,
                :dom_ready, :selector_ok, :active_is_input_q, :typed, :typed_text, :pressed_enter,
                :dom_ready_after_enter, :follow_clicked, :follow_clicked_via, :follow_forced,
                :follow_text, :follow_aria, :follow_e2e, :follow_should_click, :follow_map, :result_json
            );
            """,
            fields,
        )
        conn.commit()
        return int(cur.lastrowid)


def query_history(
    db_path: str,
    profile: Optional[str] = None,
    site: Optional[str] = None,
    title: Optional[str] = None,
    limit: int = 50,
    offset: int = 0,
) -> List[Dict[str, Any]]:
    """
    Trả về danh sách record (mới → cũ). Hỗ trợ filter đơn giản.
    """
    where = []
    args: List[Any] = []
    if profile:
        where.append("profile = ?"); args.append(profile)
    if site:
        where.append("site = ?"); args.append(site)
    if title:
        where.append("title = ?"); args.append(title)
    sql = "SELECT * FROM search_click_history"
    if where:
        sql += " WHERE " + " AND ".join(where)
    sql += " ORDER BY id DESC LIMIT ? OFFSET ?"
    args.extend([int(limit), int(offset)])

    with _connect(db_path) as conn:
        cur = conn.cursor()
        rows = [dict(r) for r in cur.execute(sql, args).fetchall()]
    return rows
