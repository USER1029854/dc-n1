// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;
import "forge-std/Test.sol";

interface IERC20 { function balanceOf(address) external view returns (uint256); function transfer(address,uint256) external returns (bool);}
interface IWNative { function deposit() external payable; }
interface IVault {
    function previewShares(uint256,uint256) external view returns (uint256,uint256,uint256);
    function totalSupply() external view returns (uint256);
    function getStrategy() external view returns (address);
}
interface IStrategy { function getBalances() external view returns (uint256,uint256); }
interface IOracleHelper { function getPrice() external view returns (uint256); function checkPriceInDeviation() external view returns (bool);}
interface ILBPair { function getActiveId() external view returns (uint24); function swap(bool,address) external returns (bytes32);}

contract Probe2 is Test {
    address constant VAULT=0x6bE5a84D4A92269eC0Eb228B6c4dAdecED4C7D54;
    address constant PAIR=0x9eDE606c7168bb09fF73EbdE7bFD6FcfaBDA9Bc3;
    address constant WETH=0x50c42dEAcD8Fc9773493ED674b675bE577f2634b;
    address constant WS=0x039e2fB66102314Ce7b64Ce5Ce3E5183bc94aD38;
    address constant OH=0x01c871DfFC36eDC4dDf86FB4a9Bc690B3613a80f;
    IVault v=IVault(VAULT); ILBPair p=ILBPair(PAIR); IStrategy s; address atk=address(0xA11CE);

    function setUp() public { vm.createSelectFork("sonic", 78400000); s=IStrategy(v.getStrategy()); }

    function px() internal view returns(uint256){ return IOracleHelper(OH).getPrice(); }
    function guardOk() internal view returns(bool){ try IOracleHelper(OH).checkPriceInDeviation() returns(bool){return true;} catch {return false;} }
    function pvWeth() internal view returns(uint256 sh){ (sh,,)=v.previewShares(1e18,0); }
    function pvWs() internal view returns(uint256 sh){ (sh,,)=v.previewShares(0,81000e18); }

    function row(string memory t) internal {
        emit log_named_string("tag",t);
        emit log_named_uint("activeId",p.getActiveId());
        emit log_named_uint("getPrice_1e6", (px()*1e6)>>128);
        emit log_named_string("guardOk", guardOk()?"YES":"REVERT");
        emit log_named_uint("pShares_1WETH", pvWeth());
        emit log_named_uint("pShares_81kWS", pvWs());
    }
    function up(uint256 wsIn) internal { vm.deal(atk,wsIn); vm.startPrank(atk); IWNative(WS).deposit{value:wsIn}(); IERC20(WS).transfer(PAIR,wsIn); p.swap(false,atk); vm.stopPrank(); }
    function down(uint256 wethIn) internal { deal(WETH,atk,wethIn); vm.startPrank(atk); IERC20(WETH).transfer(PAIR,wethIn); p.swap(true,atk); vm.stopPrank(); }

    function testWindow() public {
        row("BASE");
        uint256[] memory u=new uint256[](7);
        u[0]=50_000e18;u[1]=150_000e18;u[2]=300_000e18;u[3]=600_000e18;u[4]=1_000_000e18;u[5]=1_500_000e18;u[6]=3_000_000e18;
        for(uint i=0;i<u.length;i++){uint256 sn=vm.snapshotState(); up(u[i]); row(string.concat("UP_",vm.toString(u[i]/1e18))); vm.revertToState(sn);}
        uint256[] memory d=new uint256[](7);
        d[0]=2e18;d[1]=5e18;d[2]=10e18;d[3]=20e18;d[4]=35e18;d[5]=50e18;d[6]=100e18;
        for(uint i=0;i<d.length;i++){uint256 sn=vm.snapshotState(); down(d[i]); row(string.concat("DOWN_",vm.toString(d[i]/1e18))); vm.revertToState(sn);}
    }
}
