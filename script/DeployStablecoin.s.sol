// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

import "forge-std/Script.sol";
import "openzeppelin-contracts/contracts/proxy/transparent/ProxyAdmin.sol";
import "openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import "../src/Stablecoin.sol";

contract DeployStablecoinScript is Script {
    string internal constant NAME = "First Digital USD";
    string internal constant SYMBOL = "FDUSD";

    function setUp() public {}

    function run() public {
        vm.startBroadcast();

        Stablecoin impl = new Stablecoin();
        ProxyAdmin proxyAdmin = new ProxyAdmin();
        TransparentUpgradeableProxy proxy = new TransparentUpgradeableProxy(
            address(impl),
            address(proxyAdmin),
            abi.encodeWithSignature("initialize(string,string)", NAME, SYMBOL)
        );

        vm.stopBroadcast();
    }
}
