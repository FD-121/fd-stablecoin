// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "openzeppelin-contracts-upgradeable/contracts/utils/cryptography/ECDSAUpgradeable.sol";
import "openzeppelin-contracts-upgradeable/contracts/utils/AddressUpgradeable.sol";
import "openzeppelin-contracts-upgradeable/contracts/utils/cryptography/SignatureCheckerUpgradeable.sol";
import "./libraries/EIP7598Constants.sol";
import "./Stablecoin.sol";

contract StablecoinV2 is Stablecoin {

    using ECDSAUpgradeable for bytes32;
    using AddressUpgradeable for address;

    // State variable for tracking used authorization nonces
    // This uses bytes32 nonces to allow for flexible nonce strategies
    mapping(address => mapping(bytes32 => bool)) private _authorizationStates;

    // Events
    event AuthorizationUsed(address indexed authorizer, bytes32 indexed nonce);
    event AuthorizationCanceled(address indexed authorizer, bytes32 indexed nonce);

    /**
     * @dev Disable initializers for the implementation contract
     */
    constructor() {
        _disableInitializers();
    }

    /**
     * @dev Initialize the contract
     * @param _name Token name
     */   
    function initializeV2(string memory _name) public reinitializer(2) {  
        __EIP712_init(_name, "1");
    }

    /**
     * @dev See {ERC20-_mint}.
     * @param to Mint to address
     * @param amount Mint amount
     * @return True if successful
     * Can only be called by the current owner.
     */
    function mint(address to, uint256 amount) external onlyOwner notFrozen(to) returns (bool) {
        _mint(to, amount);
        emit Mint(_msgSender(), to, amount);
        return true;
    }

    /**
     * @dev Execute a transfer with an authorization signature, backward-compatible with the ERC-3009 standard.
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
        _transferOrReceiveWithAuthorization(EIP7598Constants.TRANSFER_WITH_AUTHORIZATION_TYPEHASH, from, to, value, validAfter, validBefore, nonce, signature);
    }

    /**
     * @dev Execute a transfer with an authorization signature (EIP-7598)
     * @param from Payer's address (Authorizer)
     * @param to Payee's address
     * @param value Amount to transfer
     * @param validAfter The time after which this is valid (unix time)
     * @param validBefore The time before which this is valid (unix time)
     * @param nonce Unique nonce for this authorization
     * @param v Signature bytes (EOA signature or EIP-1271 contract signature)
     * @param r Signature bytes (EOA signature or EIP-1271 contract signature)
     * @param s Signature bytes (EOA signature or EIP-1271 contract signature)
     */
    function transferWithAuthorization(
        address from,
        address to,
        uint256 value,
        uint256 validAfter,
        uint256 validBefore,
        bytes32 nonce,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external {
        _transferOrReceiveWithAuthorization(EIP7598Constants.TRANSFER_WITH_AUTHORIZATION_TYPEHASH, from, to, value, validAfter, validBefore, nonce, abi.encodePacked(r, s, v));
    }

    /**
    * @notice Receive a transfer with a signed authorization from the payer
    * @dev This has an additional check to ensure that the payee's address matches
    * the caller of this function to prevent front-running attacks. (See security
    * considerations)
    * @param from          Payer's address (Authorizer)
    * @param to            Payee's address
    * @param value         Amount to be transferred
    * @param validAfter    The time after which this is valid (unix time)
    * @param validBefore   The time before which this is valid (unix time)
    * @param nonce         Unique nonce
    * @param signature     Unstructured bytes signature signed by an EOA wallet or a contract wallet
    */
    function receiveWithAuthorization(
        address from,
        address to,
        uint256 value,
        uint256 validAfter,
        uint256 validBefore,
        bytes32 nonce,
        bytes memory signature
    ) external {
        require(msg.sender == to, "Caller must be the payee");
        _transferOrReceiveWithAuthorization(EIP7598Constants.RECEIVE_WITH_AUTHORIZATION_TYPEHASH, from, to, value, validAfter, validBefore, nonce, signature);
    }

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
    function _transferOrReceiveWithAuthorization(
        bytes32 typeHash,
        address from,
        address to,
        uint256 value,
        uint256 validAfter,
        uint256 validBefore,
        bytes32 nonce,
        bytes memory signature
    ) internal {
        // Validate time window
        require(block.timestamp > validAfter, "Authorization not yet valid");
        require(block.timestamp < validBefore, "Authorization expired");

        // Validate nonce
        require(!_authorizationStates[from][nonce], "Authorization already used");

        // Build EIP-712 struct hash
        bytes32 structHash = keccak256(
            abi.encode(
                typeHash,
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
        require(
            SignatureCheckerUpgradeable.isValidSignatureNow(from, digest, signature),
            "Invalid signature"
        );
        //_validateSignature(from, digest, signature);

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
     * @dev Gap for future upgrades
     * Total storage slots: 50 - 1 (mapping) = 49
     */
    uint256[49] private __gap;
}
