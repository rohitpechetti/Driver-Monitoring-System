"""
Email Service - Sends alert emails with screenshots to admins,
and OTP emails for password reset.
"""
from flask_mail import Message
import os
import traceback
from typing import Optional


class EmailService:
    def __init__(self, mail):
        self.mail = mail

    def _mail_configured(self) -> bool:
        """Check if mail credentials are properly set."""
        username = os.environ.get('MAIL_USERNAME', '')
        password = os.environ.get('MAIL_PASSWORD', '')
        if not username or not password or 'your_email' in username or 'your_app_password' in password:
            print("[Email] Mail not configured - set MAIL_USERNAME and MAIL_PASSWORD env vars on Render")
            return False
        return True

    # ── Driver alert email ────────────────────────────────────────────────────

    def send_alert_email(
        self,
        to_email: str,
        driver_name: str,
        alert_type: str,
        timestamp: str,
        screenshot_path: Optional[str] = None,
    ):
        if not self._mail_configured():
            print(f"[Email] Skipping alert email to {to_email} - mail not configured")
            return

        try:
            subject = f"[DMS Alert] {alert_type} - Driver: {driver_name}"

            body = f"""
Driver Monitoring System - Incident Alert

Driver Name  : {driver_name}
Alert Type   : {alert_type}
Time         : {timestamp}

Please review the situation immediately.
            """.strip()

            msg       = Message(subject=subject, recipients=[to_email])
            msg.body  = body

            html_body = f"""
<h2>🚨 Driver Monitoring Alert</h2>
<p><b>Driver:</b> {driver_name}</p>
<p><b>Alert:</b>  {alert_type}</p>
<p><b>Time:</b>   {timestamp}</p>
<p>Please review the situation immediately.</p>
"""

            if screenshot_path:
                print(f"[DEBUG] Checking screenshot path: {screenshot_path}")

            if screenshot_path and os.path.exists(screenshot_path):
                with open(screenshot_path, 'rb') as f:
                    img_data = f.read()

                msg.attach(
                    filename="driver.jpg",
                    content_type="image/jpeg",
                    data=img_data,
                    headers=[('Content-ID', '<driver_image>')],
                )
                print(f"[Email] Screenshot attached: {screenshot_path}")
                html_body += """
<h3>Driver Snapshot:</h3>
<img src="cid:driver_image" width="300"/>
"""
            else:
                print("[Email] Screenshot NOT attached (missing or invalid path)")

            msg.html = html_body
            self.mail.send(msg)
            print(f"[Email] Alert sent to {to_email}: {alert_type}")

        except Exception as e:
            print(f"[Email] Failed to send alert to {to_email}: {e}")
            traceback.print_exc()

    # ── Admin approval notification ───────────────────────────────────────────

    def send_approval_notification(self, to_email: str, username: str):
        if not self._mail_configured():
            return
        try:
            msg = Message(
                subject="[DMS] Your Account Has Been Approved",
                recipients=[to_email],
                body=f"""
Hello {username},

Your account on the Driver Monitoring System has been approved.
You can now log in and access the system.

— Driver Monitoring System
                """.strip(),
            )
            self.mail.send(msg)
            print(f"[Email] Approval notification sent to {to_email}")
        except Exception as e:
            print(f"[Email] Failed to send approval notification: {e}")

    # ── New admin/superadmin registration alert ───────────────────────────────

    def send_registration_alert_to_superadmin(
        self, superadmin_email: str, new_username: str, role: str
    ):
        """Notify superadmin when a new admin registers."""
        if not self._mail_configured():
            return
        try:
            msg = Message(
                subject=f"[DMS] New {role} registration: {new_username}",
                recipients=[superadmin_email],
                body=f"""
Driver Monitoring System - New Registration

A new {role} account is pending your approval:

Username : {new_username}
Role     : {role}

Please log in to the Super Admin panel to approve or reject.

— Driver Monitoring System
                """.strip(),
            )
            self.mail.send(msg)
            print(f"[Email] Registration alert sent to superadmin {superadmin_email}")
        except Exception as e:
            print(f"[Email] Failed to send registration alert: {e}")

    # ── Password reset OTP ────────────────────────────────────────────────────

    def send_password_reset_otp(self, to_email: str, username: str, otp: str):
        """
        Send a 6-digit OTP to the user's registered email address
        for the forgot-password flow.
        """
        if not self._mail_configured():
            print(f"[Email] Skipping OTP email to {to_email} - mail not configured")
            return

        try:
            subject = "[DMS] Password Reset OTP"

            body = f"""
Driver Monitoring System - Password Reset

Hello {username},

Your one-time password (OTP) for resetting your account password is:

  {otp}

This OTP is valid for 10 minutes.
If you did not request a password reset, please ignore this email.

— Driver Monitoring System
            """.strip()

            html_body = f"""
<div style="font-family:Arial,sans-serif;max-width:480px;margin:auto;">
  <h2 style="color:#0A1628;">🔐 Password Reset</h2>
  <p>Hello <b>{username}</b>,</p>
  <p>Use the OTP below to reset your Driver Monitoring System password:</p>
  <div style="
    font-size:36px;
    font-weight:bold;
    letter-spacing:12px;
    text-align:center;
    padding:20px;
    margin:24px 0;
    background:#f0f8ff;
    border:2px solid #00D4FF;
    border-radius:12px;
    color:#0A1628;">
    {otp}
  </div>
  <p style="color:#666;">This OTP expires in <b>10 minutes</b>.</p>
  <p style="color:#666;">If you did not request this, simply ignore this email.</p>
  <hr style="border:none;border-top:1px solid #eee;margin:24px 0;">
  <p style="color:#999;font-size:12px;">— Driver Monitoring System</p>
</div>
"""

            msg      = Message(subject=subject, recipients=[to_email])
            msg.body = body
            msg.html = html_body
            self.mail.send(msg)
            print(f"[Email] OTP sent to {to_email}")

        except Exception as e:
            print(f"[Email] Failed to send OTP to {to_email}: {e}")
            traceback.print_exc()