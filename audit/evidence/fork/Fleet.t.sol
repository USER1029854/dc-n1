// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;
import "forge-std/Test.sol";
interface IERC20 { function symbol() external view returns(string memory); function decimals() external view returns(uint8);}
interface IFactory { function getNumberOfVaults(uint8) external view returns(uint256); function getVaultAt(uint8,uint256) external view returns(address);}
interface IVault {
    function getStrategy() external view returns(address);
    function getBalances() external view returns(uint256,uint256);
    function totalSupply() external view returns(uint256);
    function getOracleHelper() external view returns(address);
    function getTokenX() external view returns(address);
    function getTokenY() external view returns(address);
}
interface IOH { function getPrice() external view returns(uint256); function getOracleParameters() external view returns(uint256,uint256,uint24,uint24,uint256,bool,uint40);}

contract Fleet is Test {
    address constant FACT=0x197d40B36677248E82939f96930bf4E7Fe8aD1c2;
    function setUp() public { vm.createSelectFork("sonic",78400000); }
    function testEnum() public {
        IFactory f=IFactory(FACT);
        uint256 n=f.getNumberOfVaults(2);
        emit log_named_uint("numOracleVaults",n);
        for(uint256 i=0;i<n;i++){
            address vault=f.getVaultAt(2,i);
            (uint256 bx,uint256 by)=(0,0); uint256 price=0; address tx_;address ty; bool twapEn=false; uint256 dev=0; uint40 twi=0; address oh;
            try IVault(vault).getBalances() returns(uint256 a,uint256 b){bx=a;by=b;}catch{}
            try IVault(vault).getTokenX() returns(address a){tx_=a;}catch{}
            try IVault(vault).getTokenY() returns(address a){ty=a;}catch{}
            try IVault(vault).getOracleHelper() returns(address a){oh=a;}catch{}
            if(oh!=address(0)){
                
                try IOH(oh).getOracleParameters() returns(uint256,uint256,uint24,uint24,uint256 d,bool e,uint40 t){dev=d;twapEn=e;twi=t;}catch{}
            }
            // one CSV-ish line
            emit log_string(string.concat(
                "ROW|",vm.toString(i),"|",vm.toString(vault),"|",vm.toString(tx_),"|",vm.toString(ty),
                "|",vm.toString(bx),"|",vm.toString(by),"|",vm.toString(price),
                "|",twapEn?"1":"0","|",vm.toString(dev),"|",vm.toString(uint256(twi))
            ));
        }
    }
}
