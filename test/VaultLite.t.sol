// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {BurrowVaultLite} from "../src/BurrowVaultLite.sol";

contract MockSQK {
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;
    function mint(address t, uint256 v) external { balanceOf[t] += v; }
    function approve(address s, uint256 v) external returns (bool) { allowance[msg.sender][s] = v; return true; }
    function transfer(address t, uint256 v) external returns (bool) { balanceOf[msg.sender] -= v; balanceOf[t] += v; return true; }
    function transferFrom(address f, address t, uint256 v) external returns (bool) {
        if (allowance[f][msg.sender] != type(uint256).max) allowance[f][msg.sender] -= v;
        balanceOf[f] -= v; balanceOf[t] += v; return true;
    }
}
contract MockNFT {
    mapping(uint256 => address) public ownerOf;
    mapping(address => mapping(address => bool)) public isApprovedForAll;
    function mint(address t, uint256 id) external { ownerOf[id] = t; }
    function setApprovalForAll(address op, bool ok) external { isApprovedForAll[msg.sender][op] = ok; }
    function transferFrom(address f, address t, uint256 id) external { require(ownerOf[id] == f, "owner"); ownerOf[id] = t; }
}
contract MockStaking {
    MockSQK public sqk; MockNFT public nft;
    mapping(address => uint256) public pending;
    mapping(address => uint256) public accountPower;
    uint256 public constant POWER_PER_ID = 1000e18;
    constructor(MockSQK s, MockNFT n) { sqk = s; nft = n; }
    function deposit(address c, uint256[] calldata ids) external { for (uint256 i; i < ids.length; ++i) MockNFT(c).transferFrom(msg.sender, address(this), ids[i]); accountPower[msg.sender] += ids.length * POWER_PER_ID; }
    function withdraw(address c, uint256[] calldata ids) external { for (uint256 i; i < ids.length; ++i) MockNFT(c).transferFrom(address(this), msg.sender, ids[i]); accountPower[msg.sender] -= ids.length * POWER_PER_ID; }
    function setClaimRecipient(address) external {}
    function claimable(address a) external view returns (uint256) { return pending[a]; }
    function accrueFor(address a, uint256 v) external { pending[a] += v; sqk.mint(address(this), v); }
    function claim(address a) external { uint256 v = pending[a]; pending[a] = 0; if (v != 0) sqk.transfer(a, v); }   // real staking: claim(account) pays account's recipient
    function claimFor(address a) external { uint256 v = pending[a]; pending[a] = 0; if (v != 0) sqk.transfer(a, v); }
}
contract MockValuer {
    uint256 public ltvBps = 6000;
    uint256 public lastPriceChange;
    uint256 public perId = 100e18;        // credit line per token id
    function creditLine(uint256[] calldata ids) external view returns (uint256) { return ids.length * perId; }
    function setPerId(uint256 v) external { perId = v; lastPriceChange = block.timestamp; }
}

