import json,urllib.request,sys
RPC="https://rpc.soniclabs.com"
FACT="0x197d40B36677248E82939f96930bf4E7Fe8aD1c2"
PIN=hex(78400000)
def rpc_batch(calls):
    # calls: list of (to, data). returns list of hex results
    req=[{"jsonrpc":"2.0","id":i,"method":"eth_call","params":[{"to":to,"data":data},PIN]} for i,(to,data) in enumerate(calls)]
    out=[None]*len(calls)
    # chunk to avoid oversized
    CH=40
    for s in range(0,len(req),CH):
        chunk=req[s:s+CH]
        data=json.dumps(chunk).encode()
        r=urllib.request.Request(RPC,data=data,headers={"content-type":"application/json"})
        resp=json.loads(urllib.request.urlopen(r,timeout=60).read())
        for item in resp:
            out[item["id"]]= item.get("result")
    return out
def sel(sig):
    import hashlib
    # keccak needed; use pysha3? fallback to precomputed
    raise Exception("use precomputed")
# precomputed selectors
SEL={
 "getNumberOfVaults(uint8)":"0x", # not needed, we know 123
 "getVaultAt(uint8,uint256)":"0xa1s", 
}
# We'll compute selectors via eth_utils if available
try:
    from eth_utils import keccak
    def s4(sig): return "0x"+keccak(text=sig).hex()[:8]
except Exception:
    from Crypto.Hash import keccak as _k
    def s4(sig):
        h=_k.new(digest_bits=256); h.update(sig.encode()); return "0x"+h.hexdigest()[:8]
def enc_u(x): return hex(x)[2:].rjust(64,'0')
def enc_addr(a): return a.lower().replace("0x","").rjust(64,'0')

N=123
# 1) vault addresses
calls=[(FACT, s4("getVaultAt(uint8,uint256)")+enc_u(2)+enc_u(i)) for i in range(N)]
res=rpc_batch(calls)
vaults=["0x"+r[-40:] for r in res]
# 2) per vault: getTokenX, getTokenY, getOracleHelper, getBalances, totalSupply
def col(sig): return rpc_batch([(v, s4(sig)) for v in vaults])
tx=col("getTokenX()"); ty=col("getTokenY()"); oh=col("getOracleHelper()")
bal=col("getBalances()"); ts=col("totalSupply()")
def a(r): return "0x"+r[-40:]
def u(r,i=0): return int(r[2+i*64:2+(i+1)*64],16) if r and r!="0x" else 0
rows=[]
for i in range(N):
    rows.append({
      "i":i,"vault":vaults[i],"tokenX":a(tx[i]),"tokenY":a(ty[i]),
      "oh":a(oh[i]) if oh[i] and oh[i]!="0x" else None,
      "balX":u(bal[i],0) if bal[i] else 0,"balY":u(bal[i],1) if bal[i] else 0,
      "totalSupply":u(ts[i]) if ts[i] else 0
    })
# 3) oracle params per helper
ohs=[r["oh"] for r in rows]
opRes=rpc_batch([(o if o else FACT, s4("getOracleParameters()")) for o in ohs])
# struct: (minPrice,maxPrice,heartbeatX,heartbeatY,deviationThreshold,twapPriceCheckEnabled(bool),twapInterval)
for i,r in enumerate(rows):
    d=opRes[i]
    if r["oh"] and d and d!="0x" and len(d)>=2+7*64:
        r["deviation"]=int(d[2+4*64:2+5*64],16)
        r["twapEnabled"]=int(d[2+5*64:2+6*64],16)
        r["twapInterval"]=int(d[2+6*64:2+7*64],16)
    else:
        r["deviation"]=None;r["twapEnabled"]=None;r["twapInterval"]=None
json.dump(rows,open(sys.argv[1],"w"),indent=1)
print("wrote",len(rows),"rows")
# collect unique tokens for price fetch
toks=set()
for r in rows: toks.add(r["tokenX"].lower()); toks.add(r["tokenY"].lower())
open(sys.argv[2],"w").write("\n".join(sorted(toks)))
print("unique tokens:",len(toks))
