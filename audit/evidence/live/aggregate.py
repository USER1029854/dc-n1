import json,urllib.request
RPC="https://rpc.soniclabs.com"; PIN=hex(78400000)
from eth_utils import keccak
def s4(sig): return "0x"+keccak(text=sig).hex()[:8]
def batch(calls):
    req=[{"jsonrpc":"2.0","id":i,"method":"eth_call","params":[{"to":to,"data":data},PIN]} for i,(to,data) in enumerate(calls)]
    data=json.dumps(req).encode()
    r=urllib.request.Request(RPC,data=data,headers={"content-type":"application/json"})
    resp=json.loads(urllib.request.urlopen(r,timeout=60).read())
    out=[None]*len(calls)
    for it in resp: out[it["id"]]=it.get("result")
    return out
rows=json.load(open("audit/live/fleet.json"))
prices={k.split(":")[1].lower():v["price"] for k,v in json.load(open("audit/reference/fleet_prices.json"))["coins"].items()}
toks=[t.strip() for t in open("audit/live/fleet_tokens.txt")]
dec=batch([(t,s4("decimals()")) for t in toks])
decs={toks[i].lower():int(dec[i],16) if dec[i] and dec[i]!="0x" else 18 for i in range(len(toks))}
def val(tok,amt):
    tok=tok.lower(); p=prices.get(tok,0.0); d=decs.get(tok,18)
    return amt/(10**d)*p
tot=0.0
for r in rows:
    r["tvlUSD"]=val(r["tokenX"],r["balX"])+val(r["tokenY"],r["balY"])
    tot+=r["tvlUSD"]
rows.sort(key=lambda r:-r["tvlUSD"])
print(f"TOTAL fleet TVL (123 oracle vaults): ${tot:,.0f}\n")
# guard config summary
from collections import Counter
gc=Counter((r["twapEnabled"],r["deviation"],r["twapInterval"]) for r in rows)
print("guard config (twapEnabled,deviation,twapInterval) -> count:")
for k,c in gc.most_common(): print("  ",k,"->",c)
print("\nTop 20 vaults by TVL:")
print(f'{"#":>3} {"vault":42} {"tokX/tokY":20} {"TVL$":>12} {"twapEn":>6} {"dev":>4} {"twapI":>6}')
def sym(a):
    m={ "0x50c42deacd8fc9773493ed674b675be577f2634b":"WETH","0x039e2fb66102314ce7b64ce5ce3e5183bc94ad38":"wS",
        "0x0555e30da8f98308edb960aa94c0db47230d2b9c":"WBTC","0x29219dd400f2bf60e5a23d13be72b486d4038894":"USDC",
        "0x6047828dc181963ba44974801ff68e538da5eaf9":"USDT","0x80eede496655fb9047dd39d9f418d5483ed600df":"frxUSD",
        "0xb1e25689d55734fd3fffc939c4c3eb52dff8a794":"OS","0xd3dce716f3ef535c5ff8d041c1a41c3bd89b97ae":"scUSD",
        "0xe5da20f15420ad15de0fa650600afc998bbe3955":"stS","0xe715cba7b5ccb33790cebff1436809d36cb17e57":"EURC.e",
        "0x000000000eccff26b795f73fb0a70d48da657fef":"USSD","0xb026e4cc9025fa72e7fd68b93c08eea0948269fd":"???"}
    return m.get(a.lower(),a[:8])
for r in rows[:20]:
    print(f'{r["i"]:>3} {r["vault"]:42} {sym(r["tokenX"])+"/"+sym(r["tokenY"]):20} {r["tvlUSD"]:>12,.0f} {str(r["twapEnabled"]):>6} {str(r["deviation"]):>4} {str(r["twapInterval"]):>6}')
json.dump(rows,open("audit/live/fleet_valued.json","w"),indent=1)
# at-risk: guarded vaults ~ up to dev/2 % (conservative), unguarded flagged
def atrisk(r):
    if r["twapEnabled"]==1 and r["deviation"]:
        return r["tvlUSD"]*min(r["deviation"],10)/100.0/2.0  # ~half the band as achievable inflation
    else:
        return r["tvlUSD"]*0.05  # unguarded: still bounded, use 5% placeholder
ar=sum(atrisk(r) for r in rows)
print(f"\nRough aggregate at-risk (share-inflation extractable, guarded~dev/2, unguarded~5%): ${ar:,.0f}")
nun=sum(1 for r in rows if not (r["twapEnabled"]==1))
print(f"vaults with twap guard DISABLED or unset: {nun}")
print(f"vaults with TVL >= $10k: {sum(1 for r in rows if r['tvlUSD']>=10000)}")
print(f"vaults with TVL >= $100k: {sum(1 for r in rows if r['tvlUSD']>=100000)}")
