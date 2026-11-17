"""Short-lived, server-signed API credentials; no client-supplied role is trusted."""
from itsdangerous import BadSignature, SignatureExpired, URLSafeTimedSerializer


class AuthenticationError(ValueError):
    pass


def issue_token(secret, username, role):
    return URLSafeTimedSerializer(secret, salt='gew-erp-login').dumps({
        'username': username, 'role': role.lower(),
    })


def verify_token(secret, authorization, max_age=3600):
    if not authorization or not authorization.startswith('Bearer '):
        raise AuthenticationError('Please log in again')
    try:
        user = URLSafeTimedSerializer(secret, salt='gew-erp-login').loads(
            authorization[7:], max_age=max_age,
        )
    except (BadSignature, SignatureExpired):
        raise AuthenticationError('Login expired or invalid; please log in again')
    if not isinstance(user, dict) or not user.get('username') or not user.get('role'):
        raise AuthenticationError('Invalid login credentials')
    return user
