// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;
import {
    BurrowHook,
    BurrowBaseHook,
    BurrowHooks,
    BurrowPoolKey,
    BurrowCurrency,
    BurrowSwapParams,
    BurrowBalanceDelta,
    BurrowBalanceDeltaLib,
    BurrowModifyLiquidityParams
} from "../src/BurrowHook.sol";
import {BurrowVaultLite} from "../src/BurrowVaultLite.sol";
import {BurrowValuer} from "../src/BurrowValuer.sol";
import {BurrowVaultFixture, BurrowTestBase, BurrowTestToken, BurrowSepoliaForkFixture, IERC20, IERC721} from "./Fixtures.t.sol";
import {BurrowTestFeeSink} from "./BurrowMarket.t.sol";

contract BurrowHookFactory {
    function deploy(bytes32 salt, address manager, address sqk, address vault, uint16 fee, address owner)
        external
        returns (BurrowHook)
    {
        return new BurrowHook{salt: salt}(manager, sqk, vault, fee, owner);
    }
}

abstract contract BurrowHookMining is BurrowTestBase {
    function _salt(BurrowHookFactory factory, address manager, address sqk, address sink, uint16 fee, address owner)
        internal
        pure
        returns (bytes32 salt, address expected)
    {
        bytes32 hash =
            keccak256(abi.encodePacked(type(BurrowHook).creationCode, abi.encode(manager, sqk, sink, fee, owner)));
        for (uint256 i;; i++) {
            salt = bytes32(i);
            expected =
                address(uint160(uint256(keccak256(abi.encodePacked(bytes1(0xff), address(factory), salt, hash)))));
            // Independently spell out the protocol mask, without using the hook's
            // own flag helper as the oracle for the CREATE2 address assertion.
            if (uint160(expected) & 0x3fff == 0x44) return (salt, expected);
        }
    }

    function _mineAndDeploy(address manager, address sqk, address sink, uint16 fee, address owner)
        internal
        returns (BurrowHook h)
    {
        BurrowHookFactory f = new BurrowHookFactory();
        (bytes32 salt, address expected) = _salt(f, manager, sqk, sink, fee, owner);
        h = f.deploy(salt, manager, sqk, sink, fee, owner);
        assertEq(address(h), expected, "CREATE2 address prediction");
        assertEq(uint256(uint160(address(h)) & 0x3fff), 0x44, "exactly afterSwap and afterSwapReturnDelta bits");
    }
}

contract BurrowHookMockManager {
    uint256 public totalTaken;
    address public lastCurrency;
    address public lastRecipient;
    uint256 public takes;

    function take(BurrowCurrency currency, address to, uint256 amount) external {
        lastCurrency = BurrowCurrency.unwrap(currency);
        lastRecipient = to;
        totalTaken += amount;
        takes++;
        IERC20(lastCurrency).transfer(to, amount);
    }

    function callAfterSwap(
        BurrowHook hook,
        BurrowPoolKey memory key,
        BurrowSwapParams memory params,
        BurrowBalanceDelta delta
    ) external returns (bytes4, int128) {
        return hook.afterSwap(msg.sender, key, params, delta, "");
    }
}

