"""
Database module - SQLite with role-based user management and incident logging.
Includes OTP storage for password reset.
"""

import sqlite3
import hashlib
import os
import random
import string
from datetime import datetime, timedelta
from typing import Optional, List, Dict, Any


DB_PATH = os.path.join(os.path.dirname(__file__), 'driver_monitor.db')


def _hash_password(password: str) -> str:
    return hashlib.sha256(password.encode()).hexdigest()


class Database:
    def __init__(self, db_path: str = DB_PATH):
        self.db_path = db_path
        self.init_db()

    def _connect(self):
        conn = sqlite3.connect(self.db_path)
        conn.row_factory = sqlite3.Row
        return conn

    def init_db(self):
        """Create tables and seed a default super admin."""
        with self._connect() as conn:
            conn.executescript("""
                CREATE TABLE IF NOT EXISTS users (
                    id          INTEGER PRIMARY KEY AUTOINCREMENT,
                    username    TEXT    NOT NULL UNIQUE,
                    email       TEXT    NOT NULL UNIQUE,
                    password    TEXT    NOT NULL,
                    role        TEXT    NOT NULL DEFAULT 'user',
                    is_approved INTEGER NOT NULL DEFAULT 1,
                    created_at  TEXT    NOT NULL
                );

                CREATE TABLE IF NOT EXISTS logs (
                    id              INTEGER PRIMARY KEY AUTOINCREMENT,
                    username        TEXT    NOT NULL,
                    status          TEXT    NOT NULL,
                    timestamp       TEXT    NOT NULL,
                    screenshot_path TEXT
                );

                CREATE TABLE IF NOT EXISTS password_reset_otps (
                    id         INTEGER PRIMARY KEY AUTOINCREMENT,
                    email      TEXT    NOT NULL,
                    otp        TEXT    NOT NULL,
                    expires_at TEXT    NOT NULL,
                    used       INTEGER NOT NULL DEFAULT 0,
                    created_at TEXT    NOT NULL
                );
            """)
            # Seed default super admin if none exists
            existing = conn.execute(
                "SELECT id FROM users WHERE role='superadmin' LIMIT 1"
            ).fetchone()
            if not existing:
                conn.execute(
                    "INSERT INTO users (username, email, password, role, is_approved, created_at) "
                    "VALUES (?, ?, ?, 'superadmin', 1, ?)",
                    ('Rohit', 'rohitpechetti03@gmail.com', _hash_password('Rohit@456'),
                     datetime.now().isoformat())
                )
                conn.commit()
                print("[DB] Default super admin created: superadmin / superadmin123")

    # ── User operations ───────────────────────────────────────────────────────

    def create_user(self, username: str, email: str, password: str,
                    role: str, is_approved: int) -> Optional[int]:
        try:
            with self._connect() as conn:
                cursor = conn.execute(
                    "INSERT INTO users (username, email, password, role, is_approved, created_at) "
                    "VALUES (?, ?, ?, ?, ?, ?)",
                    (username, email, _hash_password(password), role, is_approved,
                     datetime.now().isoformat())
                )
                conn.commit()
                return cursor.lastrowid
        except sqlite3.IntegrityError:
            return None

    def authenticate_user(self, username: str, password: str) -> Optional[Dict]:
        with self._connect() as conn:
            row = conn.execute(
                "SELECT * FROM users WHERE username=? AND password=?",
                (username, _hash_password(password))
            ).fetchone()
            return dict(row) if row else None

    def get_user_by_username(self, username: str) -> Optional[Dict]:
        with self._connect() as conn:
            row = conn.execute(
                "SELECT * FROM users WHERE username=?", (username,)
            ).fetchone()
            return dict(row) if row else None

    def get_user_by_email(self, email: str) -> Optional[Dict]:
        with self._connect() as conn:
            row = conn.execute(
                "SELECT * FROM users WHERE email=?", (email,)
            ).fetchone()
            return dict(row) if row else None

    def get_user_by_id(self, user_id: int) -> Optional[Dict]:
        with self._connect() as conn:
            row = conn.execute(
                "SELECT * FROM users WHERE id=?", (user_id,)
            ).fetchone()
            return dict(row) if row else None

    def get_all_users(self) -> List[Dict]:
        with self._connect() as conn:
            rows = conn.execute(
                "SELECT id, username, email, role, is_approved, created_at "
                "FROM users ORDER BY created_at DESC"
            ).fetchall()
            return [dict(r) for r in rows]

    def get_pending_admins(self) -> List[Dict]:
        with self._connect() as conn:
            rows = conn.execute(
                "SELECT id, username, email, role, created_at FROM users "
                "WHERE role IN ('admin','superadmin') AND is_approved=0 ORDER BY created_at DESC"
            ).fetchall()
            return [dict(r) for r in rows]

    def get_approved_admins(self) -> List[Dict]:
        with self._connect() as conn:
            rows = conn.execute(
                "SELECT id, username, email FROM users "
                "WHERE role IN ('admin','superadmin') AND is_approved=1"
            ).fetchall()
            return [dict(r) for r in rows]

    def get_superadmins(self) -> List[Dict]:
        with self._connect() as conn:
            rows = conn.execute(
                "SELECT id, username, email FROM users "
                "WHERE role='superadmin' AND is_approved=1"
            ).fetchall()
            return [dict(r) for r in rows]

    def approve_user(self, user_id: int) -> bool:
        with self._connect() as conn:
            conn.execute("UPDATE users SET is_approved=1 WHERE id=?", (user_id,))
            conn.commit()
            return conn.execute("SELECT changes()").fetchone()[0] > 0

    def delete_user(self, user_id: int) -> bool:
        with self._connect() as conn:
            conn.execute("DELETE FROM users WHERE id=?", (user_id,))
            conn.commit()
            return conn.execute("SELECT changes()").fetchone()[0] > 0

    # ── OTP / Password-reset operations ───────────────────────────────────────

    def generate_otp(self) -> str:
        """Generate a cryptographically random 6-digit OTP."""
        return ''.join(random.choices(string.digits, k=6))

    def create_otp(self, email: str) -> str:
        """
        Invalidate any existing unused OTPs for this email, then
        create a fresh one that expires in 10 minutes.
        Returns the plain-text OTP.
        """
        otp = self.generate_otp()
        expires_at = (datetime.now() + timedelta(minutes=10)).isoformat()
        with self._connect() as conn:
            # Invalidate previous OTPs for this email
            conn.execute(
                "UPDATE password_reset_otps SET used=1 WHERE email=? AND used=0",
                (email,)
            )
            conn.execute(
                "INSERT INTO password_reset_otps (email, otp, expires_at, used, created_at) "
                "VALUES (?, ?, ?, 0, ?)",
                (email, otp, expires_at, datetime.now().isoformat())
            )
            conn.commit()
        return otp

    def verify_otp(self, email: str, otp: str) -> bool:
        """
        Return True if the OTP is valid, unused, and not yet expired.
        Does NOT mark it as used (so the same OTP can be reused in step 3).
        """
        with self._connect() as conn:
            row = conn.execute(
                "SELECT expires_at FROM password_reset_otps "
                "WHERE email=? AND otp=? AND used=0 "
                "ORDER BY created_at DESC LIMIT 1",
                (email, otp)
            ).fetchone()
            if not row:
                return False
            expires_at = datetime.fromisoformat(row['expires_at'])
            return datetime.now() < expires_at

    def consume_otp_and_reset_password(self, email: str, otp: str,
                                       new_password: str) -> bool:
        """
        Verify OTP again, mark it as used, then update the user's password.
        Returns True on success.
        """
        if not self.verify_otp(email, otp):
            return False
        with self._connect() as conn:
            # Mark OTP as used
            conn.execute(
                "UPDATE password_reset_otps SET used=1 "
                "WHERE email=? AND otp=? AND used=0",
                (email, otp)
            )
            # Update password
            conn.execute(
                "UPDATE users SET password=? WHERE email=?",
                (_hash_password(new_password), email)
            )
            conn.commit()
            changed = conn.execute("SELECT changes()").fetchone()[0]
        return changed > 0

    # ── Log operations ────────────────────────────────────────────────────────

    def create_log(self, username: str, status: str,
                   timestamp: str, screenshot_path: Optional[str]) -> Optional[int]:
        try:
            with self._connect() as conn:
                cursor = conn.execute(
                    "INSERT INTO logs (username, status, timestamp, screenshot_path) "
                    "VALUES (?, ?, ?, ?)",
                    (username, status, timestamp, screenshot_path)
                )
                conn.commit()
                return cursor.lastrowid
        except Exception as e:
            print(f"[DB] Log creation error: {e}")
            return None

    def get_logs(self, username_filter: Optional[str] = None) -> List[Dict]:
        with self._connect() as conn:
            if username_filter:
                rows = conn.execute(
                    "SELECT * FROM logs WHERE username=? ORDER BY timestamp DESC",
                    (username_filter,)
                ).fetchall()
            else:
                rows = conn.execute(
                    "SELECT * FROM logs ORDER BY timestamp DESC"
                ).fetchall()
            return [dict(r) for r in rows]

    def get_stats(self) -> Dict[str, Any]:
        with self._connect() as conn:
            total_logs = conn.execute(
                "SELECT COUNT(*) as c FROM logs").fetchone()['c']
            total_users = conn.execute(
                "SELECT COUNT(*) as c FROM users WHERE role='user'").fetchone()['c']
            total_admins = conn.execute(
                "SELECT COUNT(*) as c FROM users WHERE role='admin'").fetchone()['c']
            pending_admins = conn.execute(
                "SELECT COUNT(*) as c FROM users WHERE role='admin' AND is_approved=0"
            ).fetchone()['c']

            alert_breakdown_rows = conn.execute(
                "SELECT status, COUNT(*) as count FROM logs "
                "GROUP BY status ORDER BY count DESC LIMIT 10"
            ).fetchall()
            alert_breakdown = [dict(r) for r in alert_breakdown_rows]

            recent_rows = conn.execute(
                "SELECT username, status, timestamp FROM logs "
                "ORDER BY timestamp DESC LIMIT 10"
            ).fetchall()
            recent_logs = [dict(r) for r in recent_rows]

            top_drivers_rows = conn.execute(
                "SELECT username, COUNT(*) as incidents FROM logs "
                "GROUP BY username ORDER BY incidents DESC LIMIT 5"
            ).fetchall()
            top_drivers = [dict(r) for r in top_drivers_rows]

            return {
                'total_logs':       total_logs,
                'total_users':      total_users,
                'total_admins':     total_admins,
                'pending_admins':   pending_admins,
                'alert_breakdown':  alert_breakdown,
                'recent_logs':      recent_logs,
                'top_drivers':      top_drivers,
            }

