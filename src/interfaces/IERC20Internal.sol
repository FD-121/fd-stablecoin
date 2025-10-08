// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/**
 * @dev Interface exposing internal ERC20 transfer function.
 * @notice Used by EIP-7598 extension to access internal _transfer function.
 */
interface IERC20Internal {
    /**
     * @dev Internal transfer function that can be called by extensions
     * @param from Source address
     * @param to Destination address
     * @param amount Transfer amount
     */
    function executeTransfer(address from, address to, uint256 amount) external;
}
