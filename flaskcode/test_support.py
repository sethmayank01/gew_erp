from authentication import issue_token


def authenticated_client(app, username='test', role='admin'):
    client = app.test_client()
    client.environ_base['HTTP_AUTHORIZATION'] = 'Bearer ' + issue_token(app.config['SECRET_KEY'], username, role)
    return client
