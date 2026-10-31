// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

// -----------------------------------------------------------------------------------------------
// This file is self-contained on purpose: the repository vendors no v4-core, v4-periphery or
// OpenZeppelin, and the build runs offline. The pieces below are minimal, ABI-compatible ports of
// the Uniswap v4 types (PoolKey, SwapParams, BalanceDelta, Currency), the v4 Hooks permission
// flags, v4-periphery's BaseHook, and OpenZeppelin's SafeERC20.forceApprove, ReentrancyGuard and
// Ownable2Step. Names are prefixed so they never clash with the real libraries when the
// integrator adds them. Encodings, selectors and flag bits match Uniswap v4 exactly.
// -----------------------------------------------------------------------------------------------

/// @dev Uniswap v4 `Currency` (an address, native ETH is address(0)).
type BurrowCurrency is address;

/// @dev Uniswap v4 `BalanceDelta`: amount0 in the upper 128 bits, amount1 in the lower 128 bits.
type BurrowBalanceDelta is int256;

/// @dev Uniswap v4 `PoolKey`.
struct BurrowPoolKey {
    BurrowCurrency currency0;
    BurrowCurrency currency1;
    uint24 fee;
    int24 tickSpacing;
    address hooks;
}

/// @dev Uniswap v4 `SwapParams` (IPoolManager.SwapParams / PoolOperation.SwapParams).
struct BurrowSwapParams {
    bool zeroForOne;
    int256 amountSpecified;
    uint160 sqrtPriceLimitX96;
}

/// @dev Uniswap v4 `ModifyLiquidityParams`.
struct BurrowModifyLiquidityParams {
    int24 tickLower;
    int24 tickUpper;
    int256 liquidityDelta;
    bytes32 salt;
}

/// @dev Uniswap v4 `BeforeSwapDelta`.
type BurrowBeforeSwapDelta is int256;

library BurrowBalanceDeltaLib {
    function amount0(BurrowBalanceDelta d) internal pure returns (int128 a0) {
        assembly ("memory-safe") {
            a0 := sar(128, d)
        }
    }

    function amount1(BurrowBalanceDelta d) internal pure returns (int128 a1) {
        assembly ("memory-safe") {
            a1 := signextend(15, d)
        }
    }
}

library BurrowPoolIdLib {
    /// @dev Same as v4 PoolIdLibrary.toId: keccak256 of the 5-word PoolKey.
    function toId(BurrowPoolKey memory key) internal pure returns (bytes32 id) {
        assembly ("memory-safe") {
            id := keccak256(key, 0xa0)
        }
    }
}

/// @dev The subset of the v4 PoolManager this hook calls.
interface IBurrowPoolManager {
    function take(BurrowCurrency currency, address to, uint256 amount) external;
}