contract VaultLiteTest is Test {
    MockSQK sqk; MockNFT nft; MockStaking stk; MockValuer val; BurrowVaultLite v;
    address lender = address(0xA1); address bob = address(0xB0); address liq = address(0xC0);
    uint256 constant RATE = uint256(0.08e18) / 365 days;

    function setUp() public virtual {
        sqk = new MockSQK(); nft = new MockNFT(); stk = new MockStaking(sqk, nft); val = new MockValuer();
        v = new BurrowVaultLite(address(sqk), address(nft), address(stk), address(val), RATE);
        sqk.mint(lender, 1_000_000e18); sqk.mint(bob, 1_000_000e18); sqk.mint(liq, 1_000_000e18);
        vm.prank(lender); sqk.approve(address(v), type(uint256).max);
        vm.prank(bob); sqk.approve(address(v), type(uint256).max);
        vm.prank(liq); sqk.approve(address(v), type(uint256).max);
        nft.mint(bob, 1); nft.mint(bob, 2);
        vm.prank(bob); nft.setApprovalForAll(address(v), true);
        vm.warp(block.timestamp + 2 hours);        // qua cửa đóng băng thanh lý
    }

    function _seed(uint256 a) internal { vm.prank(lender); v.deposit(a, 0); }

    function test_FirstDepositLocksMinimumLiquidity() public {
        _seed(1000e18);
        assertEq(v.balanceOf(lender), 1000e18 - 1000, "shares minus locked");
        assertGt(v.balanceOf(address(v)), 0, "locked shares held by vault");
    }

    function test_FirstDepositMustExceedMinimum() public {
        vm.prank(lender);
        vm.expectRevert(BurrowVaultLite.MinFirstDeposit.selector);
        v.deposit(1000, 0);
    }

    function test_DonateRaisesSharePriceWithoutMinting() public {
        _seed(1000e18);
        uint256 before = v.convertToAssets(1e18);
        uint256 supply = v.totalSupply();
        vm.prank(bob); v.donate(100e18);
        assertEq(v.totalSupply(), supply, "no new shares");
        assertGt(v.convertToAssets(1e18), before, "price up");
    }

    function test_SharePriceNeverFallsOnDepositOrWithdraw() public {
        _seed(1000e18);
        uint256 p0 = v.convertToAssets(1e18);
        vm.prank(bob); sqk.approve(address(v), type(uint256).max);
        vm.prank(bob); v.deposit(500e18, 0);
        assertGe(v.convertToAssets(1e18), p0, "deposit");
        vm.prank(lender); v.withdraw(100e18, 0);
        assertGe(v.convertToAssets(1e18), p0, "withdraw");
    }

    function _open() internal {
        uint256[] memory ids = new uint256[](2); ids[0] = 1; ids[1] = 2;
        vm.prank(bob); v.openPosition(ids);
    }

    function test_OpenStakesCollateralAndSetsPower() public {
        _seed(10_000e18); _open();
        assertEq(nft.ownerOf(1), address(stk), "staked");
        assertEq(v.creditLineOf(bob), 200e18, "line");
        assertGt(v.positionPower(bob), 0, "power");
    }

    function test_BorrowRefusedAboveLine() public {
        _seed(10_000e18); _open();
        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSelector(BurrowVaultLite.OverLine.selector, 200e18 + 1, 200e18));
        v.borrow(200e18 + 1);
    }

    function test_BorrowRepayClose() public {
        _seed(10_000e18); _open();
        vm.prank(bob); v.borrow(100e18);
        assertEq(sqk.balanceOf(bob), 1_000_000e18 + 100e18, "received");
        vm.prank(bob); v.repay(type(uint256).max);
        assertEq(v.debtOf(bob), 0, "cleared");
        vm.prank(bob); v.closePosition();
        assertEq(nft.ownerOf(1), bob, "returned");
    }

    function test_InterestAccrues() public {
        _seed(10_000e18); _open();
        vm.prank(bob); v.borrow(100e18);
        uint256 d0 = v.debtOf(bob);
        vm.warp(block.timestamp + 365 days);
        uint256 d1 = v.debtOf(bob);
        assertGt(d1, d0, "grew");
        assertApproxEqRel(d1, 108e18, 0.02e18, "about 8 percent");
    }

    function test_SweepRewardsCutsDebt() public {
        _seed(10_000e18); _open();
        vm.prank(bob); v.borrow(100e18);
        uint256 d0 = v.debtOf(bob);
        stk.accrueFor(address(v), 30e18);
        v.sweepRewards();
        uint256 d1 = v.debtOf(bob);
        assertLt(d1, d0, "hamster paid it down");
        assertApproxEqAbs(d0 - d1, 30e18, 1e15, "credited in full");
    }

    function test_LiquidateOnlyWhenOverLine() public {
        _seed(10_000e18); _open();
        vm.prank(bob); v.borrow(100e18);
        vm.prank(liq);
        vm.expectRevert(BurrowVaultLite.Healthy.selector);
        v.liquidate(bob);

        val.setPerId(20e18);                      // giá rơi
        vm.prank(liq);
        vm.expectRevert(BurrowVaultLite.Frozen.selector);
        v.liquidate(bob);                         // đóng băng 1 giờ

        vm.warp(block.timestamp + 2 hours);
        vm.prank(liq); v.liquidate(bob);
        assertEq(nft.ownerOf(1), liq, "collateral moved");
        assertEq(v.debtOf(bob), 0, "debt cleared");
    }

    function test_WithdrawBlockedWhenFullyUtilised() public {
        _seed(200e18); _open();
        vm.prank(bob); v.borrow(200e18);
        vm.prank(lender);
        vm.expectRevert();
        v.withdraw(150e18, 0);
    }

    function test_IdsMustBeAscendingAndBounded() public {
        _seed(10_000e18);
        uint256[] memory bad = new uint256[](2); bad[0] = 2; bad[1] = 1;
        vm.prank(bob);
        vm.expectRevert(BurrowVaultLite.BadIds.selector);
        v.openPosition(bad);
    }
}

