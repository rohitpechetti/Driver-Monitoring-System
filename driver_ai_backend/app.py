"""
Driver Monitoring System - Flask Backend
Main application entry point with all API endpoints
"""

from flask import Flask, request, jsonify, send_file, Response
from flask_cors import CORS
from flask_mail import Mail
import os
import csv
import io
import json
from datetime import datetime
from database import Database
from email_service import EmailService
from detection import DetectionEngine

app = Flask(__name__)
CORS(app)

# ─── Mail Configuration ────────────────────────────────────────────────────────
app.config['MAIL_SERVER'] = os.environ.get('MAIL_SERVER', 'smtp.gmail.com')
app.config['MAIL_PORT'] = int(os.environ.get('MAIL_PORT', 587))
app.config['MAIL_USE_TLS'] = True
app.config['MAIL_USERNAME'] = os.environ.get('MAIL_USERNAME', 'your_email@gmail.com')
app.config['MAIL_PASSWORD'] = os.environ.get('MAIL_PASSWORD', 'your_app_password')
app.config['MAIL_DEFAULT_SENDER'] = os.environ.get('MAIL_USERNAME', 'your_email@gmail.com')

mail = Mail(app)
db = Database()
email_service = EmailService(mail)
detection_engine = DetectionEngine()

SCREENSHOTS_DIR = os.path.join(os.path.dirname(__file__), 'screenshots')
os.makedirs(SCREENSHOTS_DIR, exist_ok=True)


# ─── Authentication Endpoints ──────────────────────────────────────────────────

@app.route('/api/register', methods=['POST'])
def register():
    """Register a new user. Admins require Super Admin approval."""
    data = request.get_json()
    required = ['username', 'email', 'password', 'role']
    if not all(k in data for k in required):
        return jsonify({'success': False, 'message': 'Missing required fields'}), 400

    username = data['username'].strip()
    email = data['email'].strip().lower()
    password = data['password']
    role = data['role'].lower()

    if role not in ['user', 'admin', 'superadmin']:
        return jsonify({'success': False, 'message': 'Invalid role'}), 400

    if db.get_user_by_username(username):
        return jsonify({'success': False, 'message': 'Username already exists'}), 409

    if db.get_user_by_email(email):
        return jsonify({'success': False, 'message': 'Email already registered'}), 409

    # Users are auto-approved; admins need Super Admin approval
    is_approved = 1 if role in ['user', 'superadmin'] else 0

    user_id = db.create_user(username, email, password, role, is_approved)
    if user_id:
        msg = 'Registration successful' if is_approved else 'Registration submitted. Awaiting Super Admin approval.'
        return jsonify({'success': True, 'message': msg, 'user_id': user_id}), 201
    return jsonify({'success': False, 'message': 'Registration failed'}), 500


@app.route('/api/login', methods=['POST'])
def login():
    """Authenticate user and return role + approval status."""
    data = request.get_json()
    if not data or 'username' not in data or 'password' not in data:
        return jsonify({'success': False, 'message': 'Missing credentials'}), 400

    user = db.authenticate_user(data['username'], data['password'])
    if not user:
        return jsonify({'success': False, 'message': 'Invalid username or password'}), 401

    if not user['is_approved']:
        return jsonify({'success': False, 'message': 'Account pending approval from Super Admin'}), 403

    return jsonify({
        'success': True,
        'message': 'Login successful',
        'user': {
            'id': user['id'],
            'username': user['username'],
            'email': user['email'],
            'role': user['role']
        }
    })


# ─── Super Admin Endpoints ─────────────────────────────────────────────────────

@app.route('/api/superadmin/pending-admins', methods=['GET'])
def get_pending_admins():
    """Get list of admin registrations awaiting approval."""
    pending = db.get_pending_admins()
    return jsonify({'success': True, 'pending': pending})