/// @dev Uniswap v4 `Hooks.Permissions` and flag bits (v4-core src/libraries/Hooks.sol).
library BurrowHooks {
    uint160 internal constant ALL_HOOK_MASK = uint160((1 << 14) - 1);

    uint160 internal constant BEFORE_INITIALIZE_FLAG = 1 << 13;
    uint160 internal constant AFTER_INITIALIZE_FLAG = 1 << 12;
    uint160 internal constant BEFORE_ADD_LIQUIDITY_FLAG = 1 << 11;
    uint160 internal constant AFTER_ADD_LIQUIDITY_FLAG = 1 << 10;
    uint160 internal constant BEFORE_REMOVE_LIQUIDITY_FLAG = 1 << 9;
    uint160 internal constant AFTER_REMOVE_LIQUIDITY_FLAG = 1 << 8;
    uint160 internal constant BEFORE_SWAP_FLAG = 1 << 7;
    uint160 internal constant AFTER_SWAP_FLAG = 1 << 6;
    uint160 internal constant BEFORE_DONATE_FLAG = 1 << 5;
    uint160 internal constant AFTER_DONATE_FLAG = 1 << 4;
    uint160 internal constant BEFORE_SWAP_RETURNS_DELTA_FLAG = 1 << 3;
    uint160 internal constant AFTER_SWAP_RETURNS_DELTA_FLAG = 1 << 2;
    uint160 internal constant AFTER_ADD_LIQUIDITY_RETURNS_DELTA_FLAG = 1 << 1;
    uint160 internal constant AFTER_REMOVE_LIQUIDITY_RETURNS_DELTA_FLAG = 1 << 0;

    struct Permissions {
        bool beforeInitialize;
        bool afterInitialize;
        bool beforeAddLiquidity;
        bool afterAddLiquidity;
        bool beforeRemoveLiquidity;
        bool afterRemoveLiquidity;
        bool beforeSwap;
        bool afterSwap;
        bool beforeDonate;
        bool afterDonate;
        bool beforeSwapReturnDelta;
        bool afterSwapReturnDelta;
        bool afterAddLiquidityReturnDelta;
        bool afterRemoveLiquidityReturnDelta;
    }

    error HookAddressNotValid(address hooks);

    function toFlags(Permissions memory p) internal pure returns (uint160 flags) {
        if (p.beforeInitialize) flags |= BEFORE_INITIALIZE_FLAG;
        if (p.afterInitialize) flags |= AFTER_INITIALIZE_FLAG;
        if (p.beforeAddLiquidity) flags |= BEFORE_ADD_LIQUIDITY_FLAG;
        if (p.afterAddLiquidity) flags |= AFTER_ADD_LIQUIDITY_FLAG;
        if (p.beforeRemoveLiquidity) flags |= BEFORE_REMOVE_LIQUIDITY_FLAG;
        if (p.afterRemoveLiquidity) flags |= AFTER_REMOVE_LIQUIDITY_FLAG;
        if (p.beforeSwap) flags |= BEFORE_SWAP_FLAG;
        if (p.afterSwap) flags |= AFTER_SWAP_FLAG;
        if (p.beforeDonate) flags |= BEFORE_DONATE_FLAG;
        if (p.afterDonate) flags |= AFTER_DONATE_FLAG;
        if (p.beforeSwapReturnDelta) flags |= BEFORE_SWAP_RETURNS_DELTA_FLAG;
        if (p.afterSwapReturnDelta) flags |= AFTER_SWAP_RETURNS_DELTA_FLAG;
        if (p.afterAddLiquidityReturnDelta) flags |= AFTER_ADD_LIQUIDITY_RETURNS_DELTA_FLAG;
        if (p.afterRemoveLiquidityReturnDelta) flags |= AFTER_REMOVE_LIQUIDITY_RETURNS_DELTA_FLAG;
    }

    /// @dev Equivalent to v4 Hooks.validateHookPermissions: every one of the 14 low address bits
    /// must equal the declared permission.
    function validateHookPermissions(address self, Permissions memory p) internal pure {
        if (uint160(self) & ALL_HOOK_MASK != toFlags(p)) revert HookAddressNotValid(self);
    }
}

