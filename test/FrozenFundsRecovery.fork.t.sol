// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "openzeppelin-contracts/contracts/proxy/transparent/ProxyAdmin.sol";
import "openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import "forge-std/Test.sol";
import "../src/StablecoinV3.sol";

/**
 * Rehearses the V3 upgrade against the live FDUSD proxy on a fork.
 *
 * Runs only when FORK_RPC_URL is set, for example:
 *   FORK_RPC_URL=<rpc url> forge test --match-path test/FrozenFundsRecovery.fork.t.sol -vv
 *
 * The token has the same address on Ethereum and BNB Chain.
 */
contract FrozenFundsRecoveryForkTest is Test {
    address internal constant FDUSD = 0xc5f0f7b66764F6ec8C8Dff7BA683102295E16409;

    // EIP-1967 slots
    bytes32 internal constant ADMIN_SLOT = bytes32(uint256(keccak256("eip1967.proxy.admin")) - 1);
    bytes32 internal constant IMPLEMENTATION_SLOT = bytes32(uint256(keccak256("eip1967.proxy.implementation")) - 1);

    StablecoinV3 internal token = StablecoinV3(FDUSD);
    bool internal enabled;

    struct State {
        string name;
        string symbol;
        uint8 decimals;
        uint256 totalSupply;
        address owner;
        address pendingOwner;
        bool paused;
        bool eip7598;
        bytes32 domainSeparator;
        uint256 ownerBalance;
    }

    function setUp() public {
        string memory rpc = vm.envOr("FORK_RPC_URL", string(""));
        if (bytes(rpc).length == 0) return;
        vm.createSelectFork(rpc);
        enabled = true;
    }

    function _state() internal view returns (State memory s) {
        s.name = token.name();
        s.symbol = token.symbol();
        s.decimals = token.decimals();
        s.totalSupply = token.totalSupply();
        s.owner = token.owner();
        s.pendingOwner = token.pendingOwner();
        s.paused = token.paused();
        s.eip7598 = token.eip7598EnableFlag();
        s.domainSeparator = token.DOMAIN_SEPARATOR();
        s.ownerBalance = token.balanceOf(s.owner);
    }

    function _upgrade() internal returns (address impl) {
        ProxyAdmin admin = ProxyAdmin(address(uint160(uint256(vm.load(FDUSD, ADMIN_SLOT)))));
        impl = address(new StablecoinV3());
        vm.prank(admin.owner());
        admin.upgrade(TransparentUpgradeableProxy(payable(FDUSD)), impl);
    }

    function testFork_UpgradeKeepsLiveState() public {
        if (!enabled) return;

        State memory before_ = _state();
        address impl = _upgrade();
        State memory after_ = _state();

        assertEq(address(uint160(uint256(vm.load(FDUSD, IMPLEMENTATION_SLOT)))), impl, "implementation slot");
        assertEq(keccak256(abi.encode(before_)), keccak256(abi.encode(after_)), "state changed by the upgrade");

        console.log("chain id      ", block.chainid);
        console.log("block         ", block.number);
        console.log("owner         ", after_.owner);
        console.log("total supply  ", after_.totalSupply);

        vm.expectRevert("Initializable: contract is already initialized");
        token.initializeV2("Fake");
    }

    function testFork_RecoverAfterUpgrade() public {
        if (!enabled) return;
        _upgrade();

        address owner = token.owner();
        address account = address(0xF120ED);
        uint256 minted = 1_000e18;
        uint256 amount = 400e18;

        vm.startPrank(owner);
        token.mint(account, minted);
        token.freeze(account);

        uint256 supplyBefore = token.totalSupply();
        uint256 ownerBefore = token.balanceOf(owner);

        token.recoverFrozenFunds(account, amount);
        vm.stopPrank();

        assertEq(token.balanceOf(account), minted - amount);
        assertEq(token.balanceOf(owner), ownerBefore + amount);
        assertEq(token.totalSupply(), supplyBefore);
        assertTrue(token.frozen(account));

        // The owner (the multisig) can pass the recovered tokens on with a normal transfer.
        address rightfulOwner = address(0x900D);
        vm.prank(owner);
        token.transfer(rightfulOwner, amount);
        assertEq(token.balanceOf(rightfulOwner), amount);
    }

    function testFork_OnlyOwnerAfterUpgrade() public {
        if (!enabled) return;
        _upgrade();

        address owner = token.owner();
        vm.prank(owner);
        token.freeze(address(0xF120ED));

        vm.prank(address(0xBAD));
        vm.expectRevert("Ownable: caller is not the owner");
        token.recoverFrozenFunds(address(0xF120ED), 1);
    }
}
