// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./StablecoinV2.sol";

/**
 * @title StablecoinV3
 * @dev Adds frozen funds recovery to StablecoinV2.
 *
 * Upgrade notes:
 * - No new state variables. The storage layout is identical to StablecoinV2.
 * - No initializer. The upgrade is a plain `ProxyAdmin.upgrade(proxy, implementation)`.
 */
contract StablecoinV3 is StablecoinV2 {

    event FrozenFundsRecovered(address indexed caller, address indexed account, uint256 amount);

    /**
     * @dev Moves `amount` tokens from a frozen `account` to the current owner.
     *
     * The tokens are moved, not burned and re-minted, so total supply does not change.
     * The destination is always the owner and cannot be chosen by the caller. Any onward
     * transfer is a separate, ordinary transfer by the owner.
     *
     * Requirements:
     * - the caller is the owner
     * - the contract is not paused
     * - `account` is frozen
     * - the owner is not frozen, so the recovered tokens are never stuck
     * - `amount` is greater than zero and not more than the balance of `account`
     *
     * `account` stays frozen. Its allowances and authorization nonces are not changed.
     *
     * @param account Frozen account to recover from
     * @param amount Amount to recover
     */
    function recoverFrozenFunds(address account, uint256 amount) external onlyOwner whenNotPaused {
        require(frozen[account], "Account is not frozen");
        require(amount > 0, "Amount is zero");

        address recipient = owner();
        require(!frozen[recipient], "Owner is frozen");

        // Call the ERC20 base transfer directly. The override in Stablecoin would reject
        // a frozen source. All checks that override makes are repeated above, except the
        // one on the source, which is inverted on purpose.
        ERC20Upgradeable._transfer(account, recipient, amount);

        emit FrozenFundsRecovered(_msgSender(), account, amount);
    }
}