contract BurrowHookTest is BurrowVaultFixture, BurrowHookMining {
    BurrowHook internal hook;
    BurrowHookMockManager internal pool;
    BurrowPoolKey internal key;
    event FeeDonated(bytes32 indexed poolId, uint256 amount);
    event FeeHeld(bytes32 indexed poolId, uint256 amount);
    event Flushed(uint256 amount);

    function setUp() public {
        _setup(0);
        _seed(10000e18);
        pool = new BurrowHookMockManager();
        token.mint(address(pool), 1e30);
        hook = _mineAndDeploy(address(pool), address(token), address(vault), 100, address(this));
        key = BurrowPoolKey(
            BurrowCurrency.wrap(address(nft)), BurrowCurrency.wrap(address(token)), 3000, 60, address(hook)
        );
    }

    function _delta(int128 a0, int128 a1) internal pure returns (BurrowBalanceDelta) {
        return BurrowBalanceDelta.wrap((int256(a0) << 128) | int256(uint256(uint128(a1))));
    }

    function _params(bool zeroForOne) internal pure returns (BurrowSwapParams memory) {
        return BurrowSwapParams(zeroForOne, -100e18, 0);
    }

    function test_CREATE2AddressHasExactlyDeclaredPermissions() public view {
        BurrowHooks.Permissions memory p = hook.getHookPermissions();
        assertTrue(p.afterSwap && p.afterSwapReturnDelta, "required permissions");
        assertTrue(
            !p.beforeInitialize && !p.afterInitialize && !p.beforeAddLiquidity && !p.afterAddLiquidity
                && !p.beforeRemoveLiquidity && !p.afterRemoveLiquidity && !p.beforeSwap && !p.beforeDonate
                && !p.afterDonate && !p.beforeSwapReturnDelta && !p.afterAddLiquidityReturnDelta
                && !p.afterRemoveLiquidityReturnDelta,
            "undeclared flag enabled"
        );
        assertEq(hook.hookFlags(), 0x44, "declared flags");
        assertEq(uint160(address(hook)) & 0x3fff, 0x44, "actual address flags");
    }

    function test_ConstructorRejectsAnAddressWithWrongFlags() public {
        BurrowHookFactory f = new BurrowHookFactory();
        bytes32 hash = keccak256(
            abi.encodePacked(
                type(BurrowHook).creationCode,
                abi.encode(address(pool), address(token), address(vault), uint16(100), address(this))
            )
        );
        bytes32 salt;
        address expected = address(uint160(uint256(keccak256(abi.encodePacked(bytes1(0xff), address(f), salt, hash)))));
        if (uint160(expected) & 0x3fff == 0x44) {
            salt = bytes32(uint256(1));
            expected = address(uint160(uint256(keccak256(abi.encodePacked(bytes1(0xff), address(f), salt, hash)))));
        }
        assertTrue(uint160(expected) & 0x3fff != 0x44, "invalid deployment fixture");
        vm.expectRevert(abi.encodeWithSelector(BurrowHooks.HookAddressNotValid.selector, expected));
        f.deploy(salt, address(pool), address(token), address(vault), 100, address(this));
    }

    function test_SQKOutputSkimTakesAndDonatesToRealVault() public {
        uint256 assets = vault.totalAssets();
        uint256 supply = vault.totalSupply();
        vm.expectEmit(true, false, false, true, address(hook));
        emit FeeDonated(keccak256(abi.encode(key)), 1e18);
        (bytes4 selector, int128 delta) = pool.callAfterSwap(hook, key, _params(true), _delta(-110e18, 100e18));
        assertEq(uint32(selector), uint32(BurrowBaseHook.afterSwap.selector), "afterSwap selector");
        assertEq(uint256(uint128(delta)), 1e18, "positive unspecified currency delta");
        assertEq(pool.totalTaken(), 1e18, "fee taken from pool");
        assertEq(pool.lastCurrency(), address(token), "SQK currency");
        assertEq(pool.lastRecipient(), address(hook), "hook receives fee");
        assertEq(vault.totalAssets(), assets + 1e18, "donation reaches vault");
        assertEq(vault.totalSupply(), supply, "fee mints no shares");
        assertEq(token.balanceOf(address(hook)), 0, "all fees forwarded");
        assertEq(token.allowance(address(hook), address(vault)), 0, "donation consumes exact allowance");
    }

    function test_SQKAsCurrencyZeroUsesAmountZero() public {
        key.currency0 = BurrowCurrency.wrap(address(token));
        key.currency1 = BurrowCurrency.wrap(address(nft));
        (, int128 delta) = pool.callAfterSwap(hook, key, _params(false), _delta(75e18, -100e18));
        assertEq(uint256(uint128(delta)), 0.75e18, "currency zero output");
        assertEq(pool.totalTaken(), 0.75e18, "SQK amount zero fee");
    }

    function test_NonSQKOutputNonPositiveOutputAndDustTakeNothing() public {
        pool.callAfterSwap(hook, key, _params(false), _delta(100e18, -100e18));
        pool.callAfterSwap(hook, key, _params(true), _delta(-100e18, 0));
        pool.callAfterSwap(hook, key, _params(true), _delta(-100e18, -1));
        pool.callAfterSwap(hook, key, _params(true), _delta(-100e18, 99));
        assertEq(pool.takes(), 0, "no take without positive fee on SQK output");
        hook.setHookFeeBps(0);
        pool.callAfterSwap(hook, key, _params(true), _delta(-100e18, 100e18));
        assertEq(pool.takes(), 0, "zero fee no take");
    }

    /// forge-config: default.fuzz.runs = 1000
    function testFuzz_FeeBoundAndBalanceConservation(uint128 outputRaw, uint16 feeRaw, bool direction) public {
        uint256 amount = bound(outputRaw, 1, 1e27);
        uint16 fee = uint16(bound(feeRaw, 0, 100));
        hook.setHookFeeBps(fee);
        if (!direction) {
            key.currency0 = BurrowCurrency.wrap(address(token));
            key.currency1 = BurrowCurrency.wrap(address(nft));
        }
        uint256 expected = amount * fee / 10000;
        uint256 assets = vault.totalAssets();
        uint256 poolBalance = token.balanceOf(address(pool));
        (, int128 delta) = pool.callAfterSwap(
            hook,
            key,
            _params(direction),
            direction ? _delta(-1, int128(int256(amount))) : _delta(int128(int256(amount)), -1)
        );
        assertEq(uint256(uint128(delta)), expected, "floor fee delta");
        assertLe(expected, amount / 100, "one percent cap");
        assertEq(vault.totalAssets() - assets, expected, "fee to vault");
        assertEq(poolBalance - token.balanceOf(address(pool)), expected, "pool exactly debited");
        assertEq(token.balanceOf(address(hook)), 0, "no fee residue");
    }

    function test_OnlyPoolManagerMayInvokeAfterSwap() public {
        vm.expectRevert(BurrowBaseHook.NotPoolManager.selector);
        hook.afterSwap(address(this), key, _params(true), _delta(-1, 100e18), "");
        vm.expectRevert(BurrowBaseHook.NotPoolManager.selector);
        vm.prank(alice);
        hook.afterSwap(alice, key, _params(true), _delta(-1, 100e18), "");
    }

    function test_AllUnimplementedCallbacksRevert() public {
        BurrowModifyLiquidityParams memory lp = BurrowModifyLiquidityParams(-60, 60, 1, bytes32(0));
        BurrowBalanceDelta d = _delta(0, 0);
        vm.expectRevert(BurrowBaseHook.HookNotImplemented.selector);
        hook.beforeInitialize(alice, key, 1);
        vm.expectRevert(BurrowBaseHook.HookNotImplemented.selector);
        hook.afterInitialize(alice, key, 1, 0);
        vm.expectRevert(BurrowBaseHook.HookNotImplemented.selector);
        hook.beforeAddLiquidity(alice, key, lp, "");
        vm.expectRevert(BurrowBaseHook.HookNotImplemented.selector);
        hook.afterAddLiquidity(alice, key, lp, d, d, "");
        vm.expectRevert(BurrowBaseHook.HookNotImplemented.selector);
        hook.beforeRemoveLiquidity(alice, key, lp, "");
        vm.expectRevert(BurrowBaseHook.HookNotImplemented.selector);
        hook.afterRemoveLiquidity(alice, key, lp, d, d, "");
        vm.expectRevert(BurrowBaseHook.HookNotImplemented.selector);
        hook.beforeSwap(alice, key, _params(true), "");
        vm.expectRevert(BurrowBaseHook.HookNotImplemented.selector);
        hook.beforeDonate(alice, key, 1, 1, "");
        vm.expectRevert(BurrowBaseHook.HookNotImplemented.selector);
        hook.afterDonate(alice, key, 1, 1, "");
    }

    function test_RefusedDonationIsHeldThenAnyoneCanFlushIt() public {
        BurrowTestFeeSink sink = new BurrowTestFeeSink(token);
        BurrowHook h = _mineAndDeploy(address(pool), address(token), address(sink), 100, address(this));
        key.hooks = address(h);
        sink.setFail(true);
        vm.expectEmit(true, false, false, true, address(h));
        emit FeeHeld(keccak256(abi.encode(key)), 1e18);
        (, int128 delta) = pool.callAfterSwap(h, key, _params(true), _delta(-1, 100e18));
        assertEq(uint256(uint128(delta)), 1e18, "fee credit retained");
        assertEq(token.balanceOf(address(h)), 1e18, "held fee");
        assertEq(token.allowance(address(h), address(sink)), 0, "failed sink allowance revoked");
        vm.expectRevert(BurrowTestFeeSink.DonationRejected.selector);
        h.flush();
        assertEq(token.balanceOf(address(h)), 1e18, "failed flush preserves funds");
        sink.setFail(false);
        vm.expectEmit(false, false, false, true, address(h));
        emit Flushed(1e18);
        vm.prank(alice);
        h.flush();
        assertEq(token.balanceOf(address(h)), 0, "flushed all fees");
        assertEq(sink.donated(), 1e18, "fee delivered once");
        vm.expectRevert(BurrowHook.NothingToFlush.selector);
        h.flush();
    }

    function test_ApprovalFailureIsAtomicAndFlushCannotReenter() public {
        token.setRejectApproval(true);
        uint256 before = token.balanceOf(address(pool));
        vm.expectRevert(BurrowHook.ApproveFailed.selector);
        pool.callAfterSwap(hook, key, _params(true), _delta(-1, 100e18));
        assertEq(token.balanceOf(address(pool)), before, "failed approval leaked take");
        token.setRejectApproval(false);
        token.mint(address(hook), 1e18);
        token.setCallback(address(hook), abi.encodeWithSignature("flush()"));
        hook.flush();
        assertTrue(!token.callbackSucceeded(), "reentered flush");
        assertEq(
            keccak256(token.callbackResult()),
            keccak256(abi.encodeWithSignature("ReentrancyGuardReentrantCall()")),
            "guard failure"
        );
    }

    function test_ConstructorAndSetterCapsAndUnauthorizedOwnerActions() public {
        BurrowHookFactory f = new BurrowHookFactory();
        (bytes32 salt,) = _salt(f, address(pool), address(token), address(vault), 101, address(this));
        vm.expectRevert(abi.encodeWithSelector(BurrowHook.FeeTooHigh.selector, uint16(101), uint16(100)));
        f.deploy(salt, address(pool), address(token), address(vault), 101, address(this));
        for (uint256 i; i < 3; i++) {
            address manager_ = i == 0 ? address(0) : address(pool);
            address token_ = i == 1 ? address(0) : address(token);
            address vault_ = i == 2 ? address(0) : address(vault);
            (salt,) = _salt(f, manager_, token_, vault_, 0, address(this));
            vm.expectRevert(BurrowHook.ZeroAddress.selector);
            f.deploy(salt, manager_, token_, vault_, 0, address(this));
        }
        (salt,) = _salt(f, address(pool), address(token), address(vault), 0, address(0));
        vm.expectRevert(abi.encodeWithSignature("OwnableInvalidOwner(address)", address(0)));
        f.deploy(salt, address(pool), address(token), address(vault), 0, address(0));
        vm.expectRevert(abi.encodeWithSelector(BurrowHook.FeeTooHigh.selector, uint16(101), uint16(100)));
        hook.setHookFeeBps(101);
        vm.expectRevert(abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", alice));
        vm.prank(alice);
        hook.setHookFeeBps(0);
        hook.transferOwnership(alice);
        vm.expectRevert(abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", alice));
        vm.prank(alice);
        hook.setHookFeeBps(0);
        vm.prank(alice);
        hook.acceptOwnership();
        vm.prank(alice);
        hook.setHookFeeBps(0);
        assertEq(hook.hookFeeBps(), 0, "new owner can set capped fee");
    }
}

contract BurrowHookHandler is BurrowTestBase {
    BurrowHook public immutable hook;
    BurrowHookMockManager public immutable manager;
    BurrowTestToken public immutable token;
    BurrowTestFeeSink public immutable sink;
    uint256 public expectedFees;
    uint256 public unsolicited;
    bool public refusing;
    bool public badDelta;

    constructor(BurrowHook h, BurrowHookMockManager m, BurrowTestToken t, BurrowTestFeeSink s) {
        hook = h;
        manager = m;
        token = t;
        sink = s;
    }

    function acceptOwnership() external {
        hook.acceptOwnership();
    }

    function swap(uint128 raw, bool sqkOutput, bool direction) external {
        uint256 amount = bound(raw, 1, 1e24);
        uint256 charge = sqkOutput ? amount * hook.hookFeeBps() / 10000 : 0;
        address other = address(sink);
        BurrowPoolKey memory key = BurrowPoolKey(
            BurrowCurrency.wrap(direction ? other : address(token)),
            BurrowCurrency.wrap(direction ? address(token) : other),
            3000,
            60,
            address(hook)
        );
        if (!sqkOutput) direction = !direction;
        BurrowBalanceDelta d = BurrowBalanceDelta.wrap(
            direction
                ? (int256(-1) << 128) | int256(amount)
                : (int256(amount) << 128) | int256(uint256(type(uint128).max))
        );
        (, int128 delta) = manager.callAfterSwap(hook, key, BurrowSwapParams(direction, -1, 0), d);
        if (delta < 0 || uint256(uint128(delta)) != charge) badDelta = true;
        expectedFees += charge;
    }

    function setFee(uint16 raw) external {
        hook.setHookFeeBps(uint16(bound(raw, 0, 100)));
    }

    function refuse(bool value) external {
        refusing = value;
        sink.setFail(value);
    }

    function sendTokens(uint128 raw) external {
        uint256 amount = bound(raw, 1, 1e20);
        token.mint(address(hook), amount);
        unsolicited += amount;
    }

    function flush() external {
        if (!refusing && token.balanceOf(address(hook)) > 0) hook.flush();
    }
}

contract BurrowHookInvariantTest is BurrowHookMining {
    BurrowHook internal hook;
    BurrowHookMockManager internal manager;
    BurrowTestToken internal token;
    BurrowTestFeeSink internal sink;
    BurrowHookHandler internal handler;

    function setUp() public {
        token = new BurrowTestToken();
        manager = new BurrowHookMockManager();
        sink = new BurrowTestFeeSink(token);
        token.mint(address(manager), 1e30);
        hook = _mineAndDeploy(address(manager), address(token), address(sink), 100, address(this));
        handler = new BurrowHookHandler(hook, manager, token, sink);
        hook.transferOwnership(address(handler));
        handler.acceptOwnership();
    }

    struct FuzzSelector {
        address addr;
        bytes4[] selectors;
    }

    function targetContracts() public view returns (address[] memory a) {
        a = new address[](1);
        a[0] = address(handler);
    }

    function targetSelectors() public view returns (FuzzSelector[] memory a) {
        a = new FuzzSelector[](1);
        bytes4[] memory s = new bytes4[](5);
        s[0] = handler.swap.selector;
        s[1] = handler.setFee.selector;
        s[2] = handler.refuse.selector;
        s[3] = handler.sendTokens.selector;
        s[4] = handler.flush.selector;
        a[0] = FuzzSelector(address(handler), s);
    }

    /// forge-config: default.invariant.runs = 256
    /// forge-config: default.invariant.depth = 64
    /// forge-config: default.invariant.fail-on-revert = true
    function invariant_FeesAreDeliveredOrRecoverableAndNeverLost() public view {
        assertTrue(!handler.badDelta(), "fee delta incorrect");
        assertEq(manager.totalTaken(), handler.expectedFees(), "pool debits match skims");
        assertEq(
            token.balanceOf(address(hook)) + sink.donated(),
            handler.expectedFees() + handler.unsolicited(),
            "held plus donated fee conservation"
        );
        assertEq(token.balanceOf(address(sink)), sink.donated(), "sink backing");
        assertEq(token.allowance(address(hook), address(sink)), 0, "no residual sink approval");
        assertEq(token.balanceOf(address(manager)) + manager.totalTaken(), 1e30, "pool conservation");
        assertLe(hook.hookFeeBps(), 100, "fee cap");
    }
}

// Narrow, independently encoded v4 ABI. The fork router settles every delta in
// one unlock transaction, matching PoolManager's transient accounting lifetime.
interface BurrowRealPoolManager {
    function initialize(BurrowPoolKey memory key, uint160 sqrtPriceX96) external returns (int24);
    function unlock(bytes calldata data) external returns (bytes memory);
    function modifyLiquidity(
        BurrowPoolKey memory key,
        BurrowModifyLiquidityParams memory params,
        bytes calldata hookData
    ) external returns (BurrowBalanceDelta, BurrowBalanceDelta);
    function swap(BurrowPoolKey memory key, BurrowSwapParams memory params, bytes calldata hookData)
        external
        returns (BurrowBalanceDelta);
    function sync(BurrowCurrency currency) external;
    function settle() external payable returns (uint256);
    function take(BurrowCurrency currency, address to, uint256 amount) external;
}

contract BurrowForkSwapRouter {
    using BurrowBalanceDeltaLib for BurrowBalanceDelta;
    BurrowRealPoolManager public immutable manager;
    BurrowPoolKey private key;
    error NotManager();

    constructor(address m, BurrowPoolKey memory k) {
        manager = BurrowRealPoolManager(m);
        key = k;
    }

    function seed(uint128 liquidity) external {
        manager.unlock(abi.encode(uint8(0), uint256(liquidity), false));
    }

    function swap(uint256 amount, bool zeroForOne) external returns (BurrowBalanceDelta) {
        return abi.decode(manager.unlock(abi.encode(uint8(1), amount, zeroForOne)), (BurrowBalanceDelta));
    }

    function unlockCallback(bytes calldata data) external returns (bytes memory) {
        if (msg.sender != address(manager)) revert NotManager();
        (uint8 action, uint256 amount, bool zeroForOne) = abi.decode(data, (uint8, uint256, bool));
        BurrowBalanceDelta delta;
        if (action == 0) {
            (delta,) =
                manager.modifyLiquidity(key, BurrowModifyLiquidityParams(-600, 600, int256(amount), bytes32(0)), "");
        } else {
            delta = manager.swap(
                key,
                BurrowSwapParams(
                    zeroForOne,
                    -int256(amount),
                    zeroForOne ? uint160(4295128740) : uint160(1461446703485210103287273052203988822378723970341)
                ),
                ""
            );
        }
        _settle(key.currency0, delta.amount0());
        _settle(key.currency1, delta.amount1());
        return abi.encode(delta);
    }

    function _settle(BurrowCurrency currency, int128 amount) internal {
        if (amount < 0) {
            manager.sync(currency);
            IERC20(BurrowCurrency.unwrap(currency)).transfer(address(manager), uint256(-int256(amount)));
            manager.settle();
        } else if (amount > 0) {
            manager.take(currency, address(this), uint256(uint128(amount)));
        }
    }
}

contract BurrowHookSepoliaForkTest is BurrowSepoliaForkFixture, BurrowHookMining {
    function testFork_SepoliaRealPoolSwapSettlesFeeIntoVault() public {
        _fork();
        (BurrowVaultLite v,) = _liveVault();
        address lender = addr("fork hook lender");
        deal(SQK, lender, 10000e18);
        vm.startPrank(lender);
        IERC20(SQK).approve(address(v), type(uint256).max);
        v.deposit(10000e18, 0);
        vm.stopPrank();
        BurrowHook h = _mineAndDeploy(MANAGER, SQK, address(v), 100, address(this));
        BurrowTestToken other = new BurrowTestToken();
        bool sqkIsOne = SQK > address(other);
        BurrowPoolKey memory k = BurrowPoolKey(
            BurrowCurrency.wrap(sqkIsOne ? address(other) : SQK),
            BurrowCurrency.wrap(sqkIsOne ? SQK : address(other)),
            3000,
            60,
            address(h)
        );
        BurrowRealPoolManager(MANAGER).initialize(k, uint160(1 << 96));
        BurrowForkSwapRouter router = new BurrowForkSwapRouter(MANAGER, k);
        deal(SQK, address(router), 1e24);
        other.mint(address(router), 1e24);
        router.seed(1e24);
        uint256 assets = v.totalAssets();
        uint256 shares = v.totalSupply();
        uint256 buyerBefore = IERC20(SQK).balanceOf(address(router));
        BurrowBalanceDelta delta = router.swap(100e18, sqkIsOne);
        int128 received = sqkIsOne ? BurrowBalanceDeltaLib.amount1(delta) : BurrowBalanceDeltaLib.amount0(delta);
        uint256 fee = v.totalAssets() - assets;
        assertTrue(fee > 0, "real PoolManager paid SQK fee");
        assertTrue(received > 0, "swap paid SQK output");
        assertEq(fee, (uint256(uint128(received)) + fee) / 100, "fee is one percent of pre-hook output");
        assertEq(
            IERC20(SQK).balanceOf(address(router)) - buyerBefore,
            uint256(uint128(received)),
            "net swap delta reconciles"
        );
        assertEq(v.totalSupply(), shares, "hook fee does not mint");
        assertEq(IERC20(SQK).balanceOf(address(h)), 0, "real fee forwarded");
        assets = v.totalAssets();
        router.swap(50e18, !sqkIsOne);
        assertEq(v.totalAssets(), assets, "non-SQK output takes no fee");
    }
}

interface BurrowLivePositionActions {
    function nextTokenId() external view returns (uint256);
    function modifyLiquidities(bytes calldata unlockData, uint256 deadline) external payable;
    function permit2() external view returns (address);
}

interface BurrowLivePermit2 {
    function approve(address token, address spender, uint160 amount, uint48 expiration) external;
    function DOMAIN_SEPARATOR() external view returns (bytes32);
}
