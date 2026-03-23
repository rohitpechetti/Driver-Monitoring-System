"""
Email Service - Sends alert emails with screenshots to admins,
and OTP emails for password reset.
Uses smtplib directly (more reliable than Flask-Mail on Render).
"""

import os
import smtplib
import traceback
from email.mime.multipart import MIMEMultipart
from email.mime.text import MIMEText
from email.mime.image import MIMEImage
from typing import Optional


def _get_smtp_config():
    return {
        'server':   os.environ.get('MAIL_SERVER',   'smtp.gmail.com'),
        'port':     int(os.environ.get('MAIL_PORT', 465)),
        'username': os.environ.get('MAIL_USERNAME', ''),
        'password': os.environ.get('MAIL_PASSWORD', ''),
        'sender':   os.environ.get('MAIL_DEFAULT_SENDER',
                    os.environ.get('MAIL_USERNAME', '')),
    }


def _mail_configured() -> bool:
    cfg = _get_smtp_config()
    if not cfg['username'] or not cfg['password']:
        print("[Email] MAIL_USERNAME or MAIL_PASSWORD not set in environment")
        return False
    if 'your_email' in cfg['username'] or 'your_app_password' in cfg['password']:
        print("[Email] Mail still has placeholder credentials")
        return False
    return True


def _send(msg: MIMEMultipart):
    """Send an email using smtplib with SSL (port 465)."""
    cfg = _get_smtp_config()
    print(f"[Email] Connecting to {cfg['server']}:{cfg['port']} as {cfg['username']}")
    with smtplib.SMTP_SSL(cfg['server'], cfg['port']) as server:
        server.login(cfg['username'], cfg['password'])
        server.sendmail(cfg['sender'], msg['To'], msg.as_string())
    print(f"[Email] Sent to {msg['To']}")


class EmailService:
    def __init__(self, mail=None):
        # mail param kept for backward compatibility but not used
        pass

    # ── Driver alert email ────────────────────────────────────────────────────

    def send_alert_email(
        self,
        to_email: str,
        driver_name: str,
        alert_type: str,
        timestamp: str,
        screenshot_path: Optional[str] = None,
    ):
        if not _mail_configured():
            print(f"[Email] Skipping alert email to {to_email} - mail not configured")
            return

        try:
            cfg = _get_smtp_config()
            msg = MIMEMultipart('related')
            msg['Subject'] = f"[DMS Alert] {alert_type} - Driver: {driver_name}"
            msg['From']    = cfg['sender']
            msg['To']      = to_email

            html_body = f"""
<h2>&#128680; Driver Monitoring Alert</h2>
<p><b>Driver:</b> {driver_name}</p>
<p><b>Alert:</b>  {alert_type}</p>
<p><b>Time:</b>   {timestamp}</p>
<p>Please review the situation immediately.</p>
"""
            text_body = (
                f"Driver Monitoring System - Incident Alert\n\n"
                f"Driver: {driver_name}\nAlert: {alert_type}\nTime: {timestamp}\n"
                f"Please review immediately."
            )

            if screenshot_path and os.path.exists(screenshot_path):
                with open(screenshot_path, 'rb') as f:
                    img_data = f.read()
                img = MIMEImage(img_data, name="driver.jpg")
                img.add_header('Content-ID', '<driver_image>')
                msg.attach(img)
                html_body += '<h3>Driver Snapshot:</h3><img src="cid:driver_image" width="300"/>'
                print(f"[Email] Screenshot attached: {screenshot_path}")
            else:
                print("[Email] No screenshot attached")

            alt = MIMEMultipart('alternative')
            alt.attach(MIMEText(text_body, 'plain'))
            alt.attach(MIMEText(html_body, 'html'))
            msg.attach(alt)

            _send(msg)

        except Exception as e:
            print(f"[Email] Failed to send alert to {to_email}: {e}")
            traceback.print_exc()

    # ── Admin approval notification ───────────────────────────────────────────

    def send_approval_notification(self, to_email: str, username: str):
        if not _mail_configured():
            return
        try:
            cfg = _get_smtp_config()
            msg = MIMEMultipart('alternative')
            msg['Subject'] = "[DMS] Your Account Has Been Approved"
            msg['From']    = cfg['sender']
            msg['To']      = to_email

            body = (
                f"Hello {username},\n\n"
                "Your account on the Driver Monitoring System has been approved.\n"
                "You can now log in and access the system.\n\n"
                "— Driver Monitoring System"
            )
            msg.attach(MIMEText(body, 'plain'))
            _send(msg)

        except Exception as e:
            print(f"[Email] Failed to send approval notification: {e}")
            traceback.print_exc()

    # ── New admin/superadmin registration alert ───────────────────────────────

    def send_registration_alert_to_superadmin(
        self, superadmin_email: str, new_username: str, role: str
    ):
        if not _mail_configured():
            return
        try:
            cfg = _get_smtp_config()
            msg = MIMEMultipart('alternative')
            msg['Subject'] = f"[DMS] New {role} registration: {new_username}"
            msg['From']    = cfg['sender']
            msg['To']      = superadmin_email

            body = (
                f"Driver Monitoring System - New Registration\n\n"
                f"A new {role} account is pending your approval:\n\n"
                f"Username : {new_username}\nRole     : {role}\n\n"
                "Please log in to the Super Admin panel to approve or reject.\n\n"
                "— Driver Monitoring System"
            )
            msg.attach(MIMEText(body, 'plain'))
            _send(msg)

        except Exception as e:
            print(f"[Email] Failed to send registration alert: {e}")
            traceback.print_exc()

    # ── Password reset OTP ────────────────────────────────────────────────────

    def send_password_reset_otp(self, to_email: str, username: str, otp: str):
        if not _mail_configured():
            print(f"[Email] Skipping OTP email to {to_email} - mail not configured")
            return

        try:
            cfg = _get_smtp_config()
            msg = MIMEMultipart('alternative')
            msg['Subject'] = "[DMS] Password Reset OTP"
            msg['From']    = cfg['sender']
            msg['To']      = to_email

            text_body = (
                f"Driver Monitoring System - Password Reset\n\n"
                f"Hello {username},\n\n"
                f"Your OTP for resetting your password is:\n\n  {otp}\n\n"
                "This OTP is valid for 10 minutes.\n"
                "If you did not request a password reset, ignore this email.\n\n"
                "— Driver Monitoring System"
            )

            html_body = f"""
<div style="font-family:Arial,sans-serif;max-width:480px;margin:auto;">
  <h2 style="color:#0A1628;">&#128272; Password Reset</h2>
  <p>Hello <b>{username}</b>,</p>
  <p>Use the OTP below to reset your Driver Monitoring System password:</p>
  <div style="
    font-size:36px;font-weight:bold;letter-spacing:12px;
    text-align:center;padding:20px;margin:24px 0;
    background:#f0f8ff;border:2px solid #00D4FF;
    border-radius:12px;color:#0A1628;">
    {otp}
  </div>
  <p style="color:#666;">This OTP expires in <b>10 minutes</b>.</p>
  <p style="color:#666;">If you did not request this, simply ignore this email.</p>
  <hr style="border:none;border-top:1px solid #eee;margin:24px 0;">
  <p style="color:#999;font-size:12px;">— Driver Monitoring System</p>
</div>
"""
            msg.attach(MIMEText(text_body, 'plain'))
            msg.attach(MIMEText(html_body, 'html'))
            _send(msg)

        except Exception as e:
            print(f"[Email] Failed to send OTP to {to_email}: {e}")
            traceback.print_exc()