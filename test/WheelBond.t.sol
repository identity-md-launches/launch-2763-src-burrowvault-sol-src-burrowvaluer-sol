// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;
import {Test} from "forge-std/Test.sol";
import {WheelBond, ICoreClock} from "../src/WheelBond.sol";
import {BurrowVaultLite} from "../src/BurrowVaultLite.sol";
import {MockSQK, MockNFT, MockStaking, MockValuer} from "./VaultLite.t.sol";

contract MockCore {
    uint64 public w = 1000; bool public dead;
    function set(uint64 v) external { w = v; }
    function kill() external { dead = true; }
    function state() external view returns (ICoreClock.State memory s) { require(!dead, "gone"); s.cumulativeWork = w; }
}

contract WheelBondTest is Test {
    MockSQK sqk; MockNFT nft; MockStaking stk; MockValuer val; BurrowVaultLite v; MockCore core; WheelBond b;
    address a = address(0xA); address c = address(0xC);

    function setUp() public {
        sqk = new MockSQK(); nft = new MockNFT(); stk = new MockStaking(sqk, nft); val = new MockValuer();
        v = new BurrowVaultLite(address(sqk), address(nft), address(stk), address(val), 1);
        core = new MockCore(); b = new WheelBond(address(core), address(v));
        for (uint160 i = 0xA; i <= 0xC; i += 2) {
            address u = address(i); sqk.mint(u, 1_000e18);
            vm.startPrank(u); sqk.approve(address(v), type(uint256).max); v.deposit(1_000e18, 0); v.approve(address(b), type(uint256).max); vm.stopPrank();
        }
    }
    function _lock(address u, uint256 s, uint256 t) internal returns (uint256 id) { vm.prank(u); id = b.lock(s, t); }

    function test_DoesNotAgeWhileWheelStops() public {
        uint256 id = _lock(a, 100e18, 1000);
        vm.warp(block.timestamp + 3650 days);
        assertEq(b.remaining(id), 1000);
        vm.prank(a); vm.expectRevert(abi.encodeWithSelector(WheelBond.NotMature.selector, 1000, 2000)); b.redeem(id);
    }
    function test_RedeemAtMaturityReturnsPrincipal() public {
        uint256 id = _lock(a, 100e18, 1000); uint256 before = v.balanceOf(a);
        core.set(2000); vm.prank(a); b.redeem(id);
        assertEq(v.balanceOf(a), before + 100e18); assertEq(b.totalWeight(), 0);
    }
    function test_PenaltyShrinksWithWork() public {
        uint256 id = _lock(a, 100e18, 1000); uint256 before = v.balanceOf(a);
        core.set(1500); vm.prank(a); b.exitEarly(id, 0);
        assertEq(v.balanceOf(a), before + 90e18);   // 10% at half way
    }
    function test_FullPenaltyAtStart() public {
        uint256 id = _lock(a, 100e18, 1000); uint256 before = v.balanceOf(a);
        vm.prank(a); b.exitEarly(id, 0);
        assertEq(v.balanceOf(a), before + 80e18);
    }
    function test_PenaltySplitPaysHoldersAndVault() public {
        uint256 x = _lock(a, 100e18, 1000); uint256 y = _lock(c, 100e18, 1000);
        uint256 assetsBefore = v.totalAssets(); uint256 supplyBefore = v.totalSupply();
        vm.prank(c); b.exitEarly(y, 0);      // penalty 20, 10 to vault, 10 to a
        assertEq(b.bonusOf(x) / 1e15, 10_000);
        assertEq(v.totalAssets(), assetsBefore, "donate keeps assets");
        assertEq(v.totalSupply(), supplyBefore - 10e18, "shares burned");
        core.set(2000); uint256 before = v.balanceOf(a); vm.prank(a); b.redeem(x);
        assertGe(v.balanceOf(a), before + 110e18 - 1e6);
    }
    function test_LongerTermEarnsMore() public {
        uint256 x = _lock(a, 100e18, 500); uint256 y = _lock(a, 100e18, 1500); uint256 z = _lock(c, 100e18, 1000);
        vm.prank(c); b.exitEarly(z, 0);
        assertEq(b.bonusOf(y) / 1e12, b.bonusOf(x) * 3 / 1e12);
    }
    function test_EntryAfterPenaltyGetsNothing() public {
        uint256 x = _lock(a, 100e18, 1000); uint256 z = _lock(c, 100e18, 1000);
        vm.prank(c); b.exitEarly(z, 0);
        uint256 y = _lock(c, 500e18, 1000);
        assertEq(b.bonusOf(y), 0); assertGt(b.bonusOf(x), 0);
    }
    function test_LastBondOutLeavesPenaltyForNextLock() public {
        uint256 x = _lock(a, 100e18, 1000);
        vm.prank(a); b.exitEarly(x, 0);
        assertEq(b.undistributed(), 10e18);
        _lock(c, 100e18, 1000); assertEq(b.undistributed(), 0);
    }
    function test_OnlyOwner() public {
        uint256 x = _lock(a, 100e18, 1000);
        vm.startPrank(c);
        vm.expectRevert(WheelBond.NotOwner.selector); b.exitEarly(x, 0);
        vm.expectRevert(WheelBond.NotOwner.selector); b.redeem(x);
        vm.expectRevert(WheelBond.NotOwner.selector); b.donateShares(1);
        vm.stopPrank();
    }
    function test_NoDoubleRedeem() public {
        uint256 x = _lock(a, 100e18, 1000); core.set(2000);
        vm.startPrank(a); b.redeem(x); vm.expectRevert(WheelBond.NotOwner.selector); b.redeem(x); vm.stopPrank();
    }
    function test_TermBounds() public {
        vm.startPrank(a);
        vm.expectRevert(WheelBond.Term.selector); b.lock(1e18, 499);
        vm.expectRevert(WheelBond.Term.selector); b.lock(1e18, 1_000_001);
        vm.stopPrank();
    }
    function test_MinOut() public {
        uint256 x = _lock(a, 100e18, 1000);
        vm.prank(a); vm.expectRevert(WheelBond.Slip.selector); b.exitEarly(x, 81e18);
    }
    function test_CoreGoneStillLetsPrincipalLeave() public {
        uint256 x = _lock(a, 100e18, 1000); core.set(1900); core.kill();
        uint256 before = v.balanceOf(a); vm.prank(a); b.exitEarly(x, 0);
        assertEq(v.balanceOf(a), before + 80e18);
    }
    function test_Solvent() public {
        uint256 x = _lock(a, 100e18, 1000); uint256 y = _lock(c, 200e18, 2000); uint256 z = _lock(c, 300e18, 800);
        core.set(1400); vm.prank(c); b.exitEarly(z, 0);
        core.set(3000);
        vm.prank(a); b.redeem(x); vm.prank(c); b.redeem(y);
        assertEq(b.totalWeight(), 0); assertLt(v.balanceOf(address(b)), 1e6);
    }
}