@app.route('/api/superadmin/approve/<int:user_id>', methods=['POST'])
def approve_admin(user_id):
    """Approve an admin registration."""
    result = db.approve_user(user_id)
    if result:
        user = db.get_user_by_id(user_id)
        if user:
            email_service.send_approval_notification(user['email'], user['username'])
        return jsonify({'success': True, 'message': 'Admin approved successfully'})
    return jsonify({'success': False, 'message': 'User not found'}), 404


@app.route('/api/superadmin/reject/<int:user_id>', methods=['DELETE'])
def reject_admin(user_id):
    """Reject and remove an admin registration."""
    result = db.delete_user(user_id)
    if result:
        return jsonify({'success': True, 'message': 'Admin registration rejected'})
    return jsonify({'success': False, 'message': 'User not found'}), 404


@app.route('/api/superadmin/users', methods=['GET'])
def get_all_users():
    """Get all users and admins."""
    users = db.get_all_users()
    return jsonify({'success': True, 'users': users})


@app.route('/api/superadmin/delete/<int:user_id>', methods=['DELETE'])
def delete_user(user_id):
    """Delete a user."""
    result = db.delete_user(user_id)
    if result:
        return jsonify({'success': True, 'message': 'User deleted successfully'})
    return jsonify({'success': False, 'message': 'User not found'}), 404


# ─── Detection & Logging Endpoints ────────────────────────────────────────────

@app.route('/api/log-alert', methods=['POST'])
def log_alert():
    """
    Log a detection alert. Accepts JSON with:
    - username, alert_type, timestamp
    - screenshot (base64 encoded image, optional)
    """
    data = request.get_json()
    if not data:
        return jsonify({'success': False, 'message': 'No data provided'}), 400

    username = data.get('username', 'unknown')
    alert_type = data.get('alert_type', 'Unknown Alert')
    timestamp = data.get('timestamp', datetime.now().isoformat())
    screenshot_b64 = data.get('screenshot')

    screenshot_path = None
    if screenshot_b64:
        screenshot_path = save_screenshot(screenshot_b64, username, timestamp)

    log_id = db.create_log(username, alert_type, timestamp, screenshot_path)

    # Notify admins/superadmins via email
    admins = db.get_approved_admins()
    user_data = db.get_user_by_username(username)
    user_email = user_data['email'] if user_data else None

    for admin in admins:
        email_service.send_alert_email(
            to_email=admin['email'],
            driver_name=username,
            alert_type=alert_type,
            timestamp=timestamp,
            screenshot_path=screenshot_path
        )

    return jsonify({
        'success': True,
        'message': 'Alert logged successfully',
        'log_id': log_id
    })


def save_screenshot(b64_data: str, username: str, timestamp: str) -> str:
    """Decode and save base64 screenshot to disk."""
    import base64
    try:
        clean = b64_data.split(',')[-1]  # strip data:image/jpeg;base64, prefix
        img_data = base64.b64decode(clean)
        safe_ts = timestamp.replace(':', '-').replace('.', '-')
        filename = f"{username}_{safe_ts}.jpg"
        filepath = os.path.join(SCREENSHOTS_DIR, filename)
        with open(filepath, 'wb') as f:
            f.write(img_data)
        return filepath
    except Exception as e:
        print(f"Screenshot save error: {e}")
        return None


# ─── Reports & Logs Endpoints ──────────────────────────────────────────────────

@app.route('/api/logs', methods=['GET'])
def get_logs():
    """Fetch all driver logs, optionally filtered by username."""
    username_filter = request.args.get('username')
    logs = db.get_logs(username_filter)
    return jsonify({'success': True, 'logs': logs})


@app.route('/api/reports/csv', methods=['GET'])
def download_csv():
    """Download driver logs as CSV."""
    username_filter = request.args.get('username')
    logs = db.get_logs(username_filter)

    output = io.StringIO()
    writer = csv.DictWriter(output, fieldnames=['id', 'username', 'status', 'timestamp', 'screenshot_path'])
    writer.writeheader()
    writer.writerows(logs)
    output.seek(0)

    return send_file(
        io.BytesIO(output.getvalue().encode()),
        mimetype='text/csv',
        as_attachment=True,
        download_name=f'driver_logs_{datetime.now().strftime("%Y%m%d_%H%M%S")}.csv'
    )


