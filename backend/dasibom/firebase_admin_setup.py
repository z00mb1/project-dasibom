import os
import json

import firebase_admin
from firebase_admin import credentials


if not firebase_admin._apps:
    firebase_credentials_json = os.getenv("FIREBASE_CREDENTIALS_JSON")

    if firebase_credentials_json:
        # Render 등 배포 환경
        cred_dict = json.loads(firebase_credentials_json)
        cred = credentials.Certificate(cred_dict)
    else:
        # 로컬 개발 환경
        from pathlib import Path

        cred_path = (
            Path(__file__).resolve().parent
            / "dasibom-auth-firebase-adminsdk-fbsvc-eb3c4dd8c5.json"
        )
        cred = credentials.Certificate(str(cred_path))

    firebase_admin.initialize_app(cred)