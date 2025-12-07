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
     * @dev EIP-712 typehash for receiveWithAuthorization
     * keccak256("ReceiveWithAuthorization(address from,address to,uint256 value,uint256 validAfter,uint256 validBefore,bytes32 nonce)")
     */
    bytes32 internal constant RECEIVE_WITH_AUTHORIZATION_TYPEHASH =
        0xd099cc98ef71107a616c4f0f941f04c322d8e254fe26b3c6668db87aae413de8;    
}
