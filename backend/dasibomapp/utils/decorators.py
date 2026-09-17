from rest_framework.response import Response
from functools import wraps
from .firebase import verify_firebase_token

def firebase_login_required(func):
    @wraps(func)
    def wrapper(self, request, *args, **kwargs):
        auth_header = request.headers.get("Authorization")

        if not auth_header:
            return Response({"error": "Authorization header missing"}, status=401)

        id_token = auth_header.replace("Bearer ", "").strip()
        decoded = verify_firebase_token(id_token)

        if not decoded:
            return Response({"error": "Invalid Firebase token"}, status=403)

        request.firebase_user = decoded
        return func(self, request, *args, **kwargs)

    return wrapper
