// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

import "openzeppelin-contracts/contracts/proxy/transparent/ProxyAdmin.sol";
import "openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import "forge-std/Test.sol";
import "./utils/MockERC20.sol";
import "./utils/SigUtils.sol";

contract StablecoinTest is Test {
    string internal constant NAME = "First Digital USD";
    string internal constant SYMBOL = "FDUSD";

    MockERC20 internal token;
    SigUtils internal sigUtils;
    uint256 internal ownerPrivateKey;
    uint256 internal spenderPrivateKey;
    address internal owner;
    address internal spender;

    function setUp() public {
        ownerPrivateKey = 0xA11CE;
        spenderPrivateKey = 0xB0B;

        owner = vm.addr(ownerPrivateKey);
        spender = vm.addr(spenderPrivateKey);

        deployAndUpgradeSmartContract();

        vm.startPrank(owner);
        sigUtils = new SigUtils(token.DOMAIN_SEPARATOR());
        token.mint(1e18);
        vm.stopPrank();
    }

    function deployAndUpgradeSmartContract() internal {
        vm.startPrank(owner);

        Stablecoin impl = new Stablecoin();
        ProxyAdmin proxyAdmin = new ProxyAdmin();
        TransparentUpgradeableProxy proxy = new TransparentUpgradeableProxy(
            address(impl),
            address(proxyAdmin),
            abi.encodeWithSignature("initialize(string,string)", "Mock Name", "MKT")
        );

        StablecoinV2 newImpl = new StablecoinV2();
        console.log("New Implementation:", address(newImpl));

        // 2️⃣ 构造 initializeV2 的 calldata
        bytes memory initData = abi.encodeWithSelector(
            StablecoinV2.initializeV2.selector,
            NAME
        );

        // 3️⃣ 调用 upgradeAndCall
        proxyAdmin.upgradeAndCall(proxy, address(newImpl), initData);
        
        token = MockERC20(address(proxy));

        vm.stopPrank();
    }

    function test_TransferOwnership() public {
        address newOwner = spender;

        assertEq(token.pendingOwner(), address(0));

        vm.prank(owner);
        token.transferOwnership(owner);

        assertEq(token.pendingOwner(), owner);

        vm.prank(owner);
        token.acceptOwnership();

        assertEq(token.owner(), owner);
        assertEq(token.pendingOwner(), address(0));

        vm.prank(owner);
        token.transferOwnership(newOwner);

        assertEq(token.pendingOwner(), newOwner);

        vm.prank(newOwner);
        token.acceptOwnership();

        assertEq(token.owner(), newOwner);
        assertEq(token.pendingOwner(), address(0));
    }

    function testRevert_InvalidOwner() public {
        address newOwner = spender;

        vm.expectRevert("Ownable: caller is not the owner");
        token.transferOwnership(newOwner);
    }

    function testRevert_InvalidPendingOwner() public {
        address newOwner = spender;

        vm.prank(owner);
        token.transferOwnership(newOwner);

        vm.expectRevert("Ownable2Step: caller is not the new owner");
        token.acceptOwnership();
    }

    function test_CancelPendingOwnership() public {
        address newOwner = spender;

        vm.prank(owner);
        token.transferOwnership(newOwner);

        assertEq(token.pendingOwner(), newOwner);

        vm.prank(owner);
        token.transferOwnership(address(0));

        assertEq(token.pendingOwner(), address(0));
    }

    function test_Mint() public {
        vm.prank(owner);
        token.mint(10e18);

        assertEq(token.balanceOf(owner), 11e18);
        assertEq(token.totalSupply(), 11e18);
    }

    function test_MintTo() public {
        vm.prank(owner);
        token.mint(spender, 10e18);

        assertEq(token.balanceOf(spender), 10e18);
        assertEq(token.totalSupply(), 11e18);

        vm.prank(owner);
        token.freeze(spender);
        
        vm.prank(owner);
        vm.expectRevert("Account is frozen");
        token.mint(spender, 1e18); // source freeze
    }

    function testRevert_InvalidMintOwner() public {
        vm.expectRevert("Ownable: caller is not the owner");
        token.mint(10e18);
    }

    function test_Burn() public {
        vm.prank(owner);
        token.burn(1e18);

        assertEq(token.balanceOf(owner), 0);
        assertEq(token.totalSupply(), 0);
    }

    function testRevert_InvalidBurnOwner() public {
        vm.expectRevert("Ownable: caller is not the owner");
        token.burn(1e18);
    }

    function testRevert_InvalidBurnAmount() public {
        vm.prank(owner);
        vm.expectRevert("ERC20: burn amount exceeds balance");
        token.burn(10e18);
    }

    function test_Freeze() public {
        address spender2 = vm.addr(0xB0B2);
        
        vm.startPrank(owner);
        token.freeze(spender);
        token.freeze(spender2);
        token.freeze(spender2); // double freeze
        vm.stopPrank();
        
        assertEq(token.frozen(spender), true);
        assertEq(token.frozen(spender2), true);
    }

    function test_Unfreeze() public {
        address notFrozenSpender = vm.addr(0xB0B2);
        
        vm.startPrank(owner);
        token.freeze(spender);
        token.unfreeze(spender);
        token.unfreeze(spender); // double unfreeze
        token.unfreeze(notFrozenSpender); // unfreeze on unfrozen
        vm.stopPrank();
        
        assertEq(token.frozen(spender), false);
        assertEq(token.frozen(notFrozenSpender), false);
    }

    function testRevert_InvalidFreezeOwner() public {
        vm.expectRevert("Ownable: caller is not the owner");
        token.freeze(spender);
    }

    function testRevert_InvalidUnFreezeOwner() public {
        vm.expectRevert("Ownable: caller is not the owner");
        token.unfreeze(spender);
    }

    function testRevert_FreezeTransfer() public {
        vm.startPrank(owner);
        token.freeze(owner);

        vm.expectRevert("Account is frozen");
        token.transfer(spender, 1e18); // source freeze

        token.unfreeze(owner);
        token.freeze(spender);

        vm.expectRevert("Account is frozen");
        token.transfer(spender, 1e18); // destination freeze
        vm.stopPrank();
    }

    function testRevert_FreezeTransferFrom() public {
        vm.startPrank(owner);
        token.approve(owner, 1e18);
        token.freeze(owner);

        vm.expectRevert("Account is frozen");
        token.transferFrom(owner, spender, 1e18); // source freeze

        token.unfreeze(owner);
        token.approve(spender, 1e18);
        token.freeze(spender);

        vm.expectRevert("Account is frozen");
        token.transferFrom(owner, spender, 1e18); // destination freeze
        vm.stopPrank();
    }

    function testRevert_FreezeApprove() public {
        vm.startPrank(owner);
        token.freeze(owner);

        vm.expectRevert("Account is frozen");
        token.approve(spender, 1e18); // source freeze

        token.unfreeze(owner);
        token.freeze(spender);

        vm.expectRevert("Account is frozen");
        token.approve(spender, 1e18); // destination freeze
        vm.stopPrank();
    }

    function test_Pause() public {
        vm.prank(owner);
        token.pause();

        assertEq(token.paused(), true);

        vm.prank(owner);
        token.unpause();

        assertEq(token.paused(), false);
    }

    function test_ResumePause() public {
        vm.startPrank(owner);
        token.pause();
        token.unpause();

        token.approve(spender, 1e18);
        token.transfer(spender, 5e17);
        vm.stopPrank();

        vm.prank(spender);
        token.transferFrom(owner, spender, 5e17);
    }

    function testRevert_InvalidPauseOwner() public {
        vm.expectRevert("Ownable: caller is not the owner");
        token.pause();
    }

    function testRevert_InvalidUnpauseOwner() public {
        vm.expectRevert("Ownable: caller is not the owner");
        token.unpause();
    }

    function test_Approve() public {
        vm.prank(owner);
        token.approve(spender, 1e18);
        assertEq(token.allowance(owner, spender), 1e18);
    }

    function testRevert_PauseApprove() public {
        vm.prank(owner);
        token.pause();

        vm.expectRevert("Pausable: paused");
        token.approve(spender, 1e18);
    }

    function test_ResumePauseApprove() public {
        vm.startPrank(owner);
        token.pause();
        token.unpause();

        token.approve(spender, 1e18);
        assertEq(token.allowance(owner, spender), 1e18);
        vm.stopPrank();
    }

    function test_IncreaseAllowance() public {
        vm.prank(owner);
        token.increaseAllowance(spender, 1e18);
        assertEq(token.allowance(owner, spender), 1e18);
    }

    function testRevert_PauseIncreaseAllowance() public {
        vm.prank(owner);
        token.pause();

        vm.expectRevert("Pausable: paused");
        token.increaseAllowance(spender, 1e18);
    }

    function test_ResumePauseIncreaseAllowance() public {
        vm.startPrank(owner);
        token.pause();
        token.unpause();

        token.increaseAllowance(spender, 1e18);
        assertEq(token.allowance(owner, spender), 1e18);
        vm.stopPrank();
    }

    function test_DecreaseAllowance() public {
        vm.startPrank(owner);
        token.increaseAllowance(spender, 1e18);
        token.decreaseAllowance(spender, 5e17);
        assertEq(token.allowance(owner, spender), 5e17);
        vm.stopPrank();
    }

    function testRevert_PauseDecreaseAllowance() public {
        vm.startPrank(owner);
        token.increaseAllowance(spender, 1e18);
        token.pause();

        vm.expectRevert("Pausable: paused");
        token.decreaseAllowance(spender, 1e18);
        vm.stopPrank();
    }

    function testRevert_ResumePauseDecreaseAllowance() public {
        vm.startPrank(owner);
        token.increaseAllowance(spender, 1e18);
        token.pause();
        token.unpause();

        token.decreaseAllowance(spender, 1e18);
        assertEq(token.allowance(owner, spender), 0);
        vm.stopPrank();
    }

    function testRevert_PauseTransfer() public {
        vm.prank(owner);
        token.pause();

        vm.expectRevert("Pausable: paused");
        token.transfer(spender, 1e18);
    }

    function testRevert_PauseTransferFrom() public {
        vm.startPrank(owner);
        token.approve(spender, 1e18);
        token.pause();
        vm.stopPrank();

        vm.prank(spender);
        vm.expectRevert("Pausable: paused");
        token.transferFrom(owner, spender, 1e18);
    }

    function test_Permit() public {
        SigUtils.Permit memory permit = SigUtils.Permit({
            owner: owner,
            spender: spender,
            value: 1e18,
            nonce: 0,
            deadline: 1 days
        });

        bytes32 digest = sigUtils.getTypedDataHash(permit);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ownerPrivateKey, digest);

        token.permit(permit.owner, permit.spender, permit.value, permit.deadline, v, r, s);

        assertEq(token.allowance(owner, spender), 1e18);
        assertEq(token.nonces(owner), 1);
    }

    function testRevert_ExpiredPermit() public {
        SigUtils.Permit memory permit = SigUtils.Permit({
            owner: owner,
            spender: spender,
            value: 1e18,
            nonce: token.nonces(owner),
            deadline: 1 days
        });

        bytes32 digest = sigUtils.getTypedDataHash(permit);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ownerPrivateKey, digest);

        vm.warp(1 days + 1 seconds); // fast forward one second past the deadline

        vm.expectRevert("ERC20Permit: expired deadline");
        token.permit(permit.owner, permit.spender, permit.value, permit.deadline, v, r, s);
    }

    function testRevert_InvalidSigner() public {
        SigUtils.Permit memory permit = SigUtils.Permit({
            owner: owner,
            spender: spender,
            value: 1e18,
            nonce: token.nonces(owner),
            deadline: 1 days
        });

        bytes32 digest = sigUtils.getTypedDataHash(permit);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(spenderPrivateKey, digest); // spender signs owner's approval

        vm.expectRevert("ERC20Permit: invalid signature");
        token.permit(permit.owner, permit.spender, permit.value, permit.deadline, v, r, s);
    }

    function testRevert_InvalidNonce() public {
        SigUtils.Permit memory permit = SigUtils.Permit({
            owner: owner,
            spender: spender,
            value: 1e18,
            nonce: 1, // owner nonce stored on-chain is 0
            deadline: 1 days
        });

        bytes32 digest = sigUtils.getTypedDataHash(permit);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ownerPrivateKey, digest);

        vm.expectRevert("ERC20Permit: invalid signature");
        token.permit(permit.owner, permit.spender, permit.value, permit.deadline, v, r, s);
    }

    function testRevert_SignatureReplay() public {
        SigUtils.Permit memory permit = SigUtils.Permit({
            owner: owner,
            spender: spender,
            value: 1e18,
            nonce: 0,
            deadline: 1 days
        });

        bytes32 digest = sigUtils.getTypedDataHash(permit);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ownerPrivateKey, digest);

        token.permit(permit.owner, permit.spender, permit.value, permit.deadline, v, r, s);

        vm.expectRevert("ERC20Permit: invalid signature");
        token.permit(permit.owner, permit.spender, permit.value, permit.deadline, v, r, s);
    }
    
    function test_TransferFromLimitedPermit() public {
        SigUtils.Permit memory permit = SigUtils.Permit({
            owner: owner,
            spender: spender,
            value: 1e18,
            nonce: 0,
            deadline: 1 days
        });

        bytes32 digest = sigUtils.getTypedDataHash(permit);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ownerPrivateKey, digest);

        token.permit(permit.owner, permit.spender, permit.value, permit.deadline, v, r, s);

        vm.prank(spender);
        token.transferFrom(owner, spender, 1e18);

        assertEq(token.balanceOf(owner), 0);
        assertEq(token.balanceOf(spender), 1e18);
        assertEq(token.allowance(owner, spender), 0);
    }

    function test_TransferFromMaxPermit() public {
        SigUtils.Permit memory permit = SigUtils.Permit({
            owner: owner,
            spender: spender,
            value: type(uint256).max,
            nonce: 0,
            deadline: 1 days
        });

        bytes32 digest = sigUtils.getTypedDataHash(permit);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ownerPrivateKey, digest);

        token.permit(permit.owner, permit.spender, permit.value, permit.deadline, v, r, s);

        vm.prank(spender);
        token.transferFrom(owner, spender, 1e18);

        assertEq(token.balanceOf(owner), 0);
        assertEq(token.balanceOf(spender), 1e18);
        assertEq(token.allowance(owner, spender), type(uint256).max);
    }

    function test_RevertInvalidAllowance() public {
        SigUtils.Permit memory permit = SigUtils.Permit({
            owner: owner,
            spender: spender,
            value: 5e17, // approve only 0.5 tokens
            nonce: 0,
            deadline: 1 days
        });

        bytes32 digest = sigUtils.getTypedDataHash(permit);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ownerPrivateKey, digest);

        token.permit(permit.owner, permit.spender, permit.value, permit.deadline, v, r, s);

        vm.prank(spender);
        vm.expectRevert("ERC20: insufficient allowance");
        token.transferFrom(owner, spender, 1e18); // attempt to transfer 1 token
    }

    function test_RevertInvalidBalance() public {
        SigUtils.Permit memory permit = SigUtils.Permit({
            owner: owner,
            spender: spender,
            value: 2e18, // approve 2 tokens
            nonce: 0,
            deadline: 1 days
        });

        bytes32 digest = sigUtils.getTypedDataHash(permit);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ownerPrivateKey, digest);

        token.permit(permit.owner, permit.spender, permit.value, permit.deadline, v, r, s);

        vm.prank(spender);
        vm.expectRevert("ERC20: transfer amount exceeds balance");
        token.transferFrom(owner, spender, 2e18); // attempt to transfer 2 tokens (owner only owns 1)
    }
}
