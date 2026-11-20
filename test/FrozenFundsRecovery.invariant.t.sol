// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "openzeppelin-contracts/contracts/proxy/transparent/ProxyAdmin.sol";
import "openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import "forge-std/Test.sol";
import "../src/StablecoinV3.sol";

/**
 * Drives the token through random sequences of mint, burn, transfer, freeze, unfreeze,
 * pause, unpause, ownership transfer and recovery attempts by random callers.
 *
 * Every recovery attempt is checked on the spot against the state before the call:
 * if it succeeded, all preconditions must have held and only two balances may have
 * moved; if it failed, nothing may have changed.
 *
 * The invariant tests run with fail-on-revert enabled. A failed assertion in this
 * handler reverts, and without that setting the revert would be silently discarded.
 * For the same reason no handler function may revert in normal operation.
 */
contract RecoveryHandler is Test {
    StablecoinV3 public token;
    address[] public actors;

    // Ghost state
    uint256 public ghostMinted;
    uint256 public ghostBurned;
    uint256 public ghostRecovered;
    uint256 public recoverySuccesses;
    uint256 public recoveryFailures;

    constructor(StablecoinV3 _token, address[] memory _actors) {
        token = _token;
        actors = _actors;
    }

    function actorCount() external view returns (uint256) {
        return actors.length;
    }

    function _actor(uint256 seed) internal view returns (address) {
        return actors[seed % actors.length];
    }

    // --- ordinary operations -------------------------------------------------

    function mint(uint256 toSeed, uint256 amount) external {
        address to = _actor(toSeed);
        amount = bound(amount, 0, 1_000_000e18);
        vm.prank(token.owner());
        try token.mint(to, amount) {
            ghostMinted += amount;
        } catch {}
    }

    function burn(uint256 amount) external {
        address currentOwner = token.owner();
        amount = bound(amount, 0, token.balanceOf(currentOwner));
        vm.prank(currentOwner);
        try token.burn(amount) {
            ghostBurned += amount;
        } catch {}
    }

    function transfer(uint256 fromSeed, uint256 toSeed, uint256 amount) external {
        address from = _actor(fromSeed);
        address to = _actor(toSeed);
        amount = bound(amount, 0, token.balanceOf(from));
        bool fromFrozen = token.frozen(from);
        bool toFrozen = token.frozen(to);

        vm.prank(from);
        try token.transfer(to, amount) {
            assertFalse(fromFrozen, "I10: frozen account sent funds");
            assertFalse(toFrozen, "I10: frozen account received funds");
        } catch {}
    }

    function freeze(uint256 seed) external {
        vm.prank(token.owner());
        token.freeze(_actor(seed));
    }

    function unfreeze(uint256 seed) external {
        vm.prank(token.owner());
        token.unfreeze(_actor(seed));
    }

    function pause() external {
        vm.prank(token.owner());
        try token.pause() {} catch {}
    }

    function unpause() external {
        vm.prank(token.owner());
        try token.unpause() {} catch {}
    }

    function changeOwner(uint256 seed) external {
        address next = _actor(seed);
        vm.prank(token.owner());
        token.transferOwnership(next);
        vm.prank(next);
        token.acceptOwnership();
    }

    // --- recovery ------------------------------------------------------------

    struct Snapshot {
        address owner;
        address caller;
        address account;
        uint256 amount;
        uint256 supply;
        uint256 accountBalance;
        uint256 ownerBalance;
        bool accountFrozen;
        bool ownerFrozen;
        bool paused;
        uint256[] balances;
        bool[] frozen;
    }

    /// Recovery attempted by a random caller, on a random account, for a random amount.
    function recover(uint256 callerSeed, uint256 accountSeed, uint256 amount, bool callerIsOwner) external {
        Snapshot memory s;
        s.owner = token.owner();
        s.caller = callerIsOwner ? s.owner : _actor(callerSeed);
        s.account = _actor(accountSeed);
        // Mostly within the balance, sometimes above it.
        s.amount = bound(amount, 0, token.balanceOf(s.account) + 2);

        // State before the call.
        s.supply = token.totalSupply();
        s.accountBalance = token.balanceOf(s.account);
        s.ownerBalance = token.balanceOf(s.owner);
        s.accountFrozen = token.frozen(s.account);
        s.ownerFrozen = token.frozen(s.owner);
        s.paused = token.paused();
        s.balances = new uint256[](actors.length);
        s.frozen = new bool[](actors.length);
        for (uint256 i = 0; i < actors.length; i++) {
            s.balances[i] = token.balanceOf(actors[i]);
            s.frozen[i] = token.frozen(actors[i]);
        }

        vm.prank(s.caller);
        try token.recoverFrozenFunds(s.account, s.amount) {
            recoverySuccesses++;
            ghostRecovered += s.amount;
            _checkSuccess(s);
        } catch {
            recoveryFailures++;
            for (uint256 i = 0; i < actors.length; i++) {
                assertEq(token.balanceOf(actors[i]), s.balances[i], "I7: failed call changed a balance");
            }
        }

        assertEq(token.totalSupply(), s.supply, "I4: supply changed");
        assertEq(token.owner(), s.owner, "owner changed");
        assertEq(token.paused(), s.paused, "pause state changed");
        for (uint256 i = 0; i < actors.length; i++) {
            assertEq(token.frozen(actors[i]), s.frozen[i], "I8: frozen state changed");
        }
    }

    function _checkSuccess(Snapshot memory s) internal {
        assertEq(s.caller, s.owner, "I1: caller was not the owner");
        assertTrue(s.accountFrozen, "I2: account was not frozen");
        assertFalse(s.ownerFrozen, "I7: owner was frozen");
        assertFalse(s.paused, "I9: contract was paused");
        assertGt(s.amount, 0, "I6: zero amount");
        assertLe(s.amount, s.accountBalance, "I6: amount above balance");

        assertEq(token.balanceOf(s.account), s.accountBalance - s.amount, "I5: account balance");
        assertEq(token.balanceOf(s.owner), s.ownerBalance + s.amount, "I5: owner balance");

        for (uint256 i = 0; i < actors.length; i++) {
            if (actors[i] != s.account && actors[i] != s.owner) {
                assertEq(token.balanceOf(actors[i]), s.balances[i], "I3: third party balance changed");
            }
        }
    }
}

