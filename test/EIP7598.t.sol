// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "openzeppelin-contracts/contracts/proxy/transparent/ProxyAdmin.sol";
import "openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import "forge-std/Test.sol";
import "../src/StablecoinV2.sol";
import "./utils/MockERC20.sol";

contract EIP7598Test is Test {
    StablecoinV2 internal token;

    uint256 internal ownerPrivateKey;
    uint256 internal spenderPrivateKey;
    address internal owner;
    address internal spender;
    address internal recipient;

    function setUp() public {
        ownerPrivateKey = 0xA11CE;
        spenderPrivateKey = 0xB0B;

        owner = vm.addr(ownerPrivateKey);
        spender = vm.addr(spenderPrivateKey);
        recipient = address(0x3);

        vm.startPrank(owner);
        StablecoinV2 impl = new StablecoinV2();
        ProxyAdmin proxyAdmin = new ProxyAdmin();
        TransparentUpgradeableProxy proxy = new TransparentUpgradeableProxy(
            address(impl),
            address(proxyAdmin),
            abi.encodeWithSignature("initializeV2(string,string)", "Mock Name", "MKT")
        );
        token = MockERC20(address(proxy));

        // Mint some tokens to owner
        token.mint(1000e18);
        vm.stopPrank();
    }

    function test_TransferWithAuthorization() public {
        uint256 amount = 100e18;
        uint256 validAfter = block.timestamp - 1 seconds;
        uint256 validBefore = block.timestamp + 1 hours;
        bytes32 nonce = keccak256(abi.encodePacked(owner, spender, uint256(1)));

        // Build EIP-712 struct hash
        bytes32 structHash = keccak256(
            abi.encode(
                keccak256("TransferWithAuthorization(address from,address to,uint256 value,uint256 validAfter,uint256 validBefore,bytes32 nonce)"),
                owner,
                recipient,
                amount,
                validAfter,
                validBefore,
                nonce
            )
        );

        // Get domain separator and build digest
        bytes32 domainSeparator = token.DOMAIN_SEPARATOR();
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));

        // Sign the digest
        bytes memory signature = sign(digest);

        // Execute transfer with authorization
        uint256 ownerBalanceBefore = token.balanceOf(owner);
        uint256 recipientBalanceBefore = token.balanceOf(recipient);

        vm.prank(spender);
        token.transferWithAuthorization(owner, recipient, amount, validAfter, validBefore, nonce, signature);

        // Verify balances
        assertEq(token.balanceOf(owner), ownerBalanceBefore - amount);
        assertEq(token.balanceOf(recipient), recipientBalanceBefore + amount);

        // Verify nonce is used
        assertTrue(token.authorizationState(owner, nonce));
    }

     function test_TransferWithAuthorizationVRS() public {
        uint256 amount = 100e18;
        uint256 validAfter = block.timestamp - 1 seconds;
        uint256 validBefore = block.timestamp + 1 hours;
        bytes32 nonce = keccak256(abi.encodePacked(owner, spender, uint256(1)));

        // Build EIP-712 struct hash
        bytes32 structHash = keccak256(
            abi.encode(
                keccak256("TransferWithAuthorization(address from,address to,uint256 value,uint256 validAfter,uint256 validBefore,bytes32 nonce)"),
                owner,
                recipient,
                amount,
                validAfter,
                validBefore,
                nonce
            )
        );

        // Get domain separator and build digest
        bytes32 domainSeparator = token.DOMAIN_SEPARATOR();
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));

        // Sign the digest
        (uint8 v, bytes32 r, bytes32 s) = signVRS(digest);

        // Execute transfer with authorization
        uint256 ownerBalanceBefore = token.balanceOf(owner);
        uint256 recipientBalanceBefore = token.balanceOf(recipient);

        vm.prank(spender);
        token.transferWithAuthorization(owner, recipient, amount, validAfter, validBefore, nonce, v, r, s);

        // Verify balances
        assertEq(token.balanceOf(owner), ownerBalanceBefore - amount);
        assertEq(token.balanceOf(recipient), recipientBalanceBefore + amount);

        // Verify nonce is used
        assertTrue(token.authorizationState(owner, nonce));
    }

    function test_ReceiveWithAuthorization() public {
        uint256 amount = 100e18;
        uint256 validAfter = block.timestamp - 1 seconds;
        uint256 validBefore = block.timestamp + 1 hours;
        bytes32 nonce = keccak256(abi.encodePacked(owner, spender, uint256(1)));

        // Build EIP-712 struct hash
        bytes32 structHash = keccak256(
            abi.encode(
                keccak256("ReceiveWithAuthorization(address from,address to,uint256 value,uint256 validAfter,uint256 validBefore,bytes32 nonce)"),
                owner,
                recipient,
                amount,
                validAfter,
                validBefore,
                nonce
            )
        );

        // Get domain separator and build digest
        bytes32 domainSeparator = token.DOMAIN_SEPARATOR();
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));

        // Sign the digest
        bytes memory signature = sign(digest);

        // Execute transfer with authorization
        uint256 ownerBalanceBefore = token.balanceOf(owner);
        uint256 recipientBalanceBefore = token.balanceOf(recipient);

        //even if payer can not use authorization
        vm.prank(owner);
        vm.expectRevert("Caller must be the payee");
        token.receiveWithAuthorization(owner, recipient, amount, validAfter, validBefore, nonce, signature);
        
        //only payee can use authorization
        vm.prank(recipient);
        token.receiveWithAuthorization(owner, recipient, amount, validAfter, validBefore, nonce, signature);

        // Verify balances
        assertEq(token.balanceOf(owner), ownerBalanceBefore - amount);
        assertEq(token.balanceOf(recipient), recipientBalanceBefore + amount);

        // Verify nonce is used
        assertTrue(token.authorizationState(owner, nonce));
    }

    function sign(bytes32 digest) internal view returns (bytes memory) {
         (uint8 v, bytes32 r, bytes32 s) = vm.sign(ownerPrivateKey, digest);
        bytes memory signature = abi.encodePacked(r, s, v);
        return signature;
    }

    function signVRS(bytes32 digest) internal view returns (uint8 v, bytes32 r, bytes32 s) {
        return vm.sign(ownerPrivateKey, digest);
    }

    function testRevert_TransferWithAuthorization_Expired() public {
        uint256 amount = 100e18;
        uint256 validAfter = block.timestamp - 1 seconds;
        uint256 validBefore = block.timestamp; // Already expired
        bytes32 nonce = keccak256(abi.encodePacked(owner, spender, uint256(2)));

        // Build and sign authorization
        bytes32 structHash = keccak256(
            abi.encode(
                keccak256("TransferWithAuthorization(address from,address to,uint256 value,uint256 validAfter,uint256 validBefore,bytes32 nonce)"),
                owner,
                recipient,
                amount,
                validAfter,
                validBefore,
                nonce
            )
        );

        bytes32 domainSeparator = token.DOMAIN_SEPARATOR();
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ownerPrivateKey, digest);
        bytes memory signature = abi.encodePacked(r, s, v);

        // Attempt transfer - should fail
        vm.prank(spender);
        vm.expectRevert("Authorization expired");
        token.transferWithAuthorization(owner, recipient, amount, validAfter, validBefore, nonce, signature);
    }

    function testRevert_TransferWithAuthorization_NotYetValid() public {
        uint256 amount = 100e18;
        uint256 validAfter = block.timestamp + 1 seconds; // Not yet valid
        uint256 validBefore = block.timestamp + 2 seconds;
        bytes32 nonce = keccak256(abi.encodePacked(owner, spender, uint256(3)));

        console.log("validAfter:" ,  validAfter);
        // Build and sign authorization
        bytes32 structHash = keccak256(
            abi.encode(
                keccak256("TransferWithAuthorization(address from,address to,uint256 value,uint256 validAfter,uint256 validBefore,bytes32 nonce)"),
                owner,
                recipient,
                amount,
                validAfter,
                validBefore,
                nonce
            )
        );

        bytes32 domainSeparator = token.DOMAIN_SEPARATOR();
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ownerPrivateKey, digest);
        bytes memory signature = abi.encodePacked(r, s, v);

        // Attempt transfer - should fail
        vm.prank(spender);
        vm.expectRevert("Authorization not yet valid");
        token.transferWithAuthorization(owner, recipient, amount, validAfter, validBefore, nonce, signature);
    }

    function testRevert_TransferWithAuthorization_AlreadyUsed() public {
        uint256 amount = 50e18;
        uint256 validAfter = block.timestamp  - 1 seconds; // Not yet valid;
        uint256 validBefore = block.timestamp + 1 hours;
        bytes32 nonce = keccak256(abi.encodePacked(owner, spender, uint256(4)));

        // Build and sign authorization
        bytes32 structHash = keccak256(
            abi.encode(
                keccak256("TransferWithAuthorization(address from,address to,uint256 value,uint256 validAfter,uint256 validBefore,bytes32 nonce)"),
                owner,
                recipient,
                amount,
                validAfter,
                validBefore,
                nonce
            )
        );

        bytes32 domainSeparator = token.DOMAIN_SEPARATOR();
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ownerPrivateKey, digest);
        bytes memory signature = abi.encodePacked(r, s, v);

        // First transfer - should succeed
        vm.prank(spender);
        token.transferWithAuthorization(owner, recipient, amount, validAfter, validBefore, nonce, signature);

        // Second transfer with same nonce - should fail
        vm.prank(spender);
        vm.expectRevert("Authorization already used");
        token.transferWithAuthorization(owner, recipient, amount, validAfter, validBefore, nonce, signature);
    }

    function test_CancelAuthorization() public {
        bytes32 nonce = keccak256(abi.encodePacked(owner, spender, uint256(5)));

        // Owner cancels authorization
        vm.prank(owner);
        token.cancelAuthorization(owner, nonce);

        // Verify nonce is marked as used
        assertTrue(token.authorizationState(owner, nonce));
    }

    function testRevert_CancelAuthorization_NotAuthorizer() public {
        bytes32 nonce = keccak256(abi.encodePacked(owner, spender, uint256(6)));

        // Spender tries to cancel owner's authorization - should fail
        vm.prank(spender);
        vm.expectRevert("Caller must be the authorizer");
        token.cancelAuthorization(owner, nonce);
    }

    function testRevert_TransferWithAuthorization_Frozen() public {
        uint256 amount = 100e18;
        uint256 validAfter = block.timestamp - 1 seconds;
        uint256 validBefore = block.timestamp + 1 hours;
        bytes32 nonce = keccak256(abi.encodePacked(owner, spender, uint256(7)));

        // Build and sign authorization
        bytes32 structHash = keccak256(
            abi.encode(
                keccak256("TransferWithAuthorization(address from,address to,uint256 value,uint256 validAfter,uint256 validBefore,bytes32 nonce)"),
                owner,
                recipient,
                amount,
                validAfter,
                validBefore,
                nonce
            )
        );

        bytes32 domainSeparator = token.DOMAIN_SEPARATOR();
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ownerPrivateKey, digest);
        bytes memory signature = abi.encodePacked(r, s, v);

        // Freeze the owner account
        vm.prank(owner);
        token.freeze(owner);

        // Attempt transfer - should fail because account is frozen
        vm.prank(spender);
        vm.expectRevert("Account is frozen");
        token.transferWithAuthorization(owner, recipient, amount, validAfter, validBefore, nonce, signature);
    }

    function testRevert_TransferWithAuthorization_Paused() public {
        uint256 amount = 100e18;
        uint256 validAfter = block.timestamp - 1 seconds;
        uint256 validBefore = block.timestamp + 1 hours;
        bytes32 nonce = keccak256(abi.encodePacked(owner, spender, uint256(8)));

        // Build and sign authorization
        bytes32 structHash = keccak256(
            abi.encode(
                keccak256("TransferWithAuthorization(address from,address to,uint256 value,uint256 validAfter,uint256 validBefore,bytes32 nonce)"),
                owner,
                recipient,
                amount,
                validAfter,
                validBefore,
                nonce
            )
        );

        bytes32 domainSeparator = token.DOMAIN_SEPARATOR();
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ownerPrivateKey, digest);
        bytes memory signature = abi.encodePacked(r, s, v);

        // Pause the contract
        vm.prank(owner);
        token.pause();

        // Attempt transfer - should fail because contract is paused
        vm.prank(spender);
        vm.expectRevert("Pausable: paused");
        token.transferWithAuthorization(owner, recipient, amount, validAfter, validBefore, nonce, signature);
    }
}
