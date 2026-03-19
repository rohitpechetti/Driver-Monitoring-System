
"""
Email Service - Sends alert emails with screenshots to admins.
"""
"""
Email Service - Sends alert emails with screenshots to admins.
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
        username = os.environ.get('MAIL_USERNAME', 'your_email@gmail.com')
        password = os.environ.get('MAIL_PASSWORD', 'your_app_password')
        if 'your_email' in username or 'your_app_password' in password:
            print("[Email] Mail not configured - set MAIL_USERNAME and MAIL_PASSWORD env vars on Render")
            return False
        return True

    def send_alert_email(
        self,
        to_email: str,
        driver_name: str,
        alert_type: str,
        timestamp: str,
        screenshot_path: Optional[str] = None
    ):
        if not self._mail_configured():
            print(f"[Email] Skipping alert email to {to_email} - mail not configured")
            return

        try:
            subject = f"[DMS Alert] {alert_type} - Driver: {driver_name}"

            # Plain text fallback
            body = f"""
Driver Monitoring System - Incident Alert

Driver Name  : {driver_name}
Alert Type   : {alert_type}
Time         : {timestamp}

Please review the situation immediately.
            """.strip()

            msg = Message(subject=subject, recipients=[to_email])
            msg.body = body  # fallback

            # HTML email
            html_body = f"""
<h2>🚨 Driver Monitoring Alert</h2>

<p><b>Driver:</b> {driver_name}</p>
<p><b>Alert:</b> {alert_type}</p>
<p><b>Time:</b> {timestamp}</p>

<p>Please review the situation immediately.</p>
"""

            # ✅ Attach + Embed image
            if screenshot_path:
                print(f"[DEBUG] Checking screenshot path: {screenshot_path}")

            if screenshot_path and os.path.exists(screenshot_path):
                with open(screenshot_path, 'rb') as f:
                    img_data = f.read()

                # Attach image
                msg.attach(
                    filename="driver.jpg",
                    content_type="image/jpeg",
                    data=img_data,
                    headers=[('Content-ID', '<driver_image>')]
                )

                print(f"[Email] Screenshot attached: {screenshot_path}")

                # Embed image in HTML
                html_body += """
<h3>Driver Snapshot:</h3>
<img src="cid:driver_image" width="300"/>
"""
            else:
                print("[Email] Screenshot NOT attached (missing or invalid path)")

            msg.html = html_body

            # Send email
            self.mail.send(msg)
            print(f"[Email] Alert sent to {to_email}: {alert_type}")

        except Exception as e:
            print(f"[Email] Failed to send alert to {to_email}: {e}")
            traceback.print_exc()

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
                """.strip()
            )
            self.mail.send(msg)
            print(f"[Email] Approval notification sent to {to_email}")
        except Exception as e:
            print(f"[Email] Failed to send approval notification: {e}")

    def send_registration_alert_to_superadmin(
        self, superadmin_email: str, new_username: str, role: str
    ):
        """Notify superadmin when a new admin/superadmin registers."""
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
                """.strip()
            )
            self.mail.send(msg)
            print(f"[Email] Registration alert sent to superadmin {superadmin_email}")
        except Exception as e:
            print(f"[Email] Failed to send registration alert: {e}")