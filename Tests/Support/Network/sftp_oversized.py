"""Owned negative fixture: valid SFTP version, then oversized header without body."""
import struct,sys

def packet():
    header=sys.stdin.buffer.read(4)
    if len(header)!=4: raise SystemExit(0)
    length=struct.unpack('>I',header)[0]
    if length>65536: raise SystemExit(1)
    data=sys.stdin.buffer.read(length)
    if len(data)!=length: raise SystemExit(1)
    return data

if packet()[0]!=1: raise SystemExit(1)
sys.stdout.buffer.write(struct.pack('>IBI',5,2,3)); sys.stdout.buffer.flush()
packet()
sys.stdout.buffer.write(struct.pack('>I',32*1024*1024)); sys.stdout.buffer.flush()
while sys.stdin.buffer.read(65536): pass
