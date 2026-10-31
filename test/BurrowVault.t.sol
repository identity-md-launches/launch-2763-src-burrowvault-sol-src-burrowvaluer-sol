// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {
    BurrowVault,
    ERC20,
    IERC20,
    IERC20Metadata,
    IERC721,
    IERC721Receiver,
    ERC721Holder,
    IBurrowPositionManager,
    Math,
    BurrowTickMath
} from "../src/BurrowVault.sol";
import {BurrowValuer} from "../src/BurrowValuer.sol";

// This repository has no forge-std dependency. The small test harness below uses
// Foundry's public cheatcode ABI and invariant discovery ABI directly, so all four
// test files compile offline without adding libraries or remappings.
interface BurrowVm {
    function prank(address) external;
    function startPrank(address) external;
    function stopPrank() external;
    function warp(uint256) external;
    function expectRevert() external;
    function expectRevert(bytes4) external;
    function expectRevert(bytes calldata) external;
    function expectEmit(bool, bool, bool, bool, address) external;
    function envOr(string calldata, string calldata) external returns (string memory);
    function createSelectFork(string calldata, uint256) external returns (uint256);
    function skip(bool) external;
    function record() external;
    function accesses(address) external returns (bytes32[] memory, bytes32[] memory);
    function load(address, bytes32) external view returns (bytes32);
    function store(address, bytes32, bytes32) external;
    function etch(address, bytes calldata) external;
    function mockCall(address, bytes calldata, bytes calldata) external;
    function mockCallRevert(address, bytes calldata, bytes calldata) external;
    function clearMockedCalls() external;
    function snapshotState() external returns (uint256);
    function revertToState(uint256) external returns (bool);
    function getCode(string calldata) external view returns (bytes memory);
}

abstract contract BurrowTestBase {
    BurrowVm internal constant vm = BurrowVm(address(uint160(uint256(keccak256("hevm cheat code")))));
    error AssertionFailed(string reason);

    function assertTrue(bool a, string memory why) internal pure {
        if (!a) revert AssertionFailed(why);
    }

    function assertEq(uint256 a, uint256 b, string memory why) internal pure {
        assertTrue(a == b, why);
    }

    function assertEq(address a, address b, string memory why) internal pure {
        assertTrue(a == b, why);
    }

    function assertEq(bytes32 a, bytes32 b, string memory why) internal pure {
        assertTrue(a == b, why);
    }

    function assertGe(uint256 a, uint256 b, string memory why) internal pure {
        assertTrue(a >= b, why);
    }

    function assertLe(uint256 a, uint256 b, string memory why) internal pure {
        assertTrue(a <= b, why);
    }

    function addr(string memory label) internal pure returns (address) {
        return address(uint160(uint256(keccak256(bytes(label)))));
    }

    function bound(uint256 x, uint256 lo, uint256 hi) internal pure returns (uint256) {
        if (x >= lo && x <= hi) return x;
        return lo + x % (hi - lo + 1);
    }

    function ids(uint256 id) internal pure returns (uint256[] memory a) {
        a = new uint256[](1);
        a[0] = id;
    }

    function powers() internal pure returns (uint256[] memory p) {
        p = new uint256[](16);
        uint256 n = 1000;
        for (uint256 i; i < p.length; i++) {
            p[i] = n;
            n = n * 2 + 1000;
        }
    }

    // Equivalent to forge-std's ERC20 deal: discover and update only balanceOf's
    // backing slot. No RPC endpoint, key, or chain balance is hardcoded.
    function deal(address token, address account, uint256 amount) internal {
        vm.record();
        IERC20(token).balanceOf(account);
        (bytes32[] memory reads,) = vm.accesses(token);
        bool found;
        for (uint256 i; i < reads.length; i++) {
            bytes32 old = vm.load(token, reads[i]);
            vm.store(token, reads[i], bytes32(amount));
            if (IERC20(token).balanceOf(account) == amount) {
                found = true;
                break;
            }
            vm.store(token, reads[i], old);
        }
        assertTrue(found, "ERC20 balance slot was not found");
    }
}

