// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;
import {Test} from "forge-std/Test.sol";
import {HamsterGarage} from "../src/HamsterGarage.sol";
import {WheelStock} from "../src/WheelStock.sol";
import {MockSQK} from "./VaultLite.t.sol";
import {StockCore} from "./WheelStock.t.sol";

contract HamsterGarageTest is Test {
    MockSQK t; StockCore core; WheelStock s; HamsterGarage g;
    address a = address(0xA); address c = address(0xC); address d = address(0xD);
    function setUp() public {
        vm.warp(1_000_000);
        t = new MockSQK(); core = new StockCore(); s = new WheelStock(address(core), address(t)); g = new HamsterGarage(address(s));
        for (uint160 i = 0xA; i <= 0xD; i++) {
            address u = address(i); t.mint(u, 1000e18);
            vm.startPrank(u); t.approve(address(s), type(uint256).max); s.mint(500e18, 0); s.approve(address(g), type(uint256).max); vm.stopPrank();
        }
    }
    function _park(address u, uint256 x) internal returns (uint256) { vm.prank(u); return g.park(x); }
    function test_ParkStakesIntoHmtr() public {
        uint256 id = _park(a, 200e18);
        assertEq(s.stakedOf(address(g)), 200e18); assertEq(g.valueOf(id), 200e18);
    }
    function test_MinPark() public { vm.prank(a); vm.expectRevert(HamsterGarage.Small.selector); g.park(99e18); }
    function test_NoCarBefore30Days() public {
        uint256 id = _park(a, 200e18); vm.warp(block.timestamp + 30 days - 1);
        uint256 r = g.readyAt(id); vm.expectRevert(abi.encodeWithSelector(HamsterGarage.TooSoon.selector, r)); vm.prank(a); g.claimCar(id);
    }
    function test_CarAfter30Days() public {
        uint256 id = _park(a, 200e18); vm.warp(block.timestamp + 30 days);
        vm.prank(a); uint256 car = g.claimCar(id);
        assertEq(g.ownerOf(car), a); assertEq(g.balanceOf(a), 1); assertEq(g.carParkedShares(car), 200e18);
    }
    function test_OnlyOneCarPerSpot() public {
        uint256 id = _park(a, 200e18); vm.warp(block.timestamp + 30 days);
        vm.startPrank(a); g.claimCar(id); vm.expectRevert(HamsterGarage.Claimed.selector); g.claimCar(id); vm.stopPrank();
    }
    function test_ParkEarnsCompoundedFees() public {
        uint256 id = _park(a, 200e18);
        vm.prank(c); s.redeem(500e18, 0);
        assertGt(g.valueOf(id), 200e18);
        core.set(1200); vm.prank(a); uint256 out = g.leave(id);
        assertGt(out, 200e18); assertEq(s.balanceOf(a), 300e18 + out);
    }
    function test_LeaveEarlyForfeitsCar() public {
        uint256 id = _park(a, 200e18); core.set(1200);
        vm.prank(a); g.leave(id); vm.warp(block.timestamp + 31 days);
        vm.prank(a); vm.expectRevert(HamsterGarage.NotOwner.selector); g.claimCar(id);
    }
    function test_CarSurvivesLeaving() public {
        uint256 id = _park(a, 200e18); vm.warp(block.timestamp + 30 days); core.set(1200);
        vm.startPrank(a); uint256 car = g.claimCar(id); g.leave(id); vm.stopPrank();
        assertEq(g.ownerOf(car), a);
    }
    function test_CannotParkAroundOwnership() public {
        uint256 id = _park(a, 200e18); vm.warp(block.timestamp + 30 days); core.set(1200);
        vm.startPrank(c);
        vm.expectRevert(HamsterGarage.NotOwner.selector); g.leave(id);
        vm.expectRevert(HamsterGarage.NotOwner.selector); g.claimCar(id);
        vm.stopPrank();
    }
    function test_CarTransfers() public {
        uint256 id = _park(a, 200e18); vm.warp(block.timestamp + 30 days);
        vm.startPrank(a); uint256 car = g.claimCar(id); g.approve(d, car); vm.stopPrank();
        vm.prank(c); vm.expectRevert(HamsterGarage.NotApproved.selector); g.transferFrom(a, c, car);
        vm.prank(d); g.transferFrom(a, d, car); assertEq(g.ownerOf(car), d); assertEq(g.getApproved(car), address(0));
    }
    function test_TokenUri() public {
        uint256 id = _park(a, 200e18); vm.warp(block.timestamp + 30 days); vm.prank(a); uint256 car = g.claimCar(id);
        assertGt(bytes(g.tokenURI(car)).length, 300);
    }
    function test_TwoSpotsShareFairly() public {
        uint256 x = _park(a, 100e18); uint256 y = _park(d, 300e18);
        vm.prank(c); s.redeem(500e18, 0);
        assertApproxEqRel(g.valueOf(y), g.valueOf(x) * 3, 1e12);
    }
}
