import json,logging,secrets,socket,sys,os,time,threading
from pathlib import Path
from impacket.smbserver import SimpleSMBServer
from impacket import smb3structs
from impacket.nt_errors import STATUS_SUCCESS,STATUS_PRIVILEGE_NOT_HELD
from impacket.ntlm import compute_lmhash,compute_nthash
logging.disable(logging.CRITICAL)
root=Path(sys.argv[1]); (root/'data').mkdir(exist_ok=True)
(root/'data'/'hello #中文.txt').write_text('owned SMB fixture')
with socket.socket() as sock:
    sock.bind(('127.0.0.1',0)); port=sock.getsockname()[1]
username='commander'; secret='owned disposable native fixture' if os.environ.get('COMMANDER_SMB_NATIVE') == '1' else secrets.token_urlsafe(24)
server=SimpleSMBServer(listenAddress='127.0.0.1',listenPort=port)
server.setSMB2Support(True)
# Impacket 0.13.1 returns a normal CREATE body for some failed requests.
# Emit the SMB2 error body required by the protocol, not a relaxed client parser.
def proper_errors(original):
    def handler(*args):
        if (root/'drop-next-command').exists():
            (root/'drop-next-command').unlink()
            raise ConnectionResetError('Owned fixture intentionally closed this session')
        if (root/'deny-next-command').exists():
            (root/'deny-next-command').unlink()
            return [smb3structs.SMB2Error()], None, STATUS_PRIVILEGE_NOT_HELD
        commands, packets, status = original(*args)
        if status != STATUS_SUCCESS and packets is None:
            return [smb3structs.SMB2Error()], None, status
        return commands, packets, status
    return handler
inner=server.getServer()
for command in range(2, 19):
    original=inner.hookSmb2Command(command,None)
    if original is not None: inner.hookSmb2Command(command,proper_errors(original))
query_lock=threading.Lock(); query_count=0
original_query=inner.hookSmb2Command(14,None)
def counted_query(*args):
    global query_count
    with query_lock:
        query_count += 1; (root/'query-count').write_text(str(query_count))
    if (root/'stall-query').exists(): time.sleep(15)
    return original_query(*args)
inner.hookSmb2Command(14,counted_query)
server.addShare('OwnedShare',str(root/'data'),'Owned Commander4Mac fixture')
server.addCredential(username,0,compute_lmhash(secret),compute_nthash(secret))
(root/'fixture.json').write_text(json.dumps({'port':port,'username':username,'secret':secret}))
(root/'fixture.json').chmod(0o600)
(root/'server.pid').write_text(str(os.getpid()))
server.start()
