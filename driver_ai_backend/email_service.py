"""
Email Service - Sends alert emails with screenshots to admins.
"""

from flask_mail import Message
import os
from typing import Optional


class EmailService:
    def __init__(self, mail):
        self.mail = mail

    def send_alert_email(
        self,
        to_email: str,
        driver_name: str,
        alert_type: str,
        timestamp: str,
        screenshot_path: Optional[str] = None
    ):
        """Send incident alert email to an admin."""
        try:
            subject = f"[DMS Alert] {alert_type} - Driver: {driver_name}"
            body = f"""
Driver Monitoring System - Incident Alert
==========================================

Driver Name  : {driver_name}
Alert Type   : {alert_type}
Time         : {timestamp}

Please review the attached screenshot and take appropriate action.

—
Driver Monitoring System
Automated Alert Service
            """.strip()

            msg = Message(subject=subject, recipients=[to_email], body=body)

            if screenshot_path and os.path.exists(screenshot_path):
                with open(screenshot_path, 'rb') as f:
                    msg.attach(
                        filename=os.path.basename(screenshot_path),
                        content_type='image/jpeg',
                        data=f.read()
                    )

            self.mail.send(msg)
            print(f"[Email] Alert sent to {to_email}: {alert_type}")

        except Exception as e:
            print(f"[Email] Failed to send alert to {to_email}: {e}")

    def send_approval_notification(self, to_email: str, username: str):
        """Notify admin that their account has been approved."""
        try:
            msg = Message(
                subject="[DMS] Your Admin Account Has Been Approved",
                recipients=[to_email],
                body=f"""
Hello {username},

Your admin account on the Driver Monitoring System has been approved.
You can now log in and access the admin dashboard.

—
Driver Monitoring System
                """.strip()
            )
            self.mail.send(msg)
            print(f"[Email] Approval notification sent to {to_email}")
        except Exception as e:
            print(f"[Email] Failed to send approval notification: {e}")
