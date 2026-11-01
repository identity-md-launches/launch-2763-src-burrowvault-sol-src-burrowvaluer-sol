// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;
import {Test} from "forge-std/Test.sol";
import {WheelStock, ICoreClock} from "../src/WheelStock.sol";
import {MockSQK} from "./VaultLite.t.sol";

contract StockCore {
    uint64 public w = 1000; bool public dead;
    function set(uint64 v) external { w = v; }
    function kill() external { dead = true; }
    function state() external view returns (ICoreClock.State memory s) { require(!dead, "gone"); s.cumulativeWork = w; }
}
contract WheelStockTest is Test {
    MockSQK t; StockCore core; WheelStock s;
    address a = address(0xA); address c = address(0xC); address d = address(0xD);
    function setUp() public {
        vm.warp(1_000_000);
        t = new MockSQK(); core = new StockCore(); s = new WheelStock(address(core), address(t));
        for (uint160 i = 0xA; i <= 0xD; i++) { address u = address(i); t.mint(u, 1000e18); vm.prank(u); t.approve(address(s), type(uint256).max); }
    }
    function _mint(address u, uint256 x) internal returns (uint256) { vm.prank(u); return s.mint(x, 0); }
    function test_MintOneToOneAtStart() public { assertEq(_mint(a, 100e18), 100e18); assertEq(s.sharePrice(), 1e18); }
    function test_SharesTradeFreely() public {
        _mint(a, 100e18); vm.prank(a); s.transfer(c, 40e18);
        assertEq(s.balanceOf(c), 40e18); assertEq(s.balanceOf(a), 60e18);
        vm.prank(c); s.approve(d, 10e18); vm.prank(d); s.transferFrom(c, d, 10e18); assertEq(s.balanceOf(d), 10e18);
    }
    function test_BuyerRedeemsAfterTrade() public {
        _mint(a, 100e18); _mint(c, 100e18); vm.prank(a); s.transfer(d, 50e18);
        uint256 before = t.balanceOf(d); vm.prank(d); s.redeem(50e18, 0);
        assertEq(t.balanceOf(d) - before, 47.5e18);
    }
    function test_ExitFeeIsDividendForHolders() public {
        _mint(a, 100e18); _mint(c, 100e18);
        vm.prank(c); s.redeem(100e18, 0);             // closed market: 5 stays
        assertEq(s.nav(), 103.75e18); assertEq(s.pouch(), 1.25e18);
        uint256 before = t.balanceOf(a); vm.prank(a); s.redeem(100e18, 0);
        assertEq(t.balanceOf(a) - before, 103.75e18);  // last holder pays no fee
        assertEq(s.nav(), 0); assertEq(s.totalSupply(), 0);
    }
    function test_MarketHoursFollowWheel() public {
        assertFalse(s.marketOpen()); assertEq(s.exitFeeBps(), 500);
        core.set(1001); assertTrue(s.marketOpen()); assertEq(s.exitFeeBps(), 100);
        s.poke(); vm.warp(block.timestamp + 59 minutes); assertTrue(s.marketOpen());
        vm.warp(block.timestamp + 2 minutes); assertFalse(s.marketOpen());
    }
    function test_OpenMarketChargesOnePercent() public {
        _mint(a, 100e18); _mint(c, 100e18); core.set(1001);
        uint256 before = t.balanceOf(c); vm.prank(c); s.redeem(100e18, 0);
        assertEq(t.balanceOf(c) - before, 99e18);
    }
    function test_LateMinterGetsNoOldDividend() public {
        _mint(a, 100e18); _mint(c, 100e18); vm.prank(c); s.redeem(100e18, 0);
        _mint(d, 105e18);
        assertApproxEqAbs(s.balanceOf(d), 101.2e18, 2e17);
    }
    function test_DirectTransferDoesNotInflate() public {
        _mint(a, 1); vm.prank(c); t.transfer(address(s), 500e18);
        assertEq(s.nav(), 1); assertEq(_mint(d, 100e18), 100e18);
    }
    function test_DeadCoreStillRedeems() public {
        _mint(a, 100e18); _mint(c, 100e18); core.kill();
        uint256 before = t.balanceOf(c); vm.prank(c); s.redeem(100e18, 0);
        assertEq(t.balanceOf(c) - before, 95e18);
    }
    function test_Slippage() public {
        _mint(a, 100e18); _mint(c, 100e18);
        vm.prank(c); vm.expectRevert(WheelStock.Slip.selector); s.redeem(100e18, 96e18);
        vm.prank(d); vm.expectRevert(WheelStock.Slip.selector); s.mint(1e18, 2e18);
    }
    function test_CannotRedeemMoreThanOwned() public {
        _mint(a, 100e18); vm.prank(c); vm.expectRevert(); s.redeem(1e18, 0);
    }
    function test_Solvent() public {
        _mint(a, 100e18); _mint(c, 37e18); vm.prank(c); s.redeem(20e18, 0); _mint(d, 11e18);
        vm.prank(a); s.redeem(100e18, 0); uint256 bd = s.balanceOf(d); vm.prank(d); s.redeem(bd, 0); uint256 bc = s.balanceOf(c); vm.prank(c); s.redeem(bc, 0);
        assertEq(s.nav(), 0); assertEq(t.balanceOf(address(s)), s.pouch());
    }
    function _stake(address u, uint256 x) internal { vm.prank(u); s.stake(x); }
    function test_StakeCompoundsFees() public {
        _mint(a, 100e18); _mint(c, 100e18); _stake(a, 100e18);
        vm.prank(c); s.redeem(100e18, 0);            // fee 5: 2.5 to stakers as shares, 2.5 stays in price
        assertGt(s.stakedOf(a), 102e18);
        core.set(1200); uint256 u = s.unitsOf(a); vm.prank(a); s.unstake(u);
        assertGt(s.balanceOf(a), 102e18); assertEq(s.stakedShares(), 0);
    }
    function test_StakerBeatsPlainHolder() public {
        _mint(a, 100e18); _mint(d, 100e18); _mint(c, 100e18); _stake(a, 100e18);
        vm.prank(c); s.redeem(100e18, 0);
        assertGt(s.stakedOf(a) * s.sharePrice(), s.balanceOf(d) * s.sharePrice());
    }
    function test_CannotSnipeFee() public {
        _mint(a, 100e18); _mint(c, 100e18); _stake(a, 50e18);
        vm.prank(a); vm.expectRevert(abi.encodeWithSelector(WheelStock.WheelTooEarly.selector, 1000, 1200)); s.unstake(1);
    }
    function test_LateStakerGetsNoOldFees() public {
        _mint(a, 100e18); _mint(c, 100e18); _mint(d, 100e18); _stake(a, 100e18);
        vm.prank(c); s.redeem(100e18, 0);
        _stake(d, 100e18);
        assertApproxEqAbs(s.stakedOf(d), 100e18, 1e6);
    }
    function test_DeadCoreLetsStakeLeave() public {
        _mint(a, 100e18); _stake(a, 100e18); core.kill();
        vm.prank(a); s.unstake(100e18); assertEq(s.balanceOf(a), 100e18);
    }
    function test_SolventWithStake() public {
        _mint(a, 100e18); _mint(c, 100e18); _mint(d, 100e18); _stake(a, 100e18); _stake(d, 50e18);
        vm.prank(c); s.redeem(60e18, 0); vm.prank(c); s.redeem(40e18, 0);
        core.set(1500);
        uint256 ua = s.unitsOf(a); vm.prank(a); s.unstake(ua); uint256 ud = s.unitsOf(d); vm.prank(d); s.unstake(ud);
        uint256 x = s.balanceOf(a); vm.prank(a); s.redeem(x, 0);
        x = s.balanceOf(d); vm.prank(d); s.redeem(x, 0);
        assertEq(s.nav(), 0); assertEq(s.totalSupply(), 0); assertEq(s.stakedShares(), 0); assertEq(t.balanceOf(address(s)), s.pouch());
    }
    function test_PouchHoardsUntilZoomies() public {
        _mint(a, 100e18); _mint(c, 100e18);
        vm.prank(c); s.redeem(100e18, 0);
        assertEq(s.pouch(), 1.25e18);
        core.set(1499); s.poke(); assertEq(s.pouch(), 1.25e18);      // a jog keeps the cheeks full
        uint256 navBefore = s.nav(); uint256 p = s.sharePrice();
        core.set(1500); s.poke();
        assertEq(s.pouch(), 0); assertEq(s.nav(), navBefore + 1.25e18); assertGt(s.sharePrice(), p);
    }
    function test_DeadCoreEmptiesPouch() public {
        _mint(a, 100e18); _mint(c, 100e18); vm.prank(c); s.redeem(100e18, 0);
        core.kill(); s.poke(); assertEq(s.pouch(), 0);
    }
    function test_FeeSplitAddsUp() public {
        _mint(a, 100e18); _mint(c, 100e18); _stake(a, 100e18);
        uint256 navB = s.nav(); vm.prank(c); s.redeem(100e18, 0);
        assertEq(navB - s.nav() - s.pouch(), 95e18);
    }
}
