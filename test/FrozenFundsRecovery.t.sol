// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "openzeppelin-contracts/contracts/proxy/transparent/ProxyAdmin.sol";
import "openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import "forge-std/Test.sol";
import "../src/StablecoinV3.sol";
import "./utils/SigUtils.sol";

/**
 * Tests for StablecoinV3.recoverFrozenFunds.
 *
 * Each test names the invariant it checks. The invariants are listed here so
 * that they stay next to the tests:
 *
 *  I1  Only the owner can recover.
 *  I2  Only a frozen account can be recovered from.
 *  I3  The destination is always the current owner. No other balance changes.
 *  I4  Total supply does not change.
 *  I5  Exactly `amount` leaves the account and exactly `amount` reaches the owner.
 *  I6  The amount is greater than zero and never more than the account balance.
 *  I7  Recovered funds are never stuck: the owner must not be frozen, and a failed
 *      call changes nothing.
 *  I8  Recovery changes nothing else on the account: it stays frozen, its
 *      allowances and nonces stay as they were.
 *  I9  Nothing is recovered while the contract is paused.
 *  I10 Existing behaviour is unchanged: a frozen account still cannot send,
 *      receive or approve, and an unfrozen account cannot be touched.
 *  I11 The upgrade keeps all state and cannot be re-initialized.
 *  I12 Each recovery emits one Transfer and one FrozenFundsRecovered event.
 *  I13 A pending owner has no rights and receives nothing until it accepts.
 */
