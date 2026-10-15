"""EA RefPack (QFS) decompressor.

Used by NFS5 .crp files (magic 0x10FB). Usage:
    python3 tools/refpack.py sources/GameData/CarModel/356a.crp decomposed/GameData/CarModel/356a.bin
"""
import sys
def decompress(d):
    p=0
    flags=(d[0]<<8)|d[1]; p=2
    if flags&0x0100: p+=3
    size=(d[p]<<16)|(d[p+1]<<8)|d[p+2]; p+=3
    out=bytearray()
    while p<len(d):
        b0=d[p]
        if b0<0x80:
            b1=d[p+1]; p+=2
            lit=b0&3; out+=d[p:p+lit]; p+=lit
            ln=((b0&0x1c)>>2)+3; off=((b0&0x60)<<3)+b1+1
        elif b0<0xC0:
            b1,b2=d[p+1],d[p+2]; p+=3
            lit=b1>>6; out+=d[p:p+lit]; p+=lit
            ln=(b0&0x3f)+4; off=((b1&0x3f)<<8)+b2+1
        elif b0<0xE0:
            b1,b2,b3=d[p+1],d[p+2],d[p+3]; p+=4
            lit=b0&3; out+=d[p:p+lit]; p+=lit
            ln=((b0&0x0c)<<6)+b3+5; off=((b0&0x10)<<12)+(b1<<8)+b2+1
        elif b0<0xFC:
            p+=1; lit=((b0&0x1f)<<2)+4; out+=d[p:p+lit]; p+=lit; continue
        else:
            p+=1; lit=b0&3; out+=d[p:p+lit]; p+=lit; break
        for _ in range(ln): out.append(out[-off])
    return bytes(out),size
if __name__=='__main__':
    import os
    os.makedirs(os.path.dirname(os.path.abspath(sys.argv[2])), exist_ok=True)
    d=open(sys.argv[1],'rb').read()
    o,s=decompress(d)
    open(sys.argv[2],'wb').write(o)
    print(sys.argv[1],'declared',s,'got',len(o),'OK' if s==len(o) else 'MISMATCH')
