// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "openzeppelin-contracts-upgradeable/contracts/token/ERC20/ERC20Upgradeable.sol";
import "openzeppelin-contracts-upgradeable/contracts/utils/cryptography/draft-EIP712Upgradeable.sol";
import "openzeppelin-contracts-upgradeable/contracts/utils/cryptography/ECDSAUpgradeable.sol";
import "../interfaces/IERC1271.sol";
import "../interfaces/IERC20Internal.sol";
import "../libraries/EIP7598Constants.sol";

/**
 * @title EIP7598Extension
 * @notice Implementation of EIP-7598 (Transferable ERC-20 Permit) compatible with OpenZeppelin v4.8.1
 * @dev This extension adds gasless transfer capabilities with authorization signatures
 */
abstract contract EIP7598Extension is ERC20Upgradeable, EIP712Upgradeable, IERC20Internal {
    using ECDSAUpgradeable for bytes32;

    // State variable for tracking used authorization nonces
    // This uses bytes32 nonces to allow for flexible nonce strategies
    mapping(address => mapping(bytes32 => bool)) private _authorizationStates;

    // Events
    event AuthorizationUsed(address indexed authorizer, bytes32 indexed nonce);
    event AuthorizationCanceled(address indexed authorizer, bytes32 indexed nonce);

    /**
     * @dev Check if an authorization has been used
     * @param authorizer Address that provided the authorization
     * @param nonce Nonce of the authorization
     * @return True if the authorization has been used
     */
    function authorizationState(address authorizer, bytes32 nonce) external view returns (bool) {
        return _authorizationStates[authorizer][nonce];
    }

    /**
     * @dev Execute a transfer with an authorization signature (EIP-7598)
     * @param from Payer's address (Authorizer)
     * @param to Payee's address
     * @param value Amount to transfer
     * @param validAfter The time after which this is valid (unix time)
     * @param validBefore The time before which this is valid (unix time)
     * @param nonce Unique nonce for this authorization
     * @param signature Signature bytes (EOA signature or EIP-1271 contract signature)
     */
    function transferWithAuthorization(
        address from,
        address to,
        uint256 value,
        uint256 validAfter,
        uint256 validBefore,
        bytes32 nonce,
        bytes memory signature
    ) external {
        // Validate time window
        require(block.timestamp > validAfter, "Authorization not yet valid");
        require(block.timestamp < validBefore, "Authorization expired");

        // Validate nonce
        require(!_authorizationStates[from][nonce], "Authorization already used");

        // Build EIP-712 struct hash
        bytes32 structHash = keccak256(
            abi.encode(
                EIP7598Constants.TRANSFER_WITH_AUTHORIZATION_TYPEHASH,
                from,
                to,
                value,
                validAfter,
                validBefore,
                nonce
            )
        );

        // Build EIP-712 digest
        bytes32 digest = _hashTypedDataV4(structHash);

        // Validate signature (supports both EOA and EIP-1271 smart contracts)
        _validateSignature(from, digest, signature);

        // Mark authorization as used
        _authorizationStates[from][nonce] = true;
        emit AuthorizationUsed(from, nonce);

        // Execute the transfer
        _transfer(from, to, value);
    }

    /**
     * @dev Cancel an authorization before it's used
     * @param authorizer Address that provided the authorization (must be msg.sender)
     * @param nonce Nonce of the authorization to cancel
     */
    function cancelAuthorization(address authorizer, bytes32 nonce) external {
        require(msg.sender == authorizer, "Caller must be the authorizer");
        require(!_authorizationStates[authorizer][nonce], "Authorization already used");

        _authorizationStates[authorizer][nonce] = true;
        emit AuthorizationCanceled(authorizer, nonce);
    }

    /**
     * @dev Validate a signature for an authorization
     * @param signer Expected signer address
     * @param digest EIP-712 digest to validate
     * @param signature Signature bytes
     */
    function _validateSignature(address signer, bytes32 digest, bytes memory signature) internal view {
        // Try ECDSA recovery first (for EOA signatures)
        address recovered = digest.recover(signature);

        if (recovered == signer) {
            // Valid EOA signature
            return;
        }

        // If ECDSA recovery didn't match, try EIP-1271 (for smart contract signatures)
        // Check if the signer is a contract
        if (_isContract(signer)) {
            try IERC1271(signer).isValidSignature(digest, signature) returns (bytes4 magicValue) {
                require(
                    magicValue == EIP7598Constants.ERC1271_MAGIC_VALUE,
                    "Invalid contract signature"
                );
                return;
            } catch {
                revert("Contract signature validation failed");
            }
        }

        // Neither EOA nor valid contract signature
        revert("Invalid signature");
    }

    /**
     * @dev Check if an address is a contract
     * @param account Address to check
     * @return True if the address contains code
     */
    function _isContract(address account) internal view returns (bool) {
        uint256 size;
        assembly {
            size := extcodesize(account)
        }
        return size > 0;
    }

    /**
     * @dev Implementation of IERC20Internal for internal transfers
     * @notice This allows the extension to call _transfer from the parent contract
     */
    function executeTransfer(address from, address to, uint256 amount) external override {
        require(msg.sender == address(this), "Only callable internally");
        _transfer(from, to, amount);
    }

    /**
     * @dev Gap for future upgrades
     * Total storage slots: 50 - 1 (mapping) = 49
     */
    uint256[49] private __gap;
}