contract FrozenFundsRecoveryTest is Test {
    string internal constant NAME = "First Digital USD";
    string internal constant SYMBOL = "FDUSD";

    event Transfer(address indexed from, address indexed to, uint256 value);
    event FrozenFundsRecovered(address indexed caller, address indexed account, uint256 amount);

    StablecoinV3 internal token;
    ProxyAdmin internal proxyAdmin;
    TransparentUpgradeableProxy internal proxy;
    StablecoinV3 internal v3Impl;

    uint256 internal constant THIEF_KEY = 0x7417EF;

    address internal owner = address(0xA11CE);
    address internal thief;
    address internal bystander = address(0xB0B);
    address internal stranger = address(0xBAD);
    address internal newOwner = address(0x900D);

    uint256 internal constant THIEF_BALANCE = 1_000e18;
    uint256 internal constant BYSTANDER_BALANCE = 500e18;
    uint256 internal constant OWNER_BALANCE = 250e18;

    function setUp() public {
        thief = vm.addr(THIEF_KEY);

        vm.startPrank(owner);

        // V1 behind a transparent proxy, then V2 with its initializer: the same path
        // the deployed token went through.
        Stablecoin v1Impl = new Stablecoin();
        proxyAdmin = new ProxyAdmin();
        proxy = new TransparentUpgradeableProxy(
            address(v1Impl), address(proxyAdmin), abi.encodeWithSignature("initialize(string,string)", NAME, SYMBOL)
        );
        StablecoinV2 v2Impl = new StablecoinV2();
        proxyAdmin.upgradeAndCall(proxy, address(v2Impl), abi.encodeWithSelector(StablecoinV2.initializeV2.selector, NAME));

        // State created under V2, before the V3 upgrade.
        StablecoinV2 v2 = StablecoinV2(address(proxy));
        v2.mint(thief, THIEF_BALANCE);
        v2.mint(bystander, BYSTANDER_BALANCE);
        v2.mint(OWNER_BALANCE);
        v2.freeze(thief);

        // V3: plain upgrade, no initializer call.
        v3Impl = new StablecoinV3();
        proxyAdmin.upgrade(proxy, address(v3Impl));

        vm.stopPrank();

        token = StablecoinV3(address(proxy));
    }

    // ------------------------------------------------------------------
    // Happy path: I3, I4, I5, I8, I12
    // ------------------------------------------------------------------

    function test_Recover_PartialAmount() public {
        uint256 amount = 400e18;
        uint256 supplyBefore = token.totalSupply();

        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(thief, owner, amount);
        vm.expectEmit(true, true, false, true, address(token));
        emit FrozenFundsRecovered(owner, thief, amount);

        vm.prank(owner);
        token.recoverFrozenFunds(thief, amount);

        assertEq(token.balanceOf(thief), THIEF_BALANCE - amount, "I5: account balance");
        assertEq(token.balanceOf(owner), OWNER_BALANCE + amount, "I5: owner balance");
        assertEq(token.balanceOf(bystander), BYSTANDER_BALANCE, "I3: bystander untouched");
        assertEq(token.totalSupply(), supplyBefore, "I4: supply unchanged");
        assertTrue(token.frozen(thief), "I8: account stays frozen");
    }

    function test_Recover_FullBalance() public {
        vm.prank(owner);
        token.recoverFrozenFunds(thief, THIEF_BALANCE);

        assertEq(token.balanceOf(thief), 0);
        assertEq(token.balanceOf(owner), OWNER_BALANCE + THIEF_BALANCE);
    }

    function test_Recover_InSeveralSteps() public {
        vm.startPrank(owner);
        token.recoverFrozenFunds(thief, 100e18);
        token.recoverFrozenFunds(thief, 200e18);
        token.recoverFrozenFunds(thief, THIEF_BALANCE - 300e18);
        vm.stopPrank();

        assertEq(token.balanceOf(thief), 0);
        assertEq(token.balanceOf(owner), OWNER_BALANCE + THIEF_BALANCE);
    }

    function test_Recover_EmitsExactlyTwoEvents() public {
        vm.recordLogs();
        vm.prank(owner);
        token.recoverFrozenFunds(thief, 1e18);

        Vm.Log[] memory logs = vm.getRecordedLogs();
        assertEq(logs.length, 2, "I12: one Transfer and one FrozenFundsRecovered");
        assertEq(logs[0].topics[0], keccak256("Transfer(address,address,uint256)"));
        assertEq(logs[1].topics[0], keccak256("FrozenFundsRecovered(address,address,uint256)"));
    }

    /// The recovered tokens are ordinary tokens in the owner's hands: the owner can
    /// send them on, or burn them if destruction is required.
    function test_Recover_ThenOwnerCanTransferOrBurn() public {
        uint256 supplyBefore = token.totalSupply();

        vm.startPrank(owner);
        token.recoverFrozenFunds(thief, 300e18);
        token.transfer(bystander, 200e18);
        token.burn(100e18);
        vm.stopPrank();

        assertEq(token.balanceOf(bystander), BYSTANDER_BALANCE + 200e18, "I7: funds are spendable");
        assertEq(token.balanceOf(owner), OWNER_BALANCE);
        assertEq(token.totalSupply(), supplyBefore - 100e18);
    }

    function testFuzz_Recover(uint256 minted, uint256 amount) public {
        address account = address(0xF00D);
        minted = bound(minted, 1, type(uint128).max);
        amount = bound(amount, 1, minted);

        vm.startPrank(owner);
        token.mint(account, minted);
        token.freeze(account);

        uint256 supplyBefore = token.totalSupply();
        uint256 ownerBefore = token.balanceOf(owner);

        token.recoverFrozenFunds(account, amount);
        vm.stopPrank();

        assertEq(token.balanceOf(account), minted - amount, "I5");
        assertEq(token.balanceOf(owner), ownerBefore + amount, "I5");
        assertEq(token.totalSupply(), supplyBefore, "I4");
        assertEq(token.balanceOf(thief), THIEF_BALANCE, "I3");
        assertEq(token.balanceOf(bystander), BYSTANDER_BALANCE, "I3");
    }

    // ------------------------------------------------------------------
    // I1: only the owner
    // ------------------------------------------------------------------

    function test_RevertWhen_CallerIsNotOwner() public {
        vm.prank(stranger);
        vm.expectRevert("Ownable: caller is not the owner");
        token.recoverFrozenFunds(thief, 1e18);
    }

    function test_RevertWhen_CallerIsTheFrozenAccount() public {
        vm.prank(thief);
        vm.expectRevert("Ownable: caller is not the owner");
        token.recoverFrozenFunds(thief, 1e18);
    }

    function test_RevertWhen_CallerIsProxyAdminContract() public {
        // The proxy admin can only reach the proxy's own admin functions.
        vm.prank(address(proxyAdmin));
        vm.expectRevert("TransparentUpgradeableProxy: admin cannot fallback to proxy target");
        token.recoverFrozenFunds(thief, 1e18);
    }

    function testFuzz_RevertWhen_CallerIsNotOwner(address caller, uint256 amount) public {
        vm.assume(caller != owner && caller != address(proxyAdmin));
        amount = bound(amount, 1, THIEF_BALANCE);

        vm.prank(caller);
        vm.expectRevert("Ownable: caller is not the owner");
        token.recoverFrozenFunds(thief, amount);

        assertEq(token.balanceOf(thief), THIEF_BALANCE);
    }

    // ------------------------------------------------------------------
    // I2, I10: only from a frozen account
    // ------------------------------------------------------------------

    function test_RevertWhen_AccountIsNotFrozen() public {
        vm.prank(owner);
        vm.expectRevert("Account is not frozen");
        token.recoverFrozenFunds(bystander, 1e18);

        assertEq(token.balanceOf(bystander), BYSTANDER_BALANCE);
    }

    function test_RevertWhen_AccountWasUnfrozen() public {
        vm.startPrank(owner);
        token.unfreeze(thief);
        vm.expectRevert("Account is not frozen");
        token.recoverFrozenFunds(thief, 1e18);
        vm.stopPrank();
    }

    function testFuzz_RevertWhen_AccountIsNotFrozen(address account, uint256 amount) public {
        vm.assume(!token.frozen(account));

        vm.prank(owner);
        vm.expectRevert("Account is not frozen");
        token.recoverFrozenFunds(account, amount);
    }

    function test_RevertWhen_AccountIsOwnerItself() public {
        // Not frozen: rejected as "not frozen". Frozen: rejected as "owner is frozen".
        vm.startPrank(owner);
        vm.expectRevert("Account is not frozen");
        token.recoverFrozenFunds(owner, 1e18);

        token.freeze(owner);
        vm.expectRevert("Owner is frozen");
        token.recoverFrozenFunds(owner, 1e18);
        vm.stopPrank();
    }

    function test_FrozenAccountStillCannotMoveFunds() public {
        vm.startPrank(thief);
        vm.expectRevert("Account is frozen");
        token.transfer(stranger, 1e18);
        vm.expectRevert("Account is frozen");
        token.approve(stranger, 1e18);
        vm.stopPrank();

        vm.prank(bystander);
        vm.expectRevert("Account is frozen");
        token.transfer(thief, 1e18);

        vm.prank(owner);
        vm.expectRevert("Account is frozen");
        token.mint(thief, 1e18);
    }

    // ------------------------------------------------------------------
    // I6: amount bounds
    // ------------------------------------------------------------------

    function test_RevertWhen_AmountIsZero() public {
        vm.prank(owner);
        vm.expectRevert("Amount is zero");
        token.recoverFrozenFunds(thief, 0);
    }

    function test_RevertWhen_AmountExceedsBalance() public {
        vm.prank(owner);
        vm.expectRevert("ERC20: transfer amount exceeds balance");
        token.recoverFrozenFunds(thief, THIEF_BALANCE + 1);

        assertEq(token.balanceOf(thief), THIEF_BALANCE);
        assertEq(token.balanceOf(owner), OWNER_BALANCE);
    }

    function test_RevertWhen_FrozenAccountIsEmpty() public {
        address empty = address(0xE);
        vm.startPrank(owner);
        token.freeze(empty);
        vm.expectRevert("ERC20: transfer amount exceeds balance");
        token.recoverFrozenFunds(empty, 1);
        vm.stopPrank();
    }

    function test_RevertWhen_AccountIsZeroAddress() public {
        vm.startPrank(owner);
        vm.expectRevert("Account is not frozen");
        token.recoverFrozenFunds(address(0), 1);

        token.freeze(address(0));
        vm.expectRevert("ERC20: transfer from the zero address");
        token.recoverFrozenFunds(address(0), 1);
        vm.stopPrank();
    }

    // ------------------------------------------------------------------
    // I7: no limbo
    // ------------------------------------------------------------------

    function test_RevertWhen_OwnerIsFrozen() public {
        vm.startPrank(owner);
        token.freeze(owner);
        vm.expectRevert("Owner is frozen");
        token.recoverFrozenFunds(thief, 1e18);

        // The owner can always unfreeze itself and continue.
        token.unfreeze(owner);
        token.recoverFrozenFunds(thief, 1e18);
        vm.stopPrank();

        assertEq(token.balanceOf(owner), OWNER_BALANCE + 1e18);
    }

    function test_NothingEverReachesTokenContractOrZeroAddress() public {
        vm.prank(owner);
        token.recoverFrozenFunds(thief, THIEF_BALANCE);

        assertEq(token.balanceOf(address(token)), 0);
        assertEq(token.balanceOf(address(v3Impl)), 0);
        assertEq(token.balanceOf(address(proxyAdmin)), 0);
        assertEq(token.balanceOf(address(0)), 0);
    }

    function test_RecoveryFromFrozenContractAccount() public {
        // A contract holder gets no callback: plain ERC20 has no transfer hooks.
        address pool = address(new RevertingHolder());
        vm.startPrank(owner);
        token.mint(pool, 10e18);
        token.freeze(pool);
        token.recoverFrozenFunds(pool, 10e18);
        vm.stopPrank();

        assertEq(token.balanceOf(pool), 0);
    }

    // ------------------------------------------------------------------
    // I8: nothing else changes on the account
    // ------------------------------------------------------------------

    function test_Recover_DoesNotChangeAllowancesOrNonces() public {
        vm.startPrank(owner);
        token.unfreeze(thief);
        vm.stopPrank();
        vm.prank(thief);
        token.approve(stranger, 123e18);
        vm.startPrank(owner);
        token.freeze(thief);

        uint256 nonceBefore = token.nonces(thief);
        token.recoverFrozenFunds(thief, 100e18);
        vm.stopPrank();

        assertEq(token.allowance(thief, stranger), 123e18, "I8: allowance unchanged");
        assertEq(token.allowance(thief, owner), 0, "I8: no allowance created for owner");
        assertEq(token.nonces(thief), nonceBefore, "I8: permit nonce unchanged");

        // The old allowance is still unusable while the account is frozen.
        vm.prank(stranger);
        vm.expectRevert("Account is frozen");
        token.transferFrom(thief, stranger, 1e18);
    }

    function test_RemainingBalanceIsUsableAfterUnfreeze() public {
        vm.startPrank(owner);
        token.recoverFrozenFunds(thief, 400e18);
        token.unfreeze(thief);
        vm.stopPrank();

        vm.prank(thief);
        token.transfer(stranger, THIEF_BALANCE - 400e18);
        assertEq(token.balanceOf(stranger), THIEF_BALANCE - 400e18);
    }

    // ------------------------------------------------------------------
    // I9: pause
    // ------------------------------------------------------------------

    function test_RevertWhen_Paused() public {
        vm.startPrank(owner);
        token.pause();
        vm.expectRevert("Pausable: paused");
        token.recoverFrozenFunds(thief, 1e18);

        token.unpause();
        token.recoverFrozenFunds(thief, 1e18);
        vm.stopPrank();
    }

    // ------------------------------------------------------------------
    // I13: ownership transfer
    // ------------------------------------------------------------------

    function test_PendingOwnerCannotRecoverAndReceivesNothing() public {
        vm.prank(owner);
        token.transferOwnership(newOwner);

        vm.prank(newOwner);
        vm.expectRevert("Ownable: caller is not the owner");
        token.recoverFrozenFunds(thief, 1e18);

        // Still the old owner until the new one accepts.
        vm.prank(owner);
        token.recoverFrozenFunds(thief, 1e18);
        assertEq(token.balanceOf(owner), OWNER_BALANCE + 1e18);
        assertEq(token.balanceOf(newOwner), 0);
    }

    function test_AfterOwnershipTransfer_FundsGoToNewOwnerOnly() public {
        vm.prank(owner);
        token.transferOwnership(newOwner);
        vm.prank(newOwner);
        token.acceptOwnership();

        vm.prank(owner);
        vm.expectRevert("Ownable: caller is not the owner");
        token.recoverFrozenFunds(thief, 1e18);

        vm.prank(newOwner);
        token.recoverFrozenFunds(thief, 50e18);

        assertEq(token.balanceOf(newOwner), 50e18);
        assertEq(token.balanceOf(owner), OWNER_BALANCE, "old owner receives nothing");
    }

    function test_RevertWhen_OwnershipRenounced() public {
        vm.prank(owner);
        token.renounceOwnership();

        vm.prank(owner);
        vm.expectRevert("Ownable: caller is not the owner");
        token.recoverFrozenFunds(thief, 1e18);

        vm.prank(address(0));
        vm.expectRevert("Account is not frozen");
        token.recoverFrozenFunds(bystander, 1e18);
    }

    // ------------------------------------------------------------------
    // I11: upgrade safety
    // ------------------------------------------------------------------

    function test_Upgrade_KeepsState() public {
        // Everything below was written under V1/V2 in setUp and is read through V3.
        assertEq(token.name(), NAME);
        assertEq(token.symbol(), SYMBOL);
        assertEq(token.decimals(), 18);
        assertEq(token.owner(), owner);
        assertEq(token.pendingOwner(), address(0));
        assertEq(token.totalSupply(), THIEF_BALANCE + BYSTANDER_BALANCE + OWNER_BALANCE);
        assertEq(token.balanceOf(thief), THIEF_BALANCE);
        assertEq(token.balanceOf(bystander), BYSTANDER_BALANCE);
        assertEq(token.balanceOf(owner), OWNER_BALANCE);
        assertTrue(token.frozen(thief));
        assertFalse(token.frozen(bystander));
        assertFalse(token.paused());
        assertTrue(token.eip7598EnableFlag());
    }

    function test_Upgrade_KeepsDomainSeparatorAndPermitWorks() public {
        vm.prank(owner);
        token.unfreeze(thief);

        SigUtils sigUtils = new SigUtils(token.DOMAIN_SEPARATOR());
        SigUtils.Permit memory permit = SigUtils.Permit({
            owner: thief, spender: stranger, value: 1e18, nonce: token.nonces(thief), deadline: block.timestamp + 1 days
        });
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(THIEF_KEY, sigUtils.getTypedDataHash(permit));

        token.permit(permit.owner, permit.spender, permit.value, permit.deadline, v, r, s);
        assertEq(token.allowance(thief, stranger), 1e18);
    }

    function test_Upgrade_CannotBeInitializedAgain() public {
        vm.expectRevert("Initializable: contract is already initialized");
        token.initialize("Fake", "FAKE");

        vm.expectRevert("Initializable: contract is already initialized");
        token.initializeV2("Fake");
    }

    function test_Implementation_CannotBeInitializedOrUsed() public {
        vm.expectRevert("Initializable: contract is already initialized");
        v3Impl.initialize("Fake", "FAKE");

        vm.expectRevert("Initializable: contract is already initialized");
        v3Impl.initializeV2("Fake");

        assertEq(v3Impl.owner(), address(0));
        vm.expectRevert("Ownable: caller is not the owner");
        v3Impl.recoverFrozenFunds(thief, 1);
    }

    function test_Upgrade_V2FunctionsStillWork() public {
        vm.startPrank(owner);
        token.mint(bystander, 1e18);
        token.disableEIP7598();
        assertFalse(token.eip7598EnableFlag());
        token.enableEIP7598();
        vm.stopPrank();

        vm.prank(bystander);
        token.transfer(stranger, 1e18);
        assertEq(token.balanceOf(stranger), 1e18);
    }
}

/// A holder that rejects every call. Used to show that recovery makes no callback.
contract RevertingHolder {
    fallback() external payable {
        revert("no calls");
    }
}