/// @dev Port of v4-periphery `BaseHook`: validates its own address against getHookPermissions at
/// construction, gates every callback to the PoolManager and reverts on any unimplemented hook.
abstract contract BurrowBaseHook {
    error NotPoolManager();
    error HookNotImplemented();

    IBurrowPoolManager public immutable poolManager;

    constructor(IBurrowPoolManager _poolManager) {
        poolManager = _poolManager;
        validateHookAddress(this);
    }

    modifier onlyPoolManager() {
        if (msg.sender != address(poolManager)) revert NotPoolManager();
        _;
    }

    function getHookPermissions() public pure virtual returns (BurrowHooks.Permissions memory);

    function validateHookAddress(BurrowBaseHook _this) internal pure virtual {
        BurrowHooks.validateHookPermissions(address(_this), getHookPermissions());
    }

    function beforeInitialize(address, BurrowPoolKey calldata, uint160) external virtual returns (bytes4) {
        revert HookNotImplemented();
    }

    function afterInitialize(address, BurrowPoolKey calldata, uint160, int24) external virtual returns (bytes4) {
        revert HookNotImplemented();
    }

    function beforeAddLiquidity(address, BurrowPoolKey calldata, BurrowModifyLiquidityParams calldata, bytes calldata)
        external
        virtual
        returns (bytes4)
    {
        revert HookNotImplemented();
    }

    function afterAddLiquidity(
        address,
        BurrowPoolKey calldata,
        BurrowModifyLiquidityParams calldata,
        BurrowBalanceDelta,
        BurrowBalanceDelta,
        bytes calldata
    ) external virtual returns (bytes4, BurrowBalanceDelta) {
        revert HookNotImplemented();
    }

    function beforeRemoveLiquidity(
        address,
        BurrowPoolKey calldata,
        BurrowModifyLiquidityParams calldata,
        bytes calldata
    ) external virtual returns (bytes4) {
        revert HookNotImplemented();
    }

    function afterRemoveLiquidity(
        address,
        BurrowPoolKey calldata,
        BurrowModifyLiquidityParams calldata,
        BurrowBalanceDelta,
        BurrowBalanceDelta,
        bytes calldata
    ) external virtual returns (bytes4, BurrowBalanceDelta) {
        revert HookNotImplemented();
    }

    function beforeSwap(address, BurrowPoolKey calldata, BurrowSwapParams calldata, bytes calldata)
        external
        virtual
        returns (bytes4, BurrowBeforeSwapDelta, uint24)
    {
        revert HookNotImplemented();
    }

    function afterSwap(
        address sender,
        BurrowPoolKey calldata key,
        BurrowSwapParams calldata params,
        BurrowBalanceDelta delta,
        bytes calldata hookData
    ) external onlyPoolManager returns (bytes4, int128) {
        return _afterSwap(sender, key, params, delta, hookData);
    }

    function beforeDonate(address, BurrowPoolKey calldata, uint256, uint256, bytes calldata)
        external
        virtual
        returns (bytes4)
    {
        revert HookNotImplemented();
    }

    function afterDonate(address, BurrowPoolKey calldata, uint256, uint256, bytes calldata)
        external
        virtual
        returns (bytes4)
    {
        revert HookNotImplemented();
    }

    function _afterSwap(address, BurrowPoolKey calldata, BurrowSwapParams calldata, BurrowBalanceDelta, bytes calldata)
        internal
        virtual
        returns (bytes4, int128)
    {
        revert HookNotImplemented();
    }
}

/// @dev Minimal ERC20 surface the hook needs.
interface IBurrowHookERC20 {
    function balanceOf(address account) external view returns (uint256);
    function approve(address spender, uint256 value) external returns (bool);
}

/// @notice The single function of BurrowVault this hook relies on: pull SQK from the caller and
/// raise the bSQK share price without minting.
interface IBurrowVaultFeeSink {
    function donate(uint256 amount) external;
}

/// @dev Port of OpenZeppelin ReentrancyGuard (v5 semantics).
abstract contract BurrowHookReentrancyGuard {
    uint256 private constant NOT_ENTERED = 1;
    uint256 private constant ENTERED = 2;
    uint256 private _status = NOT_ENTERED;

    error ReentrancyGuardReentrantCall();

    modifier nonReentrant() {
        if (_status == ENTERED) revert ReentrancyGuardReentrantCall();
        _status = ENTERED;
        _;
        _status = NOT_ENTERED;
    }
}

/// @dev Port of OpenZeppelin Ownable + Ownable2Step (v5 semantics, same errors and events).
abstract contract BurrowHookOwnable2Step {
    address private _owner;
    address private _pendingOwner;

    error OwnableUnauthorizedAccount(address account);
    error OwnableInvalidOwner(address owner);

    event OwnershipTransferStarted(address indexed previousOwner, address indexed newOwner);
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    constructor(address initialOwner) {
        if (initialOwner == address(0)) revert OwnableInvalidOwner(address(0));
        _transferOwnership(initialOwner);
    }

    modifier onlyOwner() {
        if (msg.sender != _owner) revert OwnableUnauthorizedAccount(msg.sender);
        _;
    }

    function owner() public view returns (address) {
        return _owner;
    }

    function pendingOwner() public view returns (address) {
        return _pendingOwner;
    }

    function transferOwnership(address newOwner) external onlyOwner {
        _pendingOwner = newOwner;
        emit OwnershipTransferStarted(_owner, newOwner);
    }

    function acceptOwnership() external {
        if (msg.sender != _pendingOwner) revert OwnableUnauthorizedAccount(msg.sender);
        _transferOwnership(msg.sender);
    }

    function _transferOwnership(address newOwner) private {
        delete _pendingOwner;
        address old = _owner;
        _owner = newOwner;
        emit OwnershipTransferred(old, newOwner);
    }
}

