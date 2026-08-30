#!/usr/bin/env bash
# Re-runnable commands for the Metropolis DLMM vaults (Sonic) re-audit.
set -e
export SONIC_RPC="https://rpc.soniclabs.com"
export ETHERSCAN_API_KEY="<etherscan v2 key>"   # chainid=146
PIN=78400000
VAULT=0x6bE5a84D4A92269eC0Eb228B6c4dAdecED4C7D54
PAIR=0x9eDE606c7168bb09fF73EbdE7bFD6FcfaBDA9Bc3
OH=0x01c871DfFC36eDC4dDf86FB4a9Bc690B3613a80f
LENS=0x189F3FAEE49F744b76dC0B2549a20146E836aa37

# --- deployment recovery ---
# vault clone -> impl (OracleRewardVault, verified) and immutable args (pair, tokenX=WETH, tokenY=wS, oracleX/Y, oracleHelper)
cast code --block $PIN $VAULT
# verified impls fetched via Etherscan V2 getsourcecode (chainid=146):
#   OracleRewardVault 0xe19b636a6abee9c14eabb3f64e30c3304859bdb7
#   VaultFactory impl 0x920b7adf83423283c2d1291cbf3d44dd56a80636 (contains OracleHelper.sol)
#   Strategy impl     0x1817134ad98b72a42ab68cc485fb123afac85e80
#   DexLens impl      0xe640b1ad57fdadf8aa60d715a455b40eb374d90b (lens proxy 0x189F...aa37)

# --- key live reads at pin ---
cast call --block $PIN $VAULT   "getStrategy()(address)"
cast call --block $PIN $OH      "getPrice()(uint256)"                 # 128.128 WETH-in-wS (DexLens spot)
cast call --block $PIN $OH      "getOracleParameters()((uint256,uint256,uint24,uint24,uint256,bool,uint40))"  # dev=5,twapEnabled=true,twap=120
cast call --block $PIN $LENS    "getDataFeeds(address)((address,address,uint88,uint8)[])" 0x50c42dEAcD8Fc9773493ED674b675bE577f2634b  # WETH -> [] (spot fallback)

# --- fork PoC (proves the corrected mechanism + ~$570 net) ---
cd fork && forge test --mc PoC --mt testPoC -vv          # documented single run
forge test --mc Attack  --mt testGrid          -vv        # profit grid
forge test --mc Attack2 --mt testAsymptoteUp   -vv        # profit asymptote (cap)
forge test --mc Probe2  --mt testWindow        -vv        # oracle move vs guard pass/fail

# --- fleet enumeration (123 oracle vaults, batched JSON-RPC) ---
python3 ../../fleet_enum.py fleet.json fleet_tokens.txt && python3 ../../aggregate.py