contract BurrowTestToken is ERC20 {
    uint8 private _decimals = 18;
    bool public tax;
    bool public rejectApproval;
    address public callbackTarget;
    bytes public callbackData;
    bytes public callbackResult;
    bool public callbackSucceeded;
    constructor() ERC20("Mock SQK", "SQK") {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    function burn(address from, uint256 amount) external {
        _burn(from, amount);
    }

    function setDecimals(uint8 d) external {
        _decimals = d;
    }

    function decimals() public view override returns (uint8) {
        return _decimals;
    }

    function setTax(bool b) external {
        tax = b;
    }

    function setRejectApproval(bool b) external {
        rejectApproval = b;
    }

    function setCallback(address target, bytes calldata data) external {
        callbackTarget = target;
        callbackData = data;
    }

    function approve(address spender, uint256 amount) public override returns (bool) {
        if (rejectApproval) return false;
        return super.approve(spender, amount);
    }

    function transferFrom(address from, address to, uint256 amount) public override returns (bool) {
        bool ok = super.transferFrom(from, to, amount);
        if (tax && amount != 0) _burn(to, 1);
        if (callbackTarget != address(0)) {
            (callbackSucceeded, callbackResult) = callbackTarget.call(callbackData);
        }
        return ok;
    }
}

contract BurrowTestNFT {
    mapping(uint256 => address) private owners;
    mapping(uint256 => uint8) public level;
    mapping(uint256 => address) public getApproved;
    mapping(address => mapping(address => bool)) public isApprovedForAll;
    error MissingToken();
    error Unauthorized();
    error UnsafeRecipient();

    function mint(address to, uint256 id, uint8 lev) external {
        if (owners[id] != address(0)) revert Unauthorized();
        owners[id] = to;
        level[id] = lev;
    }

    function setLevel(uint256 id, uint8 lev) external {
        level[id] = lev;
    }

    function ownerOf(uint256 id) public view returns (address) {
        if (owners[id] == address(0)) revert MissingToken();
        return owners[id];
    }

    function approve(address spender, uint256 id) external {
        address owner = ownerOf(id);
        if (msg.sender != owner && !isApprovedForAll[owner][msg.sender]) revert Unauthorized();
        getApproved[id] = spender;
    }

    function setApprovalForAll(address operator, bool approved) external {
        isApprovedForAll[msg.sender][operator] = approved;
    }

    function transferFrom(address from, address to, uint256 id) public {
        address owner = ownerOf(id);
        if (
            owner != from
                || (msg.sender != owner && msg.sender != getApproved[id] && !isApprovedForAll[owner][msg.sender])
        ) {
            revert Unauthorized();
        }
        owners[id] = to;
        delete getApproved[id];
    }

    function safeTransferFrom(address from, address to, uint256 id) public {
        safeTransferFrom(from, to, id, "");
    }

    function safeTransferFrom(address from, address to, uint256 id, bytes memory data) public {
        transferFrom(from, to, id);
        if (
            to.code.length != 0
                && IERC721Receiver(to).onERC721Received(msg.sender, from, id, data)
                    != IERC721Receiver.onERC721Received.selector
        ) revert UnsafeRecipient();
    }
}

// The mock exposes the real staking selectors used by the vault. Rewards are
// explicitly funded per account so unit tests control income independently of
// time; the pinned fork below separately verifies live reward accrual.
contract BurrowTestStaking is ERC721Holder {
    BurrowTestToken public immutable token;
    mapping(address => uint256) public nftPower;
    mapping(address => uint256) public claimable;
    mapping(address => address) public claimRecipient;
    mapping(address => mapping(uint256 => address)) public depositor;
    mapping(address => mapping(uint256 => uint256)) private depositedPower;
    bool public overridePower;
    uint256 public powerOverride;
    error NotDepositor();

    constructor(BurrowTestToken t) {
        token = t;
    }

    function setPowerOverride(uint256 p) external {
        overridePower = true;
        powerOverride = p;
    }

    function deposit(address collection, uint256[] calldata tokenIds) external {
        for (uint256 i; i < tokenIds.length; i++) {
            uint256 id = tokenIds[i];
            BurrowTestNFT(collection).safeTransferFrom(msg.sender, address(this), id);
            uint256 p =
                overridePower ? powerOverride : 1000 * ((uint256(1) << BurrowTestNFT(collection).level(id)) - 1) * 1e18;
            nftPower[msg.sender] += p;
            depositedPower[collection][id] = p;
            depositor[collection][id] = msg.sender;
        }
    }

    function withdraw(address collection, uint256[] calldata tokenIds) external {
        for (uint256 i; i < tokenIds.length; i++) {
            uint256 id = tokenIds[i];
            if (depositor[collection][id] != msg.sender) revert NotDepositor();
            nftPower[msg.sender] -= depositedPower[collection][id];
            delete depositor[collection][id];
            BurrowTestNFT(collection).safeTransferFrom(address(this), msg.sender, id);
        }
    }

    function fund(address account, uint256 reward) external {
        token.mint(address(this), reward);
        claimable[account] += reward;
    }

    function claim(address recipient) external {
        uint256 amount = claimable[msg.sender];
        claimable[msg.sender] = 0;
        if (amount != 0) token.transfer(recipient, amount);
    }

    function setClaimRecipient(address recipient) external {
        claimRecipient[msg.sender] = recipient;
    }

    function accountPower(address account) external view returns (uint256, uint256) {
        return (nftPower[account], 0);
    }
}

contract BurrowTestPoolManager {
    mapping(bytes32 => bytes32) public words;

    function setPrice(bytes32 poolId, uint160 sqrtPrice) external {
        words[keccak256(abi.encode(poolId, uint256(6)))] = bytes32(uint256(sqrtPrice));
    }

    function extsload(bytes32 slot) external view returns (bytes32) {
        return words[slot];
    }
}

contract BurrowTestPositionManager is BurrowTestNFT {
    address public immutable poolManager;
    IBurrowPositionManager.PoolKey private key;
    uint256 public info;
    uint128 public liquidity;

    constructor(address manager) {
        poolManager = manager;
    }

    function configure(IBurrowPositionManager.PoolKey memory k, int24 lower, int24 upper, uint128 liq) external {
        key = k;
        info = (uint256(uint24(lower)) << 8) | (uint256(uint24(upper)) << 32);
        liquidity = liq;
    }

    function getPoolAndPositionInfo(uint256) external view returns (IBurrowPositionManager.PoolKey memory, uint256) {
        return (key, info);
    }

    function getPositionLiquidity(uint256) external view returns (uint128) {
        return liquidity;
    }
}

abstract contract BurrowVaultFixture is BurrowTestBase {
    BurrowTestToken internal token;
    BurrowTestNFT internal nft;
    BurrowTestStaking internal staking;
    BurrowValuer internal valuer;
    BurrowVault internal vault;
    BurrowTestPoolManager internal manager;
    BurrowTestPositionManager internal positions;
    IBurrowPositionManager.PoolKey internal poolKey;
    address internal alice;
    address internal bob;
    address internal lender;
    address internal liquidator;
    uint256 internal constant RATE = 1e10;

    function _setup(uint256 rate) internal {
        vm.warp(10 days);
        alice = addr("borrower alice");
        bob = addr("borrower bob");
        lender = addr("lender");
        liquidator = addr("liquidator");
        token = new BurrowTestToken();
        nft = new BurrowTestNFT();
        staking = new BurrowTestStaking(token);
        valuer = new BurrowValuer(address(this), address(nft), powers(), 1e18, 1e15, 100e18, 6000);
        manager = new BurrowTestPoolManager();
        positions = new BurrowTestPositionManager(address(manager));
        poolKey = IBurrowPositionManager.PoolKey(address(token), address(nft), 3000, 60, address(0));
        positions.configure(poolKey, -600, 600, 1e24);
        manager.setPrice(keccak256(abi.encode(poolKey)), uint160(1 << 96));
        vault = new BurrowVault(_config(rate));
        _fund(lender, 1e30);
        _fund(alice, 1e30);
        _fund(bob, 1e30);
        _fund(liquidator, 1e30);
    }

    function _config(uint256 rate) internal view returns (BurrowVault.Config memory c) {
        c = BurrowVault.Config(
            address(this),
            address(token),
            address(nft),
            address(staking),
            address(valuer),
            address(positions),
            address(manager),
            keccak256(abi.encode(poolKey)),
            rate,
            1000,
            1000,
            10
        );
    }

    function _fund(address who, uint256 amount) internal {
        token.mint(who, amount);
        vm.prank(who);
        token.approve(address(vault), type(uint256).max);
    }

    function _seed(uint256 amount) internal {
        vm.prank(lender);
        vault.deposit(amount);
    }

    function _open(address who, uint256 id, uint8 lev) internal {
        nft.mint(who, id, lev);
        vm.startPrank(who);
        nft.setApprovalForAll(address(vault), true);
        vault.openPosition(ids(id));
        vm.stopPrank();
    }

    function _borrow(address who, uint256 amount) internal {
        vm.prank(who);
        vault.borrow(amount);
    }
}

contract BurrowVaultTest is BurrowVaultFixture {
    function setUp() public {
        _setup(RATE);
    }
    event Deposit(address indexed lender, uint256 assets, uint256 shares);
    event Donation(address indexed donor, uint256 amount);
    event RewardsSwept(uint256 received, uint256 debtRepaid, uint256 income);

    function test_DepositWithdrawAndMinimumLiquidity() public {
        vm.expectEmit(true, false, false, true, address(vault));
        emit Deposit(lender, 100e18, 100e18 - 1000);
        _seed(100e18);
        assertEq(vault.lockedShares(), 1000, "initial dust must remain locked");
        assertEq(vault.totalAssets(), 100e18, "backing");
        uint256 held = vault.balanceOf(lender);
        vm.prank(lender);
        uint256 paid = vault.withdraw(held);
        assertEq(paid, 100e18 - 1000, "full lender redemption");
        assertEq(vault.totalAssets(), 1000, "locked shares retain backing");
        assertEq(vault.totalSupply(), 1000, "locked supply");
    }

    /// forge-config: default.fuzz.runs = 1000
    function testFuzz_DepositAndWithdrawalNeverLowerSharePrice(uint128 a, uint128 gift, uint128 b, uint128 burn)
        public
    {
        uint256 first = bound(a, 1001, 1e27);
        uint256 donation = bound(gift, 1, 1e27);
        uint256 second = bound(b, 1e18, 1e27);
        _seed(first);
        vm.prank(alice);
        vault.donate(donation);
        uint256 oldAssets = vault.totalAssets();
        uint256 oldSupply = vault.totalSupply();
        uint256 expected = second * oldSupply / oldAssets;
        if (expected == 0) {
            vm.expectRevert(BurrowVault.ZeroShares.selector);
            vm.prank(bob);
            vault.deposit(second);
            return;
        }
        vm.prank(bob);
        uint256 minted = vault.deposit(second);
        assertEq(minted, expected, "floor shares");
        assertGe(vault.totalAssets() * oldSupply, oldAssets * vault.totalSupply(), "deposit lowered price");
        oldAssets = vault.totalAssets();
        oldSupply = vault.totalSupply();
        uint256 shares = bound(burn, 1, minted);
        uint256 assets = shares * oldAssets / oldSupply;
        vm.prank(bob);
        assertEq(vault.withdraw(shares), assets, "redemption rounding");
        assertGe(vault.totalAssets() * oldSupply, oldAssets * vault.totalSupply(), "withdraw lowered price");
    }

    function test_DonationRaisesSharePriceAndMintsNothing() public {
        _seed(100e18);
        uint256 supply = vault.totalSupply();
        vm.expectEmit(true, false, false, true, address(vault));
        emit Donation(alice, 10e18);
        vm.prank(alice);
        vault.donate(10e18);
        assertEq(vault.totalSupply(), supply, "donation must not mint");
        assertEq(vault.convertToAssets(1e18), 1.1e18, "income to all shares");
    }

    function test_PreSeedDonationCannotBeCapturedByFirstDepositor() public {
        vm.prank(alice);
        vault.donate(100e18);
        _seed(10e18);
        assertEq(vault.lockedShares(), 100e18 + 1000, "donation locked");
        uint256 held = vault.balanceOf(lender);
        vm.prank(lender);
        assertEq(vault.withdraw(held), 10e18 - 1000, "no donation capture");
    }

    function test_DepositErrorsAndSlippageAreAtomic() public {
        vm.expectRevert(BurrowVault.ZeroAmount.selector);
        vault.deposit(0);
        vm.expectRevert(abi.encodeWithSelector(BurrowVault.MinimumInitialDeposit.selector, 1001));
        vm.prank(lender);
        vault.deposit(1000);
        vm.expectRevert(abi.encodeWithSelector(BurrowVault.Slippage.selector, 100e18 - 1000, 100e18));
        vm.prank(lender);
        vault.deposit(100e18, 100e18);
        assertEq(vault.totalSupply(), 0, "failed seed minted");
        _seed(1001);
        vm.prank(alice);
        vault.donate(1e18);
        vm.expectRevert(BurrowVault.ZeroShares.selector);
        vm.prank(bob);
        vault.deposit(1);
    }

    function test_WithdrawErrorsAndSlippageAreAtomic() public {
        _seed(100e18);
        vm.expectRevert(BurrowVault.ZeroShares.selector);
        vault.withdraw(0);
        vm.expectRevert(abi.encodeWithSelector(BurrowVault.Slippage.selector, 1e18, 1e18 + 1));
        vm.prank(lender);
        vault.withdraw(1e18, 1e18 + 1);
        assertEq(vault.balanceOf(lender), 100e18 - 1000, "slippage burned shares");
        vm.expectRevert(abi.encodeWithSignature("ERC20InsufficientBalance(address,uint256,uint256)", bob, 0, 1));
        vm.prank(bob);
        vault.withdraw(1);
    }

    function test_BorrowBoundaryOneWeiAndFullRoundTrip() public {
        _seed(10000e18);
        _open(alice, 1, 1);
        uint256 line = vault.creditLine(alice);
        assertEq(line, 600e18, "real valuer integration");
        assertEq(nft.ownerOf(1), address(staking), "collateral not staked");
        assertEq(staking.claimRecipient(address(vault)), address(vault), "reward recipient");
        BurrowVault.Position memory p = vault.positionOf(alice);
        assertEq(p.levels[0], 1, "recorded level");
        assertEq(p.power, 1000, "recorded power");
        _borrow(alice, line - 1);
        vm.expectRevert(abi.encodeWithSelector(BurrowVault.CreditLimitExceeded.selector, line + 1, line));
        vm.prank(alice);
        vault.borrow(2);
        _borrow(alice, 1);
        vm.expectRevert(abi.encodeWithSelector(BurrowVault.DebtRemaining.selector, line));
        vm.prank(alice);
        vault.closePosition();
        vm.prank(alice);
        assertEq(vault.repayAll(), line, "repay principal");
        vm.prank(alice);
        vault.closePosition();
        assertEq(nft.ownerOf(1), alice, "collateral returned");
        assertEq(vault.positionCount(), 0, "position removed");
        assertEq(vault.totalPrincipal(), 0, "principal cleared");
        assertEq(vault.totalEscrowedPower(), 0, "power cleared");
        assertEq(vault.totalAssets(), 10000e18, "round trip preserves assets");
    }

    function test_InterestAccruesInViewsAndOnTouchWithoutCompounding() public {
        _seed(10000e18);
        _open(alice, 1, 1);
        _borrow(alice, 100e18);
        vm.warp(block.timestamp + 1000);
        assertEq(vault.debtOf(alice), 100e18 + 1e15, "pending interest");
        assertEq(vault.totalAssets(), 10000e18 + 1e15, "interest backs shares before touch");
        vault.sweepRewards();
        assertEq(vault.totalAccruedInterest(), 1e15, "booked interest");
        vm.warp(block.timestamp + 1000);
        vault.sweepRewards();
        assertEq(vault.totalAccruedInterest(), 2e15, "interest must not compound");
        vm.prank(alice);
        vault.repay(1e15);
        BurrowVault.Position memory p = vault.positionOf(alice);
        assertEq(p.principal, 100e18, "repay interest before principal");
        assertEq(p.interest, 1e15, "remaining interest");
    }

    function test_FractionalInterestSurvivesRepeatedTouches() public {
        _seed(1e18);
        _open(alice, 1, 1);
        _borrow(alice, 1e7);
        for (uint256 i; i < 10; i++) {
            vm.warp(block.timestamp + 1);
            vault.sweepRewards();
        }
        assertEq(vault.debtOf(alice), 1e7 + 1, "touching must not erase fractional interest");
    }

    function test_RewardsRepayProRataInterestFirstAndLeaveExcessAsIncome() public {
        _seed(10000e18);
        _open(alice, 1, 1);
        _open(bob, 2, 2);
        _borrow(alice, 100e18);
        _borrow(bob, 200e18);
        vm.warp(block.timestamp + 1000);
        uint256 assets = vault.totalAssets();
        staking.fund(address(vault), 40e18);
        (uint256 received, uint256 repaid) = vault.sweepRewards();
        assertEq(received, 40e18, "actual rewards");
        assertEq(repaid, 40e18, "repayment");
        assertEq(vault.debtOf(alice), 90e18 + 1e15, "one quarter allocation");
        assertEq(vault.debtOf(bob), 170e18 + 2e15, "three quarter allocation");
        assertEq(vault.positionOf(alice).interest, 0, "interest paid first");
        assertEq(vault.totalAssets(), assets, "repayment does not double count rewards");
        staking.fund(address(vault), 1000e18);
        (received, repaid) = vault.sweepRewards();
        assertEq(vault.debtOf(alice) + vault.debtOf(bob), 0, "overpayment clears debt");
        assertEq(vault.totalAssets(), assets + received - repaid, "excess income");
        assertEq(token.balanceOf(address(staking)), 0, "claimed rewards");
    }

    function test_RewardsBelongToOldPowerBeforeNewPositionEnters() public {
        _seed(10000e18);
        _open(alice, 1, 1);
        _borrow(alice, 100e18);
        staking.fund(address(vault), 10e18);
        _open(bob, 2, 2);
        assertEq(vault.debtOf(alice), 90e18, "old collateral earns its pending rewards");
        assertEq(vault.debtOf(bob), 0, "entrant cannot steal rewards");
    }

    function test_RepayIsClampedAndCanBeClearedByItsAutomaticSweep() public {
        _seed(10000e18);
        _open(alice, 1, 1);
        _borrow(alice, 100e18);
        uint256 before = token.balanceOf(alice);
        vm.prank(alice);
        assertEq(vault.repay(type(uint256).max), 100e18, "clamp to debt");
        assertEq(token.balanceOf(alice), before - 100e18, "no excess pulled");
        _borrow(alice, 50e18);
        staking.fund(address(vault), 50e18);
        vm.prank(alice);
        assertEq(vault.repay(1), 0, "automatic sweep cleared debt");
        vm.prank(alice);
        assertEq(vault.repayAll(), 0, "repayAll after sweep is a no-op");
    }

    function test_InsufficientIdleLiquidityDoesNotBurnSharesOrIncreaseDebt() public {
        _seed(100e18);
        _open(alice, 1, 1);
        _borrow(alice, 100e18);
        vm.expectRevert(abi.encodeWithSelector(BurrowVault.InsufficientLiquidity.selector, 0, 1));
        vm.prank(lender);
        vault.withdraw(1);
        vm.expectRevert(abi.encodeWithSelector(BurrowVault.InsufficientLiquidity.selector, 0, 1));
        vm.prank(alice);
        vault.borrow(1);
        assertEq(vault.totalPrincipal(), 100e18, "failed borrow changed debt");
        assertEq(vault.balanceOf(lender), 100e18 - 1000, "failed withdrawal burned shares");
    }

    function test_PositionAndAmountFailurePaths() public {
        vm.expectRevert(BurrowVault.PositionNotFound.selector);
        vault.borrow(1);
        vm.expectRevert(BurrowVault.PositionNotFound.selector);
        vault.repay(1);
        vm.expectRevert(BurrowVault.PositionNotFound.selector);
        vault.repayAll();
        vm.expectRevert(BurrowVault.PositionNotFound.selector);
        vault.closePosition();
        vm.expectRevert(BurrowVault.PositionNotFound.selector);
        vault.liquidate(alice);
        vm.expectRevert(BurrowVault.ZeroAmount.selector);
        vault.borrow(0);
        vm.expectRevert(BurrowVault.ZeroAmount.selector);
        vault.repay(0);
        vm.expectRevert(BurrowVault.ZeroAmount.selector);
        vault.donate(0);
        _open(alice, 1, 1);
        vm.expectRevert(BurrowVault.PositionExists.selector);
        vm.prank(alice);
        vault.openPosition(ids(1));
        vm.expectRevert(BurrowVault.NoDebt.selector);
        vm.prank(alice);
        vault.repay(1);
        vm.expectRevert(BurrowVault.NothingToClaim.selector);
        vault.claimSurplus();
        vm.expectRevert(BurrowVault.NothingToClaim.selector);
        vault.claimBond();
    }

    function test_ArrayValidationAndMaximumBatch() public {
        vm.expectRevert(BurrowVault.InvalidTokenIds.selector);
        vault.openPosition(new uint256[](0));
        vm.expectRevert(BurrowVault.InvalidTokenIds.selector);
        vault.openPosition(new uint256[](33));
        uint256[] memory a = new uint256[](2);
        a[0] = 2;
        a[1] = 2;
        vm.expectRevert(BurrowVault.InvalidTokenIds.selector);
        vault.openPosition(a);
        a[1] = 1;
        vm.expectRevert(BurrowVault.InvalidTokenIds.selector);
        vault.openPosition(a);
        a = new uint256[](32);
        for (uint256 i; i < 32; i++) {
            a[i] = i + 1;
            nft.mint(alice, i + 1, 1);
        }
        vm.startPrank(alice);
        nft.setApprovalForAll(address(vault), true);
        vault.openPosition(a);
        vm.stopPrank();
        assertEq(vault.positionOf(alice).tokenIds.length, 32, "maximum collateral batch");
        assertEq(vault.totalEscrowedPower(), 32000, "batch power");
    }

    function test_NFTMustBeOwnedAndApprovedAndUnsolicitedReceiptsRevert() public {
        nft.mint(alice, 1, 1);
        vm.expectRevert(BurrowTestNFT.Unauthorized.selector);
        vm.prank(alice);
        vault.openPosition(ids(1));
        assertEq(vault.positionCount(), 0, "failed escrow left a position");
        vm.prank(alice);
        nft.setApprovalForAll(address(vault), true);
        vm.expectRevert(BurrowTestNFT.Unauthorized.selector);
        vm.prank(bob);
        vault.openPosition(ids(1));
        vm.expectRevert(BurrowVault.UnexpectedNFT.selector);
        vm.prank(alice);
        nft.safeTransferFrom(alice, address(vault), 1);
        vm.expectRevert(BurrowVault.UnexpectedNFT.selector);
        vault.onERC721Received(alice, alice, 1, "");
    }

    function test_InvalidStakingPowerRevertsAtomically() public {
        nft.mint(alice, 1, 1);
        vm.prank(alice);
        nft.setApprovalForAll(address(vault), true);
        uint256[4] memory bad = [uint256(0), uint256(1000e18 + 1), uint256(999e18), uint256(2000e18)];
        uint256[4] memory reason = [uint256(0), uint256(1000e18 + 1), uint256(999), uint256(2000)];
        for (uint256 i; i < 4; i++) {
            staking.setPowerOverride(bad[i]);
            vm.expectRevert(abi.encodeWithSelector(BurrowVault.InvalidPower.selector, reason[i]));
            vm.prank(alice);
            vault.openPosition(ids(1));
            assertEq(nft.ownerOf(1), alice, "invalid power trapped NFT");
            assertEq(vault.positionCount(), 0, "invalid power left position");
        }
    }

    function test_FeeOnTransferSQKIsRejectedAndReentrancyIsBlocked() public {
        token.setTax(true);
        vm.expectRevert(abi.encodeWithSelector(BurrowVault.UnexpectedTokenAmount.selector, 1e18, 1e18 - 1));
        vm.prank(lender);
        vault.deposit(1e18);
        assertEq(vault.totalSupply(), 0, "taxed seed minted");
        token.setTax(false);
        token.setCallback(address(vault), abi.encodeWithSignature("deposit(uint256)", 1));
        _seed(1e18);
        assertTrue(!token.callbackSucceeded(), "reentered deposit");
        assertEq(
            keccak256(token.callbackResult()),
            keccak256(abi.encodeWithSignature("ReentrancyGuardReentrantCall()")),
            "wrong reentrancy failure"
        );
    }

    function test_PauseOnlyStopsBorrowAndAdminCaps() public {
        _seed(10000e18);
        _open(alice, 1, 1);
        _borrow(alice, 100e18);
        vault.setBorrowsPaused(true);
        vm.expectRevert(BurrowVault.BorrowingPaused.selector);
        vm.prank(alice);
        vault.borrow(1);
        vm.prank(alice);
        vault.repayAll();
        vm.prank(alice);
        vault.closePosition();
        vm.prank(lender);
        vault.withdraw(1e18);
        vault.setBorrowsPaused(false);
        vault.setBondDiscountBps(2000);
        vault.setLiquidationBonusBps(1500);
        vm.expectRevert(BurrowVault.DiscountTooHigh.selector);
        vault.setBondDiscountBps(2001);
        vm.expectRevert(BurrowVault.BonusTooHigh.selector);
        vault.setLiquidationBonusBps(1501);
        vm.expectRevert(abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", alice));
        vm.prank(alice);
        vault.setBorrowsPaused(true);
        vm.expectRevert(abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", alice));
        vm.prank(alice);
        vault.setBondDiscountBps(0);
        vm.expectRevert(abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", alice));
        vm.prank(alice);
        vault.setLiquidationBonusBps(0);
    }

    function test_ConstructorChecksEveryDependencyAndEconomicCap() public {
        BurrowVault.Config memory c = _config(RATE);
        address missing = addr("no code");
        for (uint256 i; i < 6; i++) {
            c = _config(RATE);
            if (i == 0) c.sqk = missing;
            else if (i == 1) c.squeek = missing;
            else if (i == 2) c.staking = missing;
            else if (i == 3) c.valuer = missing;
            else if (i == 4) c.positionManager = missing;
            else c.poolManager = missing;
            vm.expectRevert(abi.encodeWithSelector(BurrowVault.InvalidContract.selector, missing));
            new BurrowVault(c);
        }
        c = _config(RATE);
        c.bondPoolId = 0;
        vm.expectRevert(BurrowVault.InvalidParameter.selector);
        new BurrowVault(c);
        c = _config(RATE);
        c.bondVestingDays = 0;
        vm.expectRevert(BurrowVault.InvalidParameter.selector);
        new BurrowVault(c);
        c = _config(RATE);
        c.squeek = c.sqk;
        vm.expectRevert(BurrowVault.InvalidParameter.selector);
        new BurrowVault(c);
        c = _config(RATE);
        c.squeek = c.positionManager;
        vm.expectRevert(BurrowVault.InvalidParameter.selector);
        new BurrowVault(c);
        c = _config(RATE);
        c.interestRatePerSecond = vault.MAX_RATE_PER_SECOND() + 1;
        vm.expectRevert(BurrowVault.RateTooHigh.selector);
        new BurrowVault(c);
        c = _config(RATE);
        c.liquidationBonusBps = 1501;
        vm.expectRevert(BurrowVault.BonusTooHigh.selector);
        new BurrowVault(c);
        c = _config(RATE);
        c.bondDiscountBps = 2001;
        vm.expectRevert(BurrowVault.DiscountTooHigh.selector);
        new BurrowVault(c);
        c = _config(RATE);
        token.setDecimals(6);
        vm.expectRevert(abi.encodeWithSelector(BurrowVault.InvalidDecimals.selector, 6));
        new BurrowVault(c);
        token.setDecimals(18);
        c.poolManager = address(token);
        vm.expectRevert(BurrowVault.WrongPool.selector);
        new BurrowVault(c);
        c = _config(RATE);
        c.owner = address(0);
        vm.expectRevert(abi.encodeWithSignature("OwnableInvalidOwner(address)", address(0)));
        new BurrowVault(c);
        c = _config(vault.MAX_RATE_PER_SECOND());
        c.liquidationBonusBps = 1500;
        c.bondDiscountBps = 2000;
        BurrowVault maxed = new BurrowVault(c);
        assertEq(maxed.interestRatePerSecond(), vault.MAX_RATE_PER_SECOND(), "inclusive rate cap");
    }

    function test_LiquidationOneWeiBelowAtAndAboveLine() public {
        // Use a 1-wei/second debt increment to distinguish all three boundaries.
        BurrowVault.Config memory c = _config(1);
        vault = new BurrowVault(c);
        _fund(lender, 10000e18);
        _fund(alice, 10000e18);
        _fund(liquidator, 10000e18);
        _seed(10000e18);
        // Mock only the valuer's line, not debt or liquidation behavior, to set a
        // precise 1e18 boundary independently of the production valuation tests.
        vm.mockCall(address(valuer), abi.encodeWithSelector(BurrowValuer.creditLine.selector), abi.encode(1e18));
        _open(alice, 1, 1);
        _borrow(alice, 1e18 - 1);
        vm.expectRevert(abi.encodeWithSelector(BurrowVault.HealthyPosition.selector, 1e18 - 1, 1e18));
        vm.prank(liquidator);
        vault.liquidate(alice);
        _borrow(alice, 1);
        vm.expectRevert(abi.encodeWithSelector(BurrowVault.HealthyPosition.selector, 1e18, 1e18));
        vm.prank(liquidator);
        vault.liquidate(alice);
        vm.warp(block.timestamp + 1);
        assertEq(vault.debtOf(alice), 1e18 + 1, "one wei unhealthy");
        uint256 backing = vault.totalAssets();
        vm.prank(liquidator);
        uint256 payment = vault.liquidate(alice);
        assertEq(payment, 1566666666666666666, "debt plus borrower equity after ten percent bonus");
        uint256 equity = payment - (1e18 + 1);
        assertEq(nft.ownerOf(1), liquidator, "liquidator receives collateral");
        assertEq(vault.totalAssets(), backing, "surplus excluded from backing");
        assertEq(vault.surplus(alice), equity, "borrower equity");
        assertEq(vault.idleAssets() + equity, token.balanceOf(address(vault)), "reserved equity");
        uint256 before = token.balanceOf(alice);
        vm.prank(alice);
        assertEq(vault.claimSurplus(), equity, "surplus claim");
        assertEq(token.balanceOf(alice), before + equity, "equity paid to borrower");
        assertEq(vault.totalSurplus(), 0, "reserve cleared");
        vm.expectRevert(BurrowVault.NothingToClaim.selector);
        vm.prank(alice);
        vault.claimSurplus();
    }

    function test_ExecutedPriceMoveFreezesLiquidationForExactlyOneHour() public {
        _seed(10000e18);
        _open(alice, 1, 1);
        _borrow(alice, 590e18);
        valuer.proposePricePerPower(0.8e18);
        vm.warp(block.timestamp + 2 days);
        valuer.executePricePerPower();
        uint256 thaw = block.timestamp + 1 hours;
        vm.expectRevert(abi.encodeWithSelector(BurrowVault.LiquidationFrozen.selector, thaw));
        vm.prank(liquidator);
        vault.liquidate(alice);
        vm.warp(thaw - 1);
        vm.expectRevert(abi.encodeWithSelector(BurrowVault.LiquidationFrozen.selector, thaw));
        vm.prank(liquidator);
        vault.liquidate(alice);
        vm.warp(thaw);
        vm.prank(liquidator);
        vault.liquidate(alice);
        assertEq(nft.ownerOf(1), liquidator, "liquidation at exact thaw");
    }

    function test_SweepCanRescuePositionBeforeLiquidation() public {
        _seed(10000e18);
        _open(alice, 1, 1);
        _borrow(alice, 600e18);
        vm.warp(block.timestamp + 1 days);
        uint256 due = vault.debtOf(alice) - 600e18;
        staking.fund(address(vault), due);
        vm.expectRevert(abi.encodeWithSelector(BurrowVault.HealthyPosition.selector, 600e18, 600e18));
        vm.prank(liquidator);
        vault.liquidate(alice);
        vault.sweepRewards();
        assertEq(vault.debtOf(alice), 600e18, "rewards restored solvency");
    }

    function test_ReserveDeficitIsExplicit() public {
        _seed(10000e18);
        _open(alice, 1, 1);
        _borrow(alice, 600e18);
        vm.warp(block.timestamp + 1);
        vm.prank(liquidator);
        vault.liquidate(alice);
        uint256 reserve = vault.totalSurplus();
        assertTrue(reserve > 0, "expected equity");
        token.burn(address(vault), token.balanceOf(address(vault)) - reserve + 1);
        vm.expectRevert(BurrowVault.ReserveDeficit.selector);
        vault.idleAssets();
    }

    function test_RemovingMiddleBorrowerPreservesOtherPositions() public {
        _open(alice, 1, 1);
        _open(bob, 2, 2);
        _open(liquidator, 3, 3);
        vm.prank(bob);
        vault.closePosition();
        assertEq(vault.positionCount(), 2, "count");
        assertEq(vault.borrowerAt(1), liquidator, "swapped index");
        vm.prank(liquidator);
        vault.closePosition();
        vm.prank(alice);
        vault.closePosition();
        assertEq(vault.totalEscrowedPower(), 0, "all power removed");
    }

    function test_BondDiscountVestsLinearlyAndRetainsEarningNFT() public {
        _seed(10000e18);
        nft.mint(alice, 1, 2);
        vm.prank(alice);
        nft.setApprovalForAll(address(vault), true);
        uint256 beforeSupply = vault.totalSupply();
        vm.prank(alice);
        uint256 shares = vault.bond(address(nft), 1, 3300e18);
        assertEq(shares, 3300e18, "3000 value plus 10 percent discount");
        assertEq(vault.totalSupply(), beforeSupply + shares, "minted into vesting escrow");
        assertEq(vault.balanceOf(alice), 0, "no shares before vesting");
        assertEq(vault.claimableBond(alice), 0, "zero immediate vesting");
        assertEq(nft.ownerOf(1), address(staking), "treasury NFT staked");
        assertEq(vault.treasuryPower(), 3000, "treasury power separate");
        vm.expectRevert(BurrowVault.NothingToClaim.selector);
        vm.prank(alice);
        vault.claimBond();
        vm.warp(block.timestamp + 5 days);
        assertEq(vault.claimableBond(alice), shares / 2, "half vested");
        vm.prank(alice);
        assertEq(vault.claimBond(), shares / 2, "half claimed");
        vm.expectRevert(BurrowVault.NothingToClaim.selector);
        vm.prank(alice);
        vault.claimBond();
        uint256 backing = vault.totalAssets();
        staking.fund(address(vault), 100e18);
        vault.sweepRewards();
        assertEq(vault.totalAssets(), backing + 100e18, "treasury rewards are income");
        vm.warp(block.timestamp + 5 days);
        vm.prank(alice);
        assertEq(vault.claimBond(), shares / 2, "fully vested");
        assertEq(vault.unclaimedBondShares(), 0, "escrow released");
        assertEq(vault.bondCount(alice), 0, "mature schedule removed");
        assertEq(vault.balanceOf(alice), shares, "all vested shares received");
        assertTrue(vault.treasuryNFT(1), "retained treasury ownership");
    }

    function test_BondFailurePathsAndSlippageReturnCollateral() public {
        vm.expectRevert(abi.encodeWithSelector(BurrowVault.UnsupportedAsset.selector, address(token)));
        vault.bond(address(token), 1, 0);
        vm.expectRevert(BurrowVault.VaultUnseeded.selector);
        vault.bond(address(nft), 1, 0);
        _seed(10000e18);
        nft.mint(alice, 1, 1);
        vm.prank(alice);
        nft.setApprovalForAll(address(vault), true);
        vm.expectRevert(abi.encodeWithSelector(BurrowVault.Slippage.selector, 1100e18, 1100e18 + 1));
        vm.prank(alice);
        vault.bond(address(nft), 1, 1100e18 + 1);
        assertEq(nft.ownerOf(1), alice, "failed bond returns NFT");
        assertEq(vault.treasuryPower(), 0, "failed bond removes power");
        assertTrue(!vault.treasuryNFT(1), "failed bond flag");
        positions.mint(alice, 1, 1);
        vm.prank(alice);
        positions.setApprovalForAll(address(vault), true);
        positions.configure(poolKey, -600, 600, 0);
        vm.expectRevert(BurrowVault.EmptyPosition.selector);
        vm.prank(alice);
        vault.bond(address(positions), 1, 0);
        assertEq(positions.ownerOf(1), alice, "empty LP returned");
        positions.configure(poolKey, 600, -600, 100);
        vm.expectRevert(BurrowVault.WrongPool.selector);
        vault.positionSQKPrincipal(1);
        positions.configure(poolKey, -600, 600, 100);
        manager.setPrice(keccak256(abi.encode(poolKey)), 0);
        vm.expectRevert(BurrowVault.WrongPool.selector);
        vault.positionSQKPrincipal(1);
        IBurrowPositionManager.PoolKey memory other = poolKey;
        other.fee = 500;
        positions.configure(other, -600, 600, 100);
        vm.expectRevert(BurrowVault.WrongPool.selector);
        vault.positionSQKPrincipal(1);
    }

    function test_LPPrincipalBoundaryAndBondCustody() public {
        _seed(10000e18);
        uint256 value = vault.positionSQKPrincipal(7);
        assertTrue(value > 0, "in-range SQK principal");
        uint160 hi = BurrowTickMath.sqrtPriceAtTick(600);
        manager.setPrice(keccak256(abi.encode(poolKey)), hi);
        assertEq(vault.positionSQKPrincipal(7), 0, "SQK currency0 absent above range");
        manager.setPrice(keccak256(abi.encode(poolKey)), BurrowTickMath.sqrtPriceAtTick(-600));
        assertTrue(vault.positionSQKPrincipal(7) > value, "all SQK below range");
        manager.setPrice(keccak256(abi.encode(poolKey)), uint160(1 << 96));
        positions.mint(alice, 7, 1);
        vm.prank(alice);
        positions.setApprovalForAll(address(vault), true);
        vm.prank(alice);
        uint256 shares = vault.bond(address(positions), 7, 1);
        assertEq(shares, value + value / 10, "principal plus discount");
        assertEq(positions.ownerOf(7), address(vault), "LP retained");
        assertTrue(vault.treasuryLP(7), "treasury LP flag");
    }

    function test_BondLimitAndMatureScheduleRemoval() public {
        _seed(10000e18);
        vm.prank(alice);
        nft.setApprovalForAll(address(vault), true);
        for (uint256 i = 1; i <= 33; i++) {
            nft.mint(alice, i, 1);
        }
        for (uint256 i = 1; i <= 32; i++) {
            vm.prank(alice);
            vault.bond(address(nft), i, 1);
        }
        vm.expectRevert(BurrowVault.TooManyBonds.selector);
        vm.prank(alice);
        vault.bond(address(nft), 33, 1);
        vm.warp(block.timestamp + 10 days);
        vm.prank(alice);
        vault.claimBond();
        assertEq(vault.bondCount(alice), 0, "all swapped schedules processed");
        vm.prank(alice);
        vault.bond(address(nft), 33, 1);
        assertEq(vault.bondCount(alice), 1, "limit frees on claim");
    }
}

// Random sequences use a fixed price and zero interest for the strict debt <=
// credit-line invariant. Positive interest and timelocked price declines are
// exercised above, where exceeding the line is what enables liquidation.
contract BurrowVaultHandler is BurrowTestBase {
    BurrowVault public immutable vault;
    BurrowTestToken public immutable token;
    BurrowTestNFT public immutable nft;
    BurrowTestStaking public immutable staking;
    address[4] public actors;
    uint256 public assetsWithdrawn;
    uint256 public assetFloor;
    uint256 public nextBondId = 100;
    uint256 public actions;
    bool public assetsDecreased;
    bool public sharePriceDecreased;

    constructor(BurrowVault v, BurrowTestToken t, BurrowTestNFT n, BurrowTestStaking s) {
        vault = v;
        token = t;
        nft = n;
        staking = s;
        for (uint256 i; i < 4; i++) {
            address who = address(uint160(uint256(keccak256(abi.encode("vault actor", i)))));
            actors[i] = who;
            t.mint(who, 1e30);
            n.mint(who, i + 1, uint8(i + 1));
            vm.startPrank(who);
            t.approve(address(v), type(uint256).max);
            n.setApprovalForAll(address(v), true);
            vm.stopPrank();
        }
        assetFloor = v.totalAssets();
    }

    function _finish(uint256 beforeAssets, uint256 paid) internal {
        actions++;
        if (vault.totalAssets() + paid < beforeAssets) assetsDecreased = true;
        assetsWithdrawn += paid;
        if (vault.totalAssets() + assetsWithdrawn < assetFloor) assetsDecreased = true;
        assetFloor = vault.totalAssets() + assetsWithdrawn;
    }

    function deposit(uint256 who, uint256 raw) external {
        uint256 amount = bound(raw, 1e12, 1e21);
        uint256 a = vault.totalAssets();
        uint256 s = vault.totalSupply();
        vm.prank(actors[who % 4]);
        vault.deposit(amount);
        if (vault.totalAssets() * s < a * vault.totalSupply()) sharePriceDecreased = true;
        _finish(a, 0);
    }

    function withdraw(uint256 who, uint256 raw) external {
        address actor = actors[who % 4];
        uint256 a = vault.totalAssets();
        uint256 s = vault.totalSupply();
        uint256 cap = Math.min(vault.balanceOf(actor), vault.idleAssets() * s / a);
        if (cap == 0) return;
        uint256 shares = bound(raw, 1, cap);
        if (vault.convertToAssets(shares) == 0) return;
        vm.prank(actor);
        uint256 paid = vault.withdraw(shares);
        if (vault.totalAssets() * s < a * vault.totalSupply()) sharePriceDecreased = true;
        _finish(a, paid);
    }

    function donate(uint256 who, uint256 raw) external {
        uint256 a = vault.totalAssets();
        vm.prank(actors[who % 4]);
        vault.donate(bound(raw, 1, 1e20));
        _finish(a, 0);
    }

    function open(uint256 who) external {
        uint256 i = who % 4;
        address actor = actors[i];
        if (vault.positionOf(actor).tokenIds.length != 0 || nft.ownerOf(i + 1) != actor) return;
        uint256 a = vault.totalAssets();
        vm.prank(actor);
        vault.openPosition(ids(i + 1));
        _finish(a, 0);
    }

    function borrow(uint256 who, uint256 raw) external {
        address actor = actors[who % 4];
        uint256 line = vault.creditLine(actor);
        uint256 debt = vault.debtOf(actor);
        if (line <= debt) return;
        uint256 cap = Math.min(line - debt, vault.idleAssets());
        if (cap == 0) return;
        uint256 a = vault.totalAssets();
        vm.prank(actor);
        vault.borrow(bound(raw, 1, cap));
        _finish(a, 0);
    }

    function repay(uint256 who, uint256 raw) external {
        address actor = actors[who % 4];
        uint256 debt = vault.debtOf(actor);
        if (debt == 0) return;
        uint256 a = vault.totalAssets();
        vm.prank(actor);
        vault.repay(bound(raw, 1, debt));
        _finish(a, 0);
    }

    function close(uint256 who) external {
        address actor = actors[who % 4];
        if (vault.positionOf(actor).tokenIds.length == 0) return;
        uint256 a = vault.totalAssets();
        vm.startPrank(actor);
        vault.repayAll();
        vault.closePosition();
        vm.stopPrank();
        _finish(a, 0);
    }

    function reward(uint256 raw) external {
        if (vault.totalEscrowedPower() + vault.treasuryPower() == 0) return;
        uint256 a = vault.totalAssets();
        staking.fund(address(vault), bound(raw, 1, 1e21));
        vault.sweepRewards();
        _finish(a, 0);
    }

    function bond(uint256 who) external {
        address actor = actors[who % 4];
        if (vault.bondCount(actor) == 32) return;
        uint256 a = vault.totalAssets();
        uint256 id = nextBondId++;
        nft.mint(actor, id, 1);
        vm.prank(actor);
        vault.bond(address(nft), id, 1);
        _finish(a, 0);
    }

    function advanceAndClaim(uint256 who, uint256 raw) external {
        uint256 a = vault.totalAssets();
        vm.warp(block.timestamp + bound(raw, 1, 2 days));
        address actor = actors[who % 4];
        if (vault.claimableBond(actor) != 0) {
            vm.prank(actor);
            vault.claimBond();
        }
        _finish(a, 0);
    }

    function liquidate(uint256 who, uint256 taker) external {
        address actor = actors[who % 4];
        if (vault.debtOf(actor) <= vault.creditLine(actor)) return;
        uint256 a = vault.totalAssets();
        vm.prank(actors[taker % 4]);
        vault.liquidate(actor);
        _finish(a, 0);
    }

    function claimSurplus(uint256 who) external {
        address actor = actors[who % 4];
        if (vault.surplus(actor) == 0) return;
        uint256 a = vault.totalAssets();
        vm.prank(actor);
        vault.claimSurplus();
        _finish(a, 0);
    }

    function transferShares(uint256 from, uint256 to, uint256 raw) external {
        address actor = actors[from % 4];
        uint256 cap = vault.balanceOf(actor);
        if (cap == 0) return;
        uint256 a = vault.totalAssets();
        vm.prank(actor);
        vault.transfer(actors[to % 4], bound(raw, 1, cap));
        _finish(a, 0);
    }
}

contract BurrowVaultInvariantTest is BurrowVaultFixture {
    BurrowVaultHandler internal handler;

    function setUp() public {
        _setup(0);
        _seed(1e24);
        handler = new BurrowVaultHandler(vault, token, nft, staking);
    }

    function targetContracts() public view returns (address[] memory a) {
        a = new address[](1);
        a[0] = address(handler);
    }

    /// forge-config: default.invariant.runs = 256
    /// forge-config: default.invariant.depth = 64
    /// forge-config: default.invariant.fail-on-revert = true
    function invariant_AssetsConservedAndSharePriceMonotoneOnDepositWithdraw() public view {
        assertTrue(!handler.assetsDecreased(), "assets fell outside withdrawal");
        assertTrue(!handler.sharePriceDecreased(), "deposit or withdrawal reduced share price");
        assertEq(
            vault.totalAssets(),
            token.balanceOf(address(vault)) - vault.totalSurplus() + vault.totalPrincipal()
                + vault.totalAccruedInterest(),
            "assets reconcile"
        );
    }

    /// forge-config: default.invariant.runs = 256
    /// forge-config: default.invariant.depth = 64
    /// forge-config: default.invariant.fail-on-revert = true
    function invariant_DebtCreditAndStakedCollateralReconcile() public view {
        uint256 debt;
        uint256 lines;
        uint256 power;
        for (uint256 i; i < 4; i++) {
            address actor = handler.actors(i);
            BurrowVault.Position memory p = vault.positionOf(actor);
            debt += vault.debtOf(actor);
            lines += vault.creditLine(actor);
            power += p.power;
            assertLe(vault.debtOf(actor), vault.creditLine(actor), "borrower above fixed line");
            assertEq(nft.ownerOf(i + 1), p.tokenIds.length == 0 ? actor : address(staking), "collateral custody");
        }
        assertLe(debt, lines, "summed debt exceeds credit");
        assertEq(debt, vault.totalPrincipal() + vault.totalAccruedInterest(), "debt sum");
        assertEq(power, vault.totalEscrowedPower(), "power sum");
        assertEq(staking.nftPower(address(vault)), (power + vault.treasuryPower()) * 1e18, "staked power");
    }

    /// forge-config: default.invariant.runs = 256
    /// forge-config: default.invariant.depth = 64
    /// forge-config: default.invariant.fail-on-revert = true
    function invariant_SharesAndBondEscrowReconcile() public view {
        uint256 supply = vault.balanceOf(lender) + vault.balanceOf(address(vault));
        uint256 unclaimed;
        for (uint256 i; i < 4; i++) {
            address actor = handler.actors(i);
            supply += vault.balanceOf(actor);
            for (uint256 j; j < vault.bondCount(actor); j++) {
                BurrowVault.BondSchedule memory b = vault.bondSchedule(actor, j);
                assertLe(b.claimed, b.shares, "overclaimed bond");
                unclaimed += b.shares - b.claimed;
            }
        }
        assertEq(supply, vault.totalSupply(), "all share balances");
        assertEq(unclaimed, vault.unclaimedBondShares(), "vesting escrow");
        assertEq(vault.balanceOf(address(vault)), unclaimed + vault.lockedShares(), "escrow fully backed by shares");
    }
}

interface BurrowLiveStaking {
    function claimable(address) external view returns (uint256);
    function accountPower(address) external view returns (uint256, uint256);
    function basePower(address, uint8) external view returns (uint256);
    function stakeOf(address) external view returns (uint256);
    function exitPolicy() external view returns (uint16, uint16, uint16, uint8, uint256);
}

interface BurrowLivePermit {
    function DOMAIN_SEPARATOR() external view returns (bytes32);
    function nonces(address) external view returns (uint256);
}

abstract contract BurrowSepoliaForkFixture is BurrowTestBase {
    address internal constant SQK = address(bytes20(hex"5501e1fa81be1c3f49225fa7668da0245d07db60"));
    address internal constant NFT = address(bytes20(hex"cb98349c134ab983da5bfd80527dfe2552bdb70f"));
    address internal constant STAKING = address(bytes20(hex"4b67b739dfd832f4eac67a7aa3bc244fb74cea4f"));
    address internal constant MANAGER = 0xE03A1074c86CFeDd5C142C4F04F1a1536e203543;
    address internal constant POSITIONS = 0x429ba70129df741B2Ca2a85BC3A2a3328e5c09b4;
    address internal constant PERMIT2 = 0x000000000022D473030F116dDEE9F6B43aC78BA3;

    function _fork() internal {
        string memory url = vm.envOr("SEPOLIA_RPC_URL", string(""));
        if (bytes(url).length == 0) {
            vm.skip(true);
            return;
        }
        vm.createSelectFork(url, 12031552);
        assertEq(block.chainid, 11155111, "Sepolia chain");
        assertEq(block.number, 12031552, "pinned block");
    }

    function _liveVault() internal returns (BurrowVault v, BurrowValuer valuer) {
        valuer = new BurrowValuer(address(this), NFT, powers(), 1e18, 0.5e18, 2e18, 6000);
        IBurrowPositionManager.PoolKey memory k = IBurrowPositionManager.PoolKey(address(0), SQK, 3000, 60, address(0));
        v = new BurrowVault(
            BurrowVault.Config(
                address(this),
                SQK,
                NFT,
                STAKING,
                address(valuer),
                POSITIONS,
                MANAGER,
                keccak256(abi.encode(k)),
                1e10,
                1000,
                1000,
                10
            )
        );
    }
}

contract BurrowSepoliaForkTest is BurrowSepoliaForkFixture {
    function testFork_SepoliaVerifiedDependenciesAndExitPolicy() public {
        _fork();
        assertTrue(
            SQK.code.length != 0 && NFT.code.length != 0 && STAKING.code.length != 0, "SQK dependencies have code"
        );
        assertTrue(
            MANAGER.code.length != 0 && POSITIONS.code.length != 0 && PERMIT2.code.length != 0,
            "v4 dependencies have code"
        );
        assertEq(keccak256(bytes(IERC20Metadata(SQK).symbol())), keccak256("SQK"), "SQK identity");
        assertEq(IERC20Metadata(SQK).decimals(), 18, "SQK decimals");
        assertTrue(BurrowLivePermit(SQK).DOMAIN_SEPARATOR() != bytes32(0), "permit domain");
        BurrowLivePermit(SQK).nonces(address(this));
        assertEq(IBurrowPositionManager(POSITIONS).poolManager(), MANAGER, "position manager wiring");
        (uint16 minBps, uint16 maxBps, uint16 saturation, uint8 window, uint256 floor) =
            BurrowLiveStaking(STAKING).exitPolicy();
        assertEq(minBps, 200, "exit min");
        assertEq(maxBps, 6000, "exit max");
        assertEq(saturation, 2000, "saturation");
        assertEq(window, 7, "window");
        assertEq(floor, 21000000e18, "pressure floor");
    }

    function testFork_SepoliaRealCollateralEarningBorrowSweepRepayClose() public {
        _fork();
        (BurrowVault v, BurrowValuer valuer) = _liveVault();
        address lender = addr("fork lender");
        address holder = IERC721(NFT).ownerOf(1);
        assertTrue(holder != address(0) && holder != STAKING, "token 1 is held outside staking");
        deal(SQK, lender, 10000e18);
        vm.startPrank(lender);
        IERC20(SQK).approve(address(v), type(uint256).max);
        v.deposit(10000e18);
        vm.stopPrank();
        vm.startPrank(holder);
        IERC721(NFT).approve(address(v), 1);
        v.openPosition(ids(1));
        vm.stopPrank();
        assertEq(IERC721(NFT).ownerOf(1), STAKING, "real NFT escrowed in real staking");
        (uint256 livePower,) = BurrowLiveStaking(STAKING).accountPower(address(v));
        assertEq(livePower, 1000e18, "published level-one power");
        assertEq(v.positionOf(holder).levels[0], 1, "recorded live level");
        assertEq(v.creditLine(holder), valuer.creditLine(ids(1)), "real valuer line");
        vm.prank(holder);
        v.borrow(500e18);
        uint256 debt = v.debtOf(holder);
        vm.warp(block.timestamp + 1 days);
        uint256 claimable = BurrowLiveStaking(STAKING).claimable(address(v));
        assertTrue(claimable > 0, "escrowed collateral still earns");
        uint256 due = v.debtOf(holder);
        assertTrue(due > debt, "interest accrues on real collateral");
        uint256 backing = v.totalAssets();
        (uint256 received, uint256 repaid) = v.sweepRewards();
        assertTrue(received > 0, "real rewards reached vault");
        assertTrue(repaid > 0, "real rewards repay debt");
        assertEq(v.debtOf(holder), due - repaid, "reward repayment reconciles");
        assertEq(v.totalAssets(), backing + received - repaid, "no double counting real rewards");
        deal(SQK, holder, v.debtOf(holder) + 1e18);
        vm.startPrank(holder);
        IERC20(SQK).approve(address(v), type(uint256).max);
        v.repayAll();
        v.closePosition();
        vm.stopPrank();
        assertEq(IERC721(NFT).ownerOf(1), holder, "real collateral returned");
        assertEq(v.debtOf(holder), 0, "no remaining debt");
        assertEq(v.positionCount(), 0, "position closed");
        (livePower,) = BurrowLiveStaking(STAKING).accountPower(address(v));
        assertEq(livePower, 0, "real staking power removed");
    }
}

contract BurrowVaultBoundaryTest is BurrowVaultFixture {
    function setUp() public {
        _setup(RATE);
    }

    function test_PositionLimitRevertsAndClosingRestoresCapacity() public {
        for (uint256 i = 1; i <= 256; i++) {
            address actor = address(uint160(uint256(keccak256(abi.encode("capacity actor", i)))));
            _open(actor, i, 1);
        }
        assertEq(vault.positionCount(), 256, "capacity reached");
        nft.mint(alice, 257, 1);
        vm.prank(alice);
        nft.setApprovalForAll(address(vault), true);
        vm.expectRevert(BurrowVault.TooManyPositions.selector);
        vm.prank(alice);
        vault.openPosition(ids(257));
        assertEq(nft.ownerOf(257), alice, "limit did not escrow NFT");
        address first = vault.borrowerAt(0);
        vm.prank(first);
        vault.closePosition();
        vm.prank(alice);
        vault.openPosition(ids(257));
        assertEq(vault.positionCount(), 256, "closed slot reused");
    }

    function test_ZeroValueShareWithdrawalAndZeroShareBondRevert() public {
        _seed(1001);
        nft.mint(alice, 1, 1);
        vm.prank(alice);
        nft.setApprovalForAll(address(vault), true);
        vm.prank(alice);
        vault.bond(address(nft), 1, 1);
        vm.expectRevert(BurrowVault.ZeroAmount.selector);
        vm.prank(lender);
        vault.withdraw(1);
        // Use a fresh seeded vault with a high share price to exercise a bond
        // too small to mint even one share, without changing vault storage.
        vault = new BurrowVault(_config(0));
        _fund(lender, 1001);
        _fund(bob, 1e30);
        _seed(1001);
        vm.prank(bob);
        vault.donate(1e30);
        nft.mint(alice, 2, 1);
        vm.prank(alice);
        nft.setApprovalForAll(address(vault), true);
        vm.expectRevert(BurrowVault.ZeroShares.selector);
        vm.prank(alice);
        vault.bond(address(nft), 2, 0);
        assertEq(nft.ownerOf(2), alice, "rounded-to-zero bond trapped NFT");
    }

    function test_InvalidValuerLtvAndLPInvalidTicksFailClosed() public {
        BurrowVault.Config memory c = _config(0);
        vm.mockCall(address(valuer), abi.encodeWithSignature("ltvBps()"), abi.encode(0));
        vm.expectRevert(BurrowVault.InvalidParameter.selector);
        new BurrowVault(c);
        vm.mockCall(address(valuer), abi.encodeWithSignature("ltvBps()"), abi.encode(6001));
        vm.expectRevert(BurrowVault.InvalidParameter.selector);
        new BurrowVault(c);
        vm.clearMockedCalls();
        positions.configure(poolKey, 887273, 887274, 1);
        vm.expectRevert(abi.encodeWithSelector(BurrowTickMath.InvalidTick.selector, int24(887273)));
        vault.positionSQKPrincipal(1);
    }

    function test_LiquidationBonusAndSurplusCannotBeCapturedByOwner() public {
        _setup(0);
        _seed(10000e18);
        _open(alice, 1, 1);
        _borrow(alice, 590e18);
        valuer.proposePricePerPower(0.8e18);
        vm.warp(block.timestamp + 2 days);
        valuer.executePricePerPower();
        vm.warp(block.timestamp + 1 hours);
        uint256 liquidatorBefore = token.balanceOf(liquidator);
        uint256 backing = vault.totalAssets();
        vm.prank(liquidator);
        assertEq(vault.liquidate(alice), 741e18, "800 SQK collateral less 59 SQK bonus");
        assertEq(liquidatorBefore - token.balanceOf(liquidator), 741e18, "liquidator funded full purchase");
        assertEq(vault.surplus(alice), 151e18, "741 purchase less 590 debt belongs to borrower");
        assertEq(vault.totalAssets(), backing, "borrower equity is not shareholder income");
        vm.expectRevert(BurrowVault.NothingToClaim.selector);
        vault.claimSurplus();
        vm.expectRevert(BurrowVault.NothingToClaim.selector);
        vm.prank(liquidator);
        vault.claimSurplus();
        uint256 borrowerBefore = token.balanceOf(alice);
        vm.prank(alice);
        vault.claimSurplus();
        assertEq(token.balanceOf(alice) - borrowerBefore, 151e18, "only borrower receives equity");
    }

    function test_LPValuationHandlesSQKAsCurrencyOneAndRangeEdges() public {
        IBurrowPositionManager.PoolKey memory k =
            IBurrowPositionManager.PoolKey(address(nft), address(token), 3000, 60, address(0));
        BurrowVault.Config memory c = _config(0);
        c.bondPoolId = keccak256(abi.encode(k));
        BurrowVault v = new BurrowVault(c);
        positions.configure(k, -600, 600, 1e24);
        uint160 low = BurrowTickMath.sqrtPriceAtTick(-600);
        uint160 high = BurrowTickMath.sqrtPriceAtTick(600);
        manager.setPrice(c.bondPoolId, low);
        assertEq(v.positionSQKPrincipal(1), 0, "no SQK below range");
        manager.setPrice(c.bondPoolId, uint160(1 << 96));
        assertEq(
            v.positionSQKPrincipal(1), uint256(1e24) * ((1 << 96) - low) / (1 << 96), "in-range currency-one principal"
        );
        manager.setPrice(c.bondPoolId, high);
        assertEq(
            v.positionSQKPrincipal(1), uint256(1e24) * (uint256(high) - low) / (1 << 96), "all currency one above range"
        );
        manager.setPrice(c.bondPoolId, BurrowTickMath.MAX_SQRT_PRICE);
        vm.expectRevert(BurrowVault.WrongPool.selector);
        v.positionSQKPrincipal(1);
        k.currency1 = address(staking);
        c.bondPoolId = keccak256(abi.encode(k));
        v = new BurrowVault(c);
        positions.configure(k, -600, 600, 1e24);
        vm.expectRevert(BurrowVault.WrongPool.selector);
        v.positionSQKPrincipal(1);
    }

    function test_AscendingIdsAtUint256Boundary() public {
        uint256[] memory a = new uint256[](2);
        a[0] = type(uint256).max - 1;
        a[1] = type(uint256).max;
        nft.mint(alice, a[0], 1);
        nft.mint(alice, a[1], 2);
        vm.startPrank(alice);
        nft.setApprovalForAll(address(vault), true);
        vault.openPosition(a);
        vm.stopPrank();
        assertEq(vault.creditLine(alice), 2400e18, "full-width IDs valued");
        vm.prank(alice);
        vault.closePosition();
        assertEq(nft.ownerOf(a[0]), alice, "first full-width ID returned");
        assertEq(nft.ownerOf(a[1]), alice, "second full-width ID returned");
    }

    /// forge-config: default.fuzz.runs = 1000
    function testFuzz_AccrualIsIndependentOfTouchFrequency(uint128 raw, uint32 secondsRaw, uint8 touchesRaw) public {
        _seed(10000e18);
        _open(alice, 1, 1);
        uint256 principal = bound(raw, 1, 600e18);
        _borrow(alice, principal);
        uint256 elapsed = bound(secondsRaw, 1, 365 days);
        uint256 touches = bound(touchesRaw, 1, 24);
        uint256 start = block.timestamp;
        for (uint256 i = 1; i <= touches; i++) {
            vm.warp(start + elapsed * i / touches);
            vault.sweepRewards();
        }
        uint256 interest = principal * RATE * elapsed / 1e18;
        assertEq(vault.debtOf(alice), principal + interest, "accrual depends on touches");
        assertEq(vault.totalAccruedInterest(), interest, "global interest");
        assertEq(vault.totalAssets(), 10000e18 + interest, "interest recognized once");
        vm.prank(alice);
        vault.repayAll();
        assertEq(vault.positionOf(alice).interestRemainder, 0, "full repayment clears fraction");
    }

    /// forge-config: default.fuzz.runs = 1000
    function testFuzz_RewardAllocationsConserveDebtAndAssets(uint128 rewardRaw, uint128 firstRaw, uint128 secondRaw)
        public
    {
        _seed(10000e18);
        _open(alice, 1, 1);
        _open(bob, 2, 3);
        uint256 first = bound(firstRaw, 1, 600e18);
        uint256 second = bound(secondRaw, 1, 4200e18);
        uint256 reward = bound(rewardRaw, 1, 1e24);
        _borrow(alice, first);
        _borrow(bob, second);
        uint256 assets = vault.totalAssets();
        staking.fund(address(vault), reward);
        (uint256 received, uint256 repaid) = vault.sweepRewards();
        uint256 firstPay = Math.min(reward / 8, first);
        uint256 secondPay = Math.min(reward * 7 / 8, second);
        assertEq(received, reward, "received amount");
        assertEq(repaid, firstPay + secondPay, "power-weighted reduction");
        assertEq(vault.debtOf(alice), first - firstPay, "first debt");
        assertEq(vault.debtOf(bob), second - secondPay, "second debt");
        assertEq(vault.totalAssets(), assets + reward - repaid, "reward income after repayments");
    }

    /// forge-config: default.fuzz.runs = 1000
    function testFuzz_ClaimingBondInPartsCannotOverclaim(uint32 rawElapsed, uint16 rawDiscount) public {
        _seed(10000e18);
        uint256 discount = bound(rawDiscount, 0, 2000);
        vault.setBondDiscountBps(discount);
        nft.mint(alice, 1, 1);
        vm.prank(alice);
        nft.setApprovalForAll(address(vault), true);
        vm.prank(alice);
        uint256 shares = vault.bond(address(nft), 1, 1);
        assertEq(shares, 1000e18 + 1000e18 * discount / 10000, "capped discount");
        uint256 start = block.timestamp;
        uint256 elapsed = bound(rawElapsed, 0, 10 days);
        vm.warp(start + elapsed);
        uint256 vested = shares * elapsed / 10 days;
        assertEq(vault.claimableBond(alice), vested, "linear vesting rounds down");
        if (vested != 0) {
            vm.prank(alice);
            vault.claimBond();
        }
        assertEq(vault.balanceOf(alice), vested, "only vested shares transferred");
        vm.warp(start + 10 days);
        if (elapsed < 10 days) {
            vm.prank(alice);
            vault.claimBond();
        }
        assertEq(vault.balanceOf(alice), shares, "total claims equal schedule");
        assertEq(vault.unclaimedBondShares(), 0, "no outstanding obligation");
        vm.expectRevert(BurrowVault.NothingToClaim.selector);
        vm.prank(alice);
        vault.claimBond();
    }
}

contract BurrowNFTBondSepoliaForkTest is BurrowSepoliaForkFixture {
    function testFork_SepoliaBondedNFTKeepsEarningForShareholders() public {
        _fork();
        (BurrowVault v,) = _liveVault();
        address lender = addr("NFT bond lender");
        address holder = IERC721(NFT).ownerOf(3);
        deal(SQK, lender, 10000e18);
        vm.startPrank(lender);
        IERC20(SQK).approve(address(v), type(uint256).max);
        v.deposit(10000e18);
        vm.stopPrank();
        vm.startPrank(holder);
        IERC721(NFT).approve(address(v), 3);
        uint256 shares = v.bond(NFT, 3, 1);
        vm.stopPrank();
        assertEq(IERC721(NFT).ownerOf(3), STAKING, "real bonded NFT staked");
        assertTrue(v.treasuryNFT(3), "bonded NFT retained");
        uint256 backing = v.totalAssets();
        vm.warp(block.timestamp + 1 days);
        assertTrue(BurrowLiveStaking(STAKING).claimable(address(v)) > 0, "treasury NFT earns");
        (uint256 income, uint256 repaid) = v.sweepRewards();
        assertTrue(income > 0, "treasury reward received");
        assertEq(repaid, 0, "no borrower debt for treasury power");
        assertEq(v.totalAssets(), backing + income, "all treasury rewards to shareholders");
        vm.warp(block.timestamp + 9 days);
        vm.prank(holder);
        assertEq(v.claimBond(), shares, "real NFT bond vested");
        assertEq(IERC721(NFT).ownerOf(3), STAKING, "vesting retains treasury collateral");
    }
}

// Permit2 is shared by the v4 deployments. Exercise its real mainnet bytecode
// with newly deployed bSQK shares; SQK, NFT and staking remain local fixtures in
// these tests. The Sepolia tests above cover the live Squeekchain contracts.
interface BurrowMainnetPermit2 {
    error AllowanceExpired(uint256 deadline);
    error InsufficientAllowance(uint256 amount);

    function approve(address token, address spender, uint160 amount, uint48 expiration) external;
    function allowance(address owner, address token, address spender)
        external
        view
        returns (uint160 amount, uint48 expiration, uint48 nonce);
    function transferFrom(address from, address to, uint160 amount, address token) external;
    function DOMAIN_SEPARATOR() external view returns (bytes32);
}

contract BurrowVaultMainnetForkTest is BurrowVaultFixture {
    BurrowMainnetPermit2 internal constant permit2 = BurrowMainnetPermit2(0x000000000022D473030F116dDEE9F6B43aC78BA3);

    function _forkMainnet() internal {
        string memory url = vm.envOr("MAINNET_RPC_URL", string(""));
        if (bytes(url).length == 0) {
            vm.skip(true);
            return;
        }
        vm.createSelectFork(url, 26310460);
        assertEq(block.chainid, 1, "mainnet chain");
        assertEq(block.number, 26310460, "pinned mainnet block");
        assertTrue(address(permit2).code.length != 0, "live mainnet Permit2 has code");
        assertTrue(permit2.DOMAIN_SEPARATOR() != bytes32(0), "live mainnet Permit2 responds");

        uint256 forkTimestamp = block.timestamp;
        _setup(0);
        // The offline fixture uses a synthetic timestamp. Restore the fork's
        // timestamp before exercising live Permit2 expiration checks.
        vm.warp(forkTimestamp);
        _seed(10000e18);
        vm.prank(alice);
        vault.donate(1000e18);
    }

    function _approveShares(uint160 shares, uint48 expiration) internal {
        vm.startPrank(lender);
        vault.approve(address(permit2), shares);
        permit2.approve(address(vault), alice, shares, expiration);
        vm.stopPrank();
    }

    function _assertAllowance(uint160 expected, uint48 expiration) internal view {
        (uint160 amount, uint48 deadline, uint48 nonce) = permit2.allowance(lender, address(vault), alice);
        assertEq(amount, expected, "remaining Permit2 allowance");
        assertEq(deadline, expiration, "allowance expiration unchanged");
        assertEq(nonce, 0, "onchain approval does not consume signature nonce");
    }

    function testFork_MainnetPermit2TransfersYieldBearingSharesAndRedeems() public {
        _forkMainnet();
        uint48 expiration = uint48(block.timestamp + 1 hours);
        _approveShares(100e18, expiration);
        uint256 assets = vault.totalAssets();
        uint256 supply = vault.totalSupply();
        uint256 lenderShares = vault.balanceOf(lender);
        uint256 recipientAssets = token.balanceOf(bob);

        vm.prank(alice);
        permit2.transferFrom(lender, bob, 40e18, address(vault));
        _assertAllowance(60e18, expiration);
        assertEq(vault.totalAssets(), assets, "share transfer preserves backing");
        assertEq(vault.totalSupply(), supply, "share transfer neither mints nor burns");
        assertEq(vault.balanceOf(lender), lenderShares - 40e18, "only approved shares leave lender");
        assertEq(vault.balanceOf(bob), 40e18, "recipient receives bSQK");
        vm.prank(bob);
        assertEq(vault.withdraw(40e18), 44e18, "transferred shares retain donation income");
        assertEq(token.balanceOf(bob) - recipientAssets, 44e18, "recipient paid exact backing");
        assertEq(vault.totalAssets(), assets - 44e18, "withdrawal removes only paid assets");
        assertEq(vault.totalSupply(), supply - 40e18, "withdrawal burns transferred shares");

        vm.prank(alice);
        permit2.transferFrom(lender, bob, 60e18, address(vault));
        _assertAllowance(0, expiration);
        vm.expectRevert(abi.encodeWithSelector(BurrowMainnetPermit2.InsufficientAllowance.selector, 0));
        vm.prank(alice);
        permit2.transferFrom(lender, bob, 1, address(vault));
        assertEq(vault.balanceOf(lender), lenderShares - 100e18, "exhausted approval cannot take another wei");
        assertEq(vault.balanceOf(bob), 60e18, "failed transfer leaves recipient unchanged");
        assertEq(vault.totalAssets(), assets - 44e18, "rejected transfer cannot change backing");
        assertEq(vault.totalSupply(), supply - 40e18, "rejected transfer cannot change supply");
    }

    function testFork_MainnetPermit2RejectsWrongSpenderAndExpiredApproval() public {
        _forkMainnet();
        uint48 expiration = uint48(block.timestamp + 1 hours);
        _approveShares(100e18, expiration);
        uint256 lenderShares = vault.balanceOf(lender);

        // Another spender cannot use Alice's approval, even though the lender
        // has approved the Permit2 contract at the ERC20 layer.
        vm.expectRevert(abi.encodeWithSelector(BurrowMainnetPermit2.AllowanceExpired.selector, 0));
        vm.prank(liquidator);
        permit2.transferFrom(lender, bob, 1, address(vault));
        _assertAllowance(100e18, expiration);
        assertEq(vault.balanceOf(lender), lenderShares, "unauthorized spender cannot debit lender");
        assertEq(vault.balanceOf(bob), 0, "unauthorized transfer pays nothing");

        vm.warp(expiration);
        vm.prank(alice);
        permit2.transferFrom(lender, bob, 1, address(vault));
        _assertAllowance(100e18 - 1, expiration);
        vm.warp(uint256(expiration) + 1);
        vm.expectRevert(abi.encodeWithSelector(BurrowMainnetPermit2.AllowanceExpired.selector, expiration));
        vm.prank(alice);
        permit2.transferFrom(lender, bob, 1, address(vault));
        _assertAllowance(100e18 - 1, expiration);
        assertEq(vault.balanceOf(lender), lenderShares - 1, "expired transfer cannot debit lender");
        assertEq(vault.balanceOf(bob), 1, "only the transfer at the deadline succeeded");
        assertEq(vault.totalAssets(), 11000e18, "approval boundaries preserve backing");
        assertEq(vault.totalSupply(), 10000e18, "approval boundaries preserve supply");
    }

    function testFork_MainnetPermit2RevocationAtEitherApprovalLayerPreservesShares() public {
        _forkMainnet();
        uint48 expiration = uint48(block.timestamp + 1 hours);
        _approveShares(100e18, expiration);
        uint256 lenderShares = vault.balanceOf(lender);

        vm.prank(lender);
        vault.approve(address(permit2), 0);
        vm.expectRevert(abi.encodeWithSignature("Error(string)", "TRANSFER_FROM_FAILED"));
        vm.prank(alice);
        permit2.transferFrom(lender, bob, 1, address(vault));
        _assertAllowance(100e18, expiration);
        assertEq(vault.balanceOf(lender), lenderShares, "ERC20 revocation prevents debits");

        vm.startPrank(lender);
        vault.approve(address(permit2), 100e18);
        permit2.approve(address(vault), alice, 0, expiration);
        vm.stopPrank();
        vm.expectRevert(abi.encodeWithSelector(BurrowMainnetPermit2.InsufficientAllowance.selector, 0));
        vm.prank(alice);
        permit2.transferFrom(lender, bob, 1, address(vault));
        _assertAllowance(0, expiration);
        assertEq(vault.balanceOf(lender), lenderShares, "Permit2 revocation prevents debits");
        assertEq(vault.balanceOf(bob), 0, "neither failed transfer pays recipient");
        assertEq(vault.allowance(lender, address(permit2)), 100e18, "failed transfer preserves ERC20 allowance");
        assertEq(vault.totalAssets(), 11000e18, "revocations preserve backing");
        assertEq(vault.totalSupply(), 10000e18, "revocations preserve supply");
    }
}

contract BurrowAccruingVaultInvariantTest is BurrowVaultFixture {
    BurrowVaultHandler internal handler;

    function setUp() public {
        _setup(RATE);
        _seed(1e24);
        handler = new BurrowVaultHandler(vault, token, nft, staking);
    }

    function targetContracts() public view returns (address[] memory a) {
        a = new address[](1);
        a[0] = address(handler);
    }

    /// forge-config: default.invariant.runs = 256
    /// forge-config: default.invariant.depth = 64
    /// forge-config: default.invariant.fail-on-revert = true
    function invariant_AccruingDebtLiquidationsAndReservesRemainFullyAccounted() public view {
        assertTrue(!handler.assetsDecreased(), "assets fell outside withdrawal");
        assertTrue(!handler.sharePriceDecreased(), "deposit or withdrawal lowered price");
        uint256 debt;
        uint256 principal;
        uint256 bookedInterest;
        uint256 reserves;
        uint256 power;
        uint256 unclaimed;
        uint256 supply = vault.balanceOf(lender) + vault.balanceOf(address(vault));
        for (uint256 i; i < 4; i++) {
            address actor = handler.actors(i);
            BurrowVault.Position memory p = vault.positionOf(actor);
            principal += p.principal;
            bookedInterest += p.interest;
            debt += vault.debtOf(actor);
            reserves += vault.surplus(actor);
            power += p.power;
            supply += vault.balanceOf(actor);
            if (p.tokenIds.length > 0) {
                assertEq(nft.ownerOf(p.tokenIds[0]), address(staking), "active collateral escaped staking");
            }
            for (uint256 j; j < vault.bondCount(actor); j++) {
                BurrowVault.BondSchedule memory b = vault.bondSchedule(actor, j);
                assertLe(b.claimed, b.shares, "overclaimed bond");
                unclaimed += b.shares - b.claimed;
            }
        }
        assertEq(principal, vault.totalPrincipal(), "principal sum");
        assertEq(bookedInterest, vault.totalAccruedInterest(), "booked interest sum");
        assertEq(reserves, vault.totalSurplus(), "liquidation surplus sum");
        assertEq(
            vault.totalAssets(),
            token.balanceOf(address(vault)) - reserves + debt,
            "cash plus pending debt less reserves"
        );
        assertEq(power, vault.totalEscrowedPower(), "active power sum");
        assertEq(
            staking.nftPower(address(vault)), (power + vault.treasuryPower()) * 1e18, "staking backs recorded power"
        );
        assertEq(supply, vault.totalSupply(), "share supply");
        assertEq(unclaimed, vault.unclaimedBondShares(), "bond liabilities");
        assertEq(vault.balanceOf(address(vault)), unclaimed + vault.lockedShares(), "vesting shares held");
    }
}
