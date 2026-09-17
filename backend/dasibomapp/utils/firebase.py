from firebase_admin import auth

def verify_firebase_token(id_token):
    """
    Firebase ID Token 검증
    """
    try:
        decoded_token = auth.verify_id_token(id_token)
        return decoded_token
    except Exception:
        return None
