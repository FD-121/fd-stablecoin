// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

import "forge-std/Script.sol";
import "openzeppelin-contracts/contracts/proxy/transparent/ProxyAdmin.sol";
import "openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import "../src/StablecoinV2.sol";

contract DeployStablecoinScript is Script {
    string internal constant NAME = "$ Token";
    string internal constant SYMBOL = "$";

    function setUp() public {}

    function run() public {
        vm.startBroadcast();

        StablecoinV2 impl = new StablecoinV2();
        ProxyAdmin proxyAdmin = new ProxyAdmin();
        TransparentUpgradeableProxy proxy = new TransparentUpgradeableProxy(
            address(impl),
            address(proxyAdmin),
            abi.encodeWithSignature("initialize(string,string)", NAME, SYMBOL)
        );
        impl.initialize(NAME, SYMBOL); // prevent uninitialized implementation

        vm.stopBroadcast();
    }
}
