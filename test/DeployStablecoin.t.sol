// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "openzeppelin-contracts/contracts/proxy/transparent/ProxyAdmin.sol";
import "openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import "../src/StablecoinV2.sol";

contract DeployStablecoinTest is Test {

    string internal constant NAME = "First Digital USD";
    string internal constant SYMBOL = "FDUSD";
    uint256 internal ownerPrivateKey;
    address internal owner;
    Stablecoin internal impl;
    Stablecoin internal newImpl;
    ProxyAdmin internal proxyAdmin;
    TransparentUpgradeableProxy internal proxy;

    function setUp() public {
        ownerPrivateKey = 0xA11CE;
        owner = vm.addr(ownerPrivateKey);

        deployAndUpgradeSmartContract();
    }

    function deployAndUpgradeSmartContract() internal {
        vm.startPrank(owner);

        impl = new Stablecoin();
        proxyAdmin = new ProxyAdmin();
        proxy = new TransparentUpgradeableProxy(
            address(impl),
            address(proxyAdmin),
            abi.encodeWithSignature("initialize(string,string)", NAME, SYMBOL)
        );

        newImpl = new StablecoinV2();
        console.log("New Implementation:", address(newImpl));

        bytes memory initData = abi.encodeWithSelector(
            StablecoinV2.initializeV2.selector,
            NAME
        );

        proxyAdmin.upgradeAndCall(proxy, address(newImpl), initData);

        vm.stopPrank();
    }

    function test_Initialize() public {
        assertEq(proxyAdmin.owner(), owner);
        assertEq(proxyAdmin.getProxyAdmin(proxy), address(proxyAdmin));
        assertEq(proxyAdmin.getProxyImplementation(proxy), address(newImpl));
        assertEq(keccak256(abi.encodePacked(Stablecoin(address(proxy)).name())), keccak256(abi.encodePacked(NAME)));
        assertEq(keccak256(abi.encodePacked(Stablecoin(address(proxy)).symbol())), keccak256(abi.encodePacked(SYMBOL)));
        assertEq(keccak256(abi.encodePacked(newImpl.name())), keccak256(abi.encodePacked("")));
        assertEq(keccak256(abi.encodePacked(newImpl.symbol())), keccak256(abi.encodePacked("")));
    }
}
