// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

import "../../src/StablecoinV2.sol";

contract MockERC20 is StablecoinV2 {
    constructor() {
        initialize("Mock Token", "MOCK");
    }
}
