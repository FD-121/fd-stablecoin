// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/**
 * @dev Interface of the ERC1271 standard signature validation method for contracts.
 * @notice This interface is used to validate signatures from smart contract wallets.
 */
interface IERC1271 {
    /**
     * @dev Should return whether the signature provided is valid for the provided data
     * @param hash      Hash of the data to be signed
     * @param signature Signature byte array associated with _data
     * @return magicValue The bytes4 magic value 0x1626ba7e if valid, otherwise 0xffffffff
     */
    function isValidSignature(bytes32 hash, bytes memory signature) external view returns (bytes4 magicValue);
}
