// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;
import {Test} from "forge-std/Test.sol";
import {WheelStock} from "../src/WheelStock.sol";
contract ForkWheelStockTest is Test {
    function testFork_RealCoreAndBsqk() public {
        string memory url = vm.envOr("SEPOLIA_RPC_URL", string(""));
        if (bytes(url).length == 0) { vm.skip(true); return; }
        vm.createSelectFork(url);
        address V = 0xB63AbAb9019fa0Db4A3Ab1824C5E5Fa7171f1472; address ME = 0xbC8744370bCb6D5AbF5dE8B4086ecfBB4C5629C3;
        WheelStock s = new WheelStock(0x980B4424c007CAf7a1f3670B48c8EaEf7EbC3d44, V);
        assertGt(s.lastWork(), 65_000);
        vm.startPrank(ME);
        (bool d0,) = address(0x5501E1Fa81Be1c3F49225fa7668DA0245d07Db60).call(abi.encodeWithSignature("approve(address,uint256)", V, type(uint256).max)); assertTrue(d0);
        (bool d1,) = V.call(abi.encodeWithSignature("deposit(uint256,uint256)", 2000e18, 0)); assertTrue(d1);
        (bool ok,) = V.call(abi.encodeWithSignature("approve(address,uint256)", address(s), type(uint256).max)); assertTrue(ok);
        uint256 sh = s.mint(1000e18, 0); assertEq(sh, 1000e18);
        s.redeem(sh, 0);
        vm.stopPrank();
    }
}
