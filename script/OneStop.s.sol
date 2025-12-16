// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

import "forge-std/Script.sol";
import "openzeppelin-contracts/contracts/proxy/transparent/ProxyAdmin.sol";
import "openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import "../src/Stablecoin.sol";
import "../src/StablecoinV2.sol";

contract OneStopScript is Script {
    string internal constant NAME = "First Digital USD";
    string internal constant SYMBOL = "FDUSD";
    address internal constant OWNER = 0xBB9da27B30Bc2e6299C5d7044C4b5FE95E01D43c;

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
        impl.initialize(NAME, SYMBOL); // prevent uninitialized implementation
        
        bytes memory initData = abi.encodeWithSelector(
            StablecoinV2.initializeV2.selector,
            NAME
        );

        StablecoinV2 newImpl = new StablecoinV2();
        proxyAdmin.upgradeAndCall(proxy, address(newImpl), initData);

        proxyAdmin.transferOwnership(OWNER);
        StablecoinV2(address(proxy)).transferOwnership(OWNER);

        StablecoinV2(address(proxy)).mint(OWNER,1000000000000000000000000);
        vm.stopPrank();

        vm.stopBroadcast();
    }
}
