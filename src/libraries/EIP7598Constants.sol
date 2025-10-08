// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/**
 * @title EIP7598Constants
 * @notice Constants for EIP-7598 (Transferable ERC-20 Permit)
 */
library EIP7598Constants {
    /**
     * @dev EIP-712 typehash for transferWithAuthorization
     * keccak256("TransferWithAuthorization(address from,address to,uint256 value,uint256 validAfter,uint256 validBefore,bytes32 nonce)")
     */
    bytes32 internal constant TRANSFER_WITH_AUTHORIZATION_TYPEHASH =
        0x7c7c6cdb67a18743f49ec6fa9b35f50d52ed05cbed4cc592e13b44501c1a2267;

    /**
     * @dev EIP-1271 magic value for valid signature
     * bytes4(keccak256("isValidSignature(bytes32,bytes)"))
     */
    bytes4 internal constant ERC1271_MAGIC_VALUE = 0x1626ba7e;

    /**
     * @dev EIP-7598 interface ID
     */
    bytes4 internal constant EIP7598_INTERFACE_ID = 0x00000000; // Placeholder - update when standardized
}