@app.route('/api/reports/pdf', methods=['GET'])
def download_pdf():
    """Download driver logs as PDF using reportlab."""
    try:
        from reportlab.lib.pagesizes import A4
        from reportlab.lib import colors
        from reportlab.platypus import SimpleDocTemplate, Table, TableStyle, Paragraph, Spacer
        from reportlab.lib.styles import getSampleStyleSheet

        username_filter = request.args.get('username')
        logs = db.get_logs(username_filter)

        buffer = io.BytesIO()
        doc = SimpleDocTemplate(buffer, pagesize=A4)
        styles = getSampleStyleSheet()
        elements = []

        elements.append(Paragraph('Driver Monitoring System - Incident Report', styles['Title']))
        elements.append(Paragraph(f'Generated: {datetime.now().strftime("%Y-%m-%d %H:%M:%S")}', styles['Normal']))
        elements.append(Spacer(1, 20))

        table_data = [['ID', 'Driver', 'Alert Type', 'Timestamp']]
        for log in logs:
            table_data.append([
                str(log.get('id', '')),
                log.get('username', ''),
                log.get('status', ''),
                log.get('timestamp', '')
            ])

        table = Table(table_data, colWidths=[40, 120, 180, 160])
        table.setStyle(TableStyle([
            ('BACKGROUND', (0, 0), (-1, 0), colors.HexColor('#1a1a2e')),
            ('TEXTCOLOR', (0, 0), (-1, 0), colors.white),
            ('FONTNAME', (0, 0), (-1, 0), 'Helvetica-Bold'),
            ('FONTSIZE', (0, 0), (-1, 0), 11),
            ('ROWBACKGROUNDS', (0, 1), (-1, -1), [colors.white, colors.HexColor('#f0f0f0')]),
            ('GRID', (0, 0), (-1, -1), 0.5, colors.grey),
            ('ALIGN', (0, 0), (-1, -1), 'CENTER'),
            ('VALIGN', (0, 0), (-1, -1), 'MIDDLE'),
            ('TOPPADDING', (0, 0), (-1, -1), 6),
            ('BOTTOMPADDING', (0, 0), (-1, -1), 6),
        ]))
        elements.append(table)
        doc.build(elements)
        buffer.seek(0)

        return send_file(
            buffer,
            mimetype='application/pdf',
            as_attachment=True,
            download_name=f'driver_report_{datetime.now().strftime("%Y%m%d_%H%M%S")}.pdf'
        )
    except ImportError:
        return jsonify({'success': False, 'message': 'reportlab not installed. Run: pip install reportlab'}), 500


@app.route('/api/stats', methods=['GET'])
def get_stats():
    """Get summary statistics for admin dashboard."""
    stats = db.get_stats()
    return jsonify({'success': True, 'stats': stats})


# ─── Screenshot Serving ────────────────────────────────────────────────────────

@app.route('/api/screenshot/<path:filename>', methods=['GET'])
def serve_screenshot(filename):
    filepath = os.path.join(SCREENSHOTS_DIR, filename)
    if os.path.exists(filepath):
        return send_file(filepath, mimetype='image/jpeg')
    return jsonify({'error': 'Screenshot not found'}), 404


# ─── Health Check ──────────────────────────────────────────────────────────────

@app.route('/api/health', methods=['GET'])
def health():
    return jsonify({'status': 'ok', 'timestamp': datetime.now().isoformat()})


if __name__ == '__main__':
    db.init_db()
    print("=" * 60)
    print("  Driver Monitoring System Backend")
    print("  Running on http://0.0.0.0:5000")
    print("=" * 60)
    app.run(host='0.0.0.0', port=5000, debug=True)