/// @title BurrowHook
/// @notice Uniswap v4 hook for the SQK pool. After every exact-input swap whose output currency is
/// SQK it skims `hookFeeBps` of the output, takes it from the PoolManager and donates it to the
/// Burrow vault, raising the bSQK share price. Swaps that do not pay out SQK are left untouched.
/// @dev UNAUDITED, TESTNET ONLY. The hook address must carry exactly the AFTER_SWAP and
/// AFTER_SWAP_RETURNS_DELTA flags (0x44 in the low 14 bits); deploy it through CREATE2 with a salt
/// mined by HookMiner. A v4 afterSwap delta can only adjust the unspecified currency, so on
/// exact-output swaps (where the SQK output is the specified amount) no fee is taken.
contract BurrowHook is BurrowBaseHook, BurrowHookReentrancyGuard, BurrowHookOwnable2Step {
    using BurrowBalanceDeltaLib for BurrowBalanceDelta;
    using BurrowPoolIdLib for BurrowPoolKey;

    /// @notice Hard cap on the hook fee: 1 percent of the SQK output.
    uint16 public constant MAX_HOOK_FEE_BPS = 100;
    uint256 internal constant BPS = 10_000;

    /// @notice The SQK token, the only currency this hook ever skims.
    IBurrowHookERC20 public immutable sqk;
    /// @notice The Burrow vault every fee is donated to. Fixed at construction.
    IBurrowVaultFeeSink public immutable vault;

    /// @notice Fee skimmed from SQK output, in basis points, at most MAX_HOOK_FEE_BPS.
    uint16 public hookFeeBps;

    error ZeroAddress();
    error FeeTooHigh(uint16 feeBps, uint16 maxBps);
    error NothingToFlush();
    error ApproveFailed();

    event HookFeeSet(uint16 oldFeeBps, uint16 newFeeBps);
    event FeeDonated(bytes32 indexed poolId, uint256 amount);
    /// @notice Emitted when the vault refused a donation; the fee stays here until flush().
    event FeeHeld(bytes32 indexed poolId, uint256 amount);
    event Flushed(uint256 amount);

    /// @param poolManager_ Uniswap v4 PoolManager (Sepolia 0xE03A1074c86CFeDd5C142C4F04F1a1536e203543).
    /// @param sqk_ SQK token (Sepolia 0x5501e1fa81be1c3f49225fa7668da0245d07db60).
    /// @param vault_ BurrowVault, the fee sink.
    /// @param hookFeeBps_ Initial fee, at most MAX_HOOK_FEE_BPS.
    /// @param owner_ Owner allowed to tune hookFeeBps within its cap.
    constructor(address poolManager_, address sqk_, address vault_, uint16 hookFeeBps_, address owner_)
        BurrowBaseHook(IBurrowPoolManager(poolManager_))
        BurrowHookOwnable2Step(owner_)
    {
        if (poolManager_ == address(0) || sqk_ == address(0) || vault_ == address(0)) revert ZeroAddress();
        if (hookFeeBps_ > MAX_HOOK_FEE_BPS) revert FeeTooHigh(hookFeeBps_, MAX_HOOK_FEE_BPS);
        sqk = IBurrowHookERC20(sqk_);
        vault = IBurrowVaultFeeSink(vault_);
        hookFeeBps = hookFeeBps_;
        emit HookFeeSet(0, hookFeeBps_);
    }

    /// @notice afterSwap and afterSwapReturnDelta only.
    function getHookPermissions() public pure override returns (BurrowHooks.Permissions memory) {
        return BurrowHooks.Permissions({
            beforeInitialize: false,
            afterInitialize: false,
            beforeAddLiquidity: false,
            afterAddLiquidity: false,
            beforeRemoveLiquidity: false,
            afterRemoveLiquidity: false,
            beforeSwap: false,
            afterSwap: true,
            beforeDonate: false,
            afterDonate: false,
            beforeSwapReturnDelta: false,
            afterSwapReturnDelta: true,
            afterAddLiquidityReturnDelta: false,
            afterRemoveLiquidityReturnDelta: false
        });
    }

    /// @notice The exact low-14-bit flag set this hook's address must carry (AFTER_SWAP | AFTER_SWAP_RETURNS_DELTA).
    function hookFlags() external pure returns (uint160) {
        return BurrowHooks.AFTER_SWAP_FLAG | BurrowHooks.AFTER_SWAP_RETURNS_DELTA_FLAG;
    }

    /// @notice Set the hook fee, bounded by MAX_HOOK_FEE_BPS.
    function setHookFeeBps(uint16 newFeeBps) external onlyOwner {
        if (newFeeBps > MAX_HOOK_FEE_BPS) revert FeeTooHigh(newFeeBps, MAX_HOOK_FEE_BPS);
        emit HookFeeSet(hookFeeBps, newFeeBps);
        hookFeeBps = newFeeBps;
    }

    /// @notice Fee this hook would skim from an SQK output of `outputAmount`.
    function quoteFee(uint256 outputAmount) public view returns (uint256) {
        return outputAmount * hookFeeBps / BPS;
    }

    /// @notice Donate any SQK held here (fees the vault refused earlier) to the vault. Anyone may call.
    function flush() external nonReentrant {
        uint256 amount = sqk.balanceOf(address(this));
        if (amount == 0) revert NothingToFlush();
        _forceApprove(address(vault), amount);
        vault.donate(amount);
        emit Flushed(amount);
    }

    function _afterSwap(
        address,
        BurrowPoolKey calldata key,
        BurrowSwapParams calldata params,
        BurrowBalanceDelta delta,
        bytes calldata
    ) internal override nonReentrant returns (bytes4, int128) {
        // The returned delta applies to the unspecified currency, which is the output only on exact input.
        if (params.amountSpecified >= 0) return (BurrowBaseHook.afterSwap.selector, 0);

        BurrowCurrency output = params.zeroForOne ? key.currency1 : key.currency0;
        if (BurrowCurrency.unwrap(output) != address(sqk)) return (BurrowBaseHook.afterSwap.selector, 0);

        int128 outputAmount = params.zeroForOne ? delta.amount1() : delta.amount0();
        if (outputAmount <= 0) return (BurrowBaseHook.afterSwap.selector, 0);

        uint256 fee = quoteFee(uint256(uint128(outputAmount)));
        if (fee == 0) return (BurrowBaseHook.afterSwap.selector, 0);

        // Returning +fee credits this hook in SQK; take() settles that credit to this contract.
        poolManager.take(output, address(this), fee);

        bytes32 poolId = key.toId();
        _forceApprove(address(vault), fee);
        // A failing vault must not brick the pool: keep the fee for flush() instead.
        try vault.donate(fee) {
            emit FeeDonated(poolId, fee);
        } catch {
            _forceApprove(address(vault), 0);
            emit FeeHeld(poolId, fee);
        }

        // fee <= 1% of a positive int128, so the cast back is safe.
        return (BurrowBaseHook.afterSwap.selector, int128(int256(fee)));
    }

    /// @dev OpenZeppelin SafeERC20.forceApprove semantics: tolerate tokens returning nothing and
    /// tokens that require resetting the allowance to zero first.
    function _forceApprove(address spender, uint256 value) private {
        if (!_tryApprove(spender, value)) {
            if (!_tryApprove(spender, 0) || !_tryApprove(spender, value)) revert ApproveFailed();
        }
    }

    function _tryApprove(address spender, uint256 value) private returns (bool) {
        (bool ok, bytes memory ret) = address(sqk).call(abi.encodeCall(IBurrowHookERC20.approve, (spender, value)));
        return ok && (ret.length == 0 ? address(sqk).code.length > 0 : abi.decode(ret, (bool)));
    }
}
