"""Read-only deployment smoke checks; never prints credentials or record contents."""
import json
import os
import sys
import urllib.error
import urllib.request

sys.path.insert(0, os.path.abspath('flaskcode'))
from authentication import issue_token


def fetch(path, token=None):
    headers = {'Authorization': 'Bearer ' + token} if token else {}
    try:
        with urllib.request.urlopen(urllib.request.Request(
            'http://127.0.0.1:5005' + path, headers=headers,
        ), timeout=15) as response:
            return response.status, json.load(response)
    except urllib.error.HTTPError as error:
        return error.code, json.load(error)


status, health = fetch('/health')
assert status == 200 and health.get('version') == '1.2.10', 'Wrong backend version'
assert fetch('/jobs')[0] == 401, 'Unauthenticated data access was allowed'
assert fetch('/jobs', 'invalid')[0] == 401, 'Invalid credential was allowed'
token = issue_token(os.environ['GEW_ERP_SECRET_KEY'], 'deployment-read-check', 'user')
status, jobs = fetch('/jobs', token)
assert status == 200 and isinstance(jobs, list), 'Authenticated job read failed'
assert fetch('/users', token)[0] == 403, 'Non-admin user accessed account management'
print('Backend 1.2.10: health, authenticated read, and authorization checks passed')