contract FrozenFundsRecoveryInvariantTest is Test {
    StablecoinV3 internal token;
    RecoveryHandler internal handler;
    ProxyAdmin internal proxyAdmin;
    address internal v3Impl;
    address[] internal actors;

    function setUp() public {
        for (uint160 i = 1; i <= 6; i++) {
            actors.push(address(uint160(0x1000) + i));
        }
        address initialOwner = actors[0];

        vm.startPrank(initialOwner);
        Stablecoin v1Impl = new Stablecoin();
        proxyAdmin = new ProxyAdmin();
        TransparentUpgradeableProxy proxy = new TransparentUpgradeableProxy(
            address(v1Impl), address(proxyAdmin), abi.encodeWithSignature("initialize(string,string)", "First Digital USD", "FDUSD")
        );
        StablecoinV2 v2Impl = new StablecoinV2();
        proxyAdmin.upgradeAndCall(proxy, address(v2Impl), abi.encodeWithSelector(StablecoinV2.initializeV2.selector, "First Digital USD"));
        v3Impl = address(new StablecoinV3());
        proxyAdmin.upgrade(proxy, v3Impl);
        vm.stopPrank();

        token = StablecoinV3(address(proxy));
        handler = new RecoveryHandler(token, actors);

        targetContract(address(handler));
    }

    /// I4: supply only moves through mint and burn, never through recovery.
    /// forge-config: default.invariant.fail-on-revert = true
    function invariant_SupplyEqualsMintedMinusBurned() public {
        assertEq(token.totalSupply(), handler.ghostMinted() - handler.ghostBurned());
    }

    /// I3, I7: every token is held by a known account. Nothing leaks anywhere else.
    /// forge-config: default.invariant.fail-on-revert = true
    function invariant_AllTokensAreWithKnownAccounts() public {
        uint256 sum;
        for (uint256 i = 0; i < actors.length; i++) {
            sum += token.balanceOf(actors[i]);
        }
        assertEq(sum, token.totalSupply());
    }

    /// I7: nothing is ever parked in the token, the implementation, the proxy admin or the zero address.
    /// forge-config: default.invariant.fail-on-revert = true
    function invariant_NoTokensInLimbo() public {
        assertEq(token.balanceOf(address(token)), 0);
        assertEq(token.balanceOf(v3Impl), 0);
        assertEq(token.balanceOf(address(proxyAdmin)), 0);
        assertEq(token.balanceOf(address(handler)), 0);
        assertEq(token.balanceOf(address(0)), 0);
    }

    /// forge-config: default.invariant.fail-on-revert = true
    function invariant_CallSummary() public view {
        console.log("recoveries succeeded", handler.recoverySuccesses());
        console.log("recoveries rejected ", handler.recoveryFailures());
    }
}
