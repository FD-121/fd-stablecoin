// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

import "forge-std/Script.sol";
import "openzeppelin-contracts/contracts/proxy/transparent/ProxyAdmin.sol";
import "openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import "../src/StablecoinV2.sol";

contract UpgradeStablecoinScript is Script {
    string internal constant NAME = "First Digital USD";
    string internal constant SYMBOL = "FDUSD";

    function setUp() public {}

    address constant PROXY_ADMIN = 0xc3EFAB880544C890ebee5B727f93eaC60DD9AB34;
    address constant PROXY = 0xa19C9FB1A377621dFd1401EF160d802A14d0C91F;

    function run() external {
        vm.startBroadcast();

         // 1️⃣ 部署新的逻辑合约
        StablecoinV2 newImpl = new StablecoinV2();
        console.log("New Implementation:", address(newImpl));

        // 2️⃣ 构造 initializeV2 的 calldata
        bytes memory initData = abi.encodeWithSelector(
            StablecoinV2.initializeV2.selector,
            NAME
        );
        console.logBytes(initData);

        // 3️⃣ 调用 upgradeAndCall
        // ProxyAdmin admin = ProxyAdmin(PROXY_ADMIN);
        // TransparentUpgradeableProxy proxyInstance = TransparentUpgradeableProxy(payable(PROXY));
        // admin.upgradeAndCall(proxyInstance, address(newImpl), initData);

        vm.stopBroadcast();
    }
}
