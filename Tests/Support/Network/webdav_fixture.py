import json,logging,secrets,socket,sys,os,time,threading,subprocess
from cheroot.ssl.builtin import BuiltinSSLAdapter
from pathlib import Path
from wsgidav.wsgidav_app import WsgiDAVApp
from cheroot.wsgi import Server
logging.disable(logging.CRITICAL)
root=Path(sys.argv[1]); data=root/'data'; data.mkdir(exist_ok=True)
(data/'hello #中文.txt').write_text('owned WebDAV fixture')
(data/'stall.bin').write_bytes(b'x'*200000)
secret='owned disposable native fixture' if os.environ.get('COMMANDER_DAV_NATIVE') == '1' else secrets.token_urlsafe(24)
config={'provider_mapping':{'/dav':str(data)},'simple_dc':{'user_mapping':{'*':{'commander':{'password':secret}}}},'http_authenticator':{'accept_basic':True,'accept_digest':True,'default_to_digest':os.environ.get('COMMANDER_DAV_BASIC') != '1'},'verbose':0,'logging':{'enable':False},'dir_browser':{'enable':False}}
app=WsgiDAVApp(config)
def wrapper(env,start):
    path=env.get('PATH_INFO',''); method=env.get('REQUEST_METHOD')
    if path.startswith('/dav/denied'):
        start('403 Forbidden',[('Content-Length','0')]); return [b'']
    if path.startswith('/dav/redirect'):
        start('302 Found',[('Location','http://127.0.0.1:9/credential-trap'),('Content-Length','0')]); return [b'']
    if path.startswith('/dav/partial') and method in ['MOVE','MKCOL','PUT']:
        body=b'<d:multistatus xmlns:d="DAV:"/>'; start('207 Multi-Status',[('Content-Length',str(len(body)))]); return [body]
    if path.startswith('/dav/oversize'):
        body=b' ' * 8388609; start('207 Multi-Status',[('Content-Length',str(len(body)))]); return [body]
    if path == '/dav/stall.bin' and method == 'GET':
        start('200 OK',[('Content-Length','200000')])
        def stalled():
            yield b'x'; time.sleep(15); yield b'x'*199999
        return stalled()
    return app(env,start)
with socket.socket() as sock:
    sock.bind(('127.0.0.1',0)); port=sock.getsockname()[1]
with socket.socket() as sock:
    sock.bind(('127.0.0.1',0)); tls_port=sock.getsockname()[1]
subprocess.run(['/usr/bin/openssl','req','-x509','-newkey','rsa:2048','-nodes','-days','1','-subj','/CN=127.0.0.1','-addext','subjectAltName=IP:127.0.0.1','-keyout',str(root/'tls-key.pem'),'-out',str(root/'tls-cert.pem')],check=True,stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
(root/'tls-key.pem').chmod(0o600)
tls_server=Server(('127.0.0.1',tls_port),wrapper,numthreads=2); tls_server.ssl_adapter=BuiltinSSLAdapter(str(root/'tls-cert.pem'),str(root/'tls-key.pem'),None)
threading.Thread(target=tls_server.start,daemon=True).start()
(root/'fixture.json').write_text(json.dumps({'port':port,'tls_port':tls_port,'username':'commander','secret':secret})); (root/'fixture.json').chmod(0o600)
Server(('127.0.0.1',port),wrapper,numthreads=8).start()