contract VaultLiteAuditTest is VaultLiteTest {
    address lender2 = address(0xA2);
    function setUp() public override {
        super.setUp();
        sqk.mint(lender2, 1_000_000e18);
        vm.prank(lender2); sqk.approve(address(v), type(uint256).max);
    }
    function _open2() internal { uint256[] memory ids = new uint256[](2); ids[0]=1; ids[1]=2; vm.prank(bob); v.openPosition(ids); }

    /// Sweep must not move the share price before borrowers settle; a lender who
    /// deposits after the sweep and withdraws at once must not profit.
    function test_SweepDoesNotMoveSharePriceBeforeSettle() public {
        _seed(1000e18); _open2();
        vm.prank(bob); v.borrow(100e18);
        uint256 pxBefore = v.convertToAssets(1e18);
        stk.accrueFor(address(v), 50e18);
        v.sweepRewards();
        assertApproxEqAbs(v.unsettled(), 50e18, 10, "swept but unsettled");
        assertEq(v.convertToAssets(1e18), pxBefore, "price flat across sweep");
        vm.startPrank(lender2);
        uint256 sh = v.deposit(1000e18, 0);
        uint256 out = v.withdraw(sh, 0);
        vm.stopPrank();
        assertLe(out, 1000e18, "no free money from sweep");
        vm.prank(bob); v.repay(1); // settles bob
        assertEq(v.unsettled(), 0, "credit consumed");
        assertApproxEqAbs(v.debtOf(bob), 100e18 - 50e18 - 1, 10, "debt cut by the whole sweep");
    }

    /// Rewards above the debt belong to the borrower, not the lenders.
    function test_SurplusRewardsReturnToBorrower() public {
        _seed(1000e18); _open2();
        uint256 px = v.convertToAssets(1e18);
        uint256 bal = sqk.balanceOf(bob);
        stk.accrueFor(address(v), 50e18);
        v.sweepRewards();
        vm.prank(bob); v.closePosition();
        assertApproxEqAbs(sqk.balanceOf(bob), bal + 50e18, 10, "surplus paid out");
        assertEq(v.convertToAssets(1e18), px, "lenders unchanged");
        assertEq(v.unsettled(), 0);
        assertEq(nft.ownerOf(1), bob);
    }

    /// Lenders cannot withdraw swept rewards that are owed to borrowers.
    function test_WithdrawCannotTakeUnsettledRewards() public {
        _seed(200e18); _open2();
        vm.prank(bob); v.borrow(200e18);              // idle = 0
        stk.accrueFor(address(v), 50e18);
        v.sweepRewards();
        assertEq(sqk.balanceOf(address(v)), 50e18);
        assertLe(v.idle(), 10, "only rounding dust is lender cash");
        vm.prank(lender);
        vm.expectRevert(abi.encodeWithSelector(BurrowVaultLite.NoLiquidity.selector, 1e18, v.idle()));
        v.withdraw(1e18, 0);
    }

    /// Liquidator pays value less the 10% bonus; the rest goes to the borrower.
    function test_LiquidationPaysBonusAndRefundsBorrower() public {
        _seed(1000e18); _open2();
        vm.prank(bob); v.borrow(200e18);              // line 200 at perId 100
        val.setPerId(70e18);                          // line 140, value 233.3, threshold 175 < debt 200
        vm.warp(block.timestamp + 2 hours);
        uint256 debt = v.debtOf(bob);
        uint256 bobBal = sqk.balanceOf(bob);
        uint256 liqBal = sqk.balanceOf(liq);
        vm.prank(liq); v.liquidate(bob);
        uint256 paid = liqBal - sqk.balanceOf(liq);
        uint256 value = uint256(140e18) * 10000 / 6000;
        assertEq(paid, value * 9000 / 10000, "pays 90% of value");
        assertGt(paid, debt, "above debt");
        assertEq(sqk.balanceOf(bob) - bobBal, paid - debt, "borrower gets the remainder");
        assertEq(nft.ownerOf(1), liq); assertEq(nft.ownerOf(2), liq);
        assertEq(v.debtOf(bob), 0);
        assertEq(v.idle(), 1000e18 - 200e18 + debt, "lenders hold cash plus the paid debt");
    }

    /// Borrowing up to the line must not be liquidatable a second later: threshold sits above LTV.
    function test_ThresholdAboveBorrowCap() public {
        _seed(1000e18); _open2();
        vm.prank(bob); v.borrow(200e18);
        vm.warp(block.timestamp + 365 days);          // +8% interest
        assertGt(v.debtOf(bob), 200e18);
        assertApproxEqAbs(v.liquidationThresholdOf(bob), 250e18, 10);
        vm.prank(liq); vm.expectRevert(BurrowVaultLite.Healthy.selector); v.liquidate(bob);
    }

    /// A position sunk below 90% of value is still cleared; lenders absorb the shortfall.
    function test_LiquidationDeepUnderwaterWritesOffShortfall() public {
        _seed(1000e18); _open2();
        vm.prank(bob); v.borrow(200e18);
        val.setPerId(50e18);                          // value 166.67, 90% = 150 < debt 200
        vm.warp(block.timestamp + 2 hours);
        uint256 px = v.convertToAssets(1e18);
        uint256 liqBal = sqk.balanceOf(liq); uint256 bobBal = sqk.balanceOf(bob);
        vm.prank(liq); v.liquidate(bob);
        uint256 paid = liqBal - sqk.balanceOf(liq);
        assertApproxEqAbs(paid, 150e18, 10, "pays 90% of value even underwater");
        assertEq(sqk.balanceOf(bob), bobBal, "no refund when underwater");
        assertEq(v.debtOf(bob), 0); assertEq(v.scaledDebt(), 0, "bad debt written off");
        assertLt(v.convertToAssets(1e18), px, "shortfall absorbed by share price");
        assertEq(nft.ownerOf(1), liq);
    }

    /// Rewards mined before a position opened never reach it (open sweeps first).
    function test_NewPositionCannotTakeOldRewards() public {
        _seed(1000e18); _open2();
        vm.prank(bob); v.borrow(100e18);
        stk.accrueFor(address(v), 50e18);             // mined by bob's NFTs, not yet swept
        address eve = address(0xE0E); nft.mint(eve, 7); nft.mint(eve, 8);
        vm.startPrank(eve); nft.setApprovalForAll(address(v), true);
        uint256[] memory ids = new uint256[](2); ids[0]=7; ids[1]=8;
        v.openPosition(ids); v.sweepRewards();
        uint256 eveBal = sqk.balanceOf(eve); v.closePosition(); vm.stopPrank();
        assertEq(sqk.balanceOf(eve), eveBal, "eve got nothing");
        vm.prank(bob); v.repay(1);
        assertApproxEqAbs(v.debtOf(bob), 50e18 - 1, 10, "bob credited in full");
    }

    /// Closing or liquidating settles pending staking rewards first.
    function test_CloseSweepsPendingRewardsFirst() public {
        _seed(1000e18); _open2();
        vm.prank(bob); v.borrow(100e18);
        stk.accrueFor(address(v), 100e18);            // more than the whole debt
        uint256 bal = sqk.balanceOf(bob);
        vm.prank(bob); v.closePosition();             // no repay needed: pending rewards settle inside
        assertEq(nft.ownerOf(1), bob);
        assertApproxEqAbs(sqk.balanceOf(bob), bal + (100e18 - 100e18), 10, "surplus zero after debt");
    }

    function test_TransferToZeroReverts() public {
        _seed(1000e18);
        vm.prank(lender); vm.expectRevert(BurrowVaultLite.Zero.selector); v.transfer(address(0), 1);
    }
}
