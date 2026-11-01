// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;
import {Test} from "forge-std/Test.sol";
import {WheelBond} from "../src/WheelBond.sol";
contract ForkWheelBondTest is Test {
    address constant CORE = 0x980B4424c007CAf7a1f3670B48c8EaEf7EbC3d44;
    address constant VAULT = 0xB63AbAb9019fa0Db4A3Ab1824C5E5Fa7171f1472;
    address constant ME = 0xbC8744370bCb6D5AbF5dE8B4086ecfBB4C5629C3;
    function testFork_ReadsRealWheelAndCycles() public {
        string memory url = vm.envOr("SEPOLIA_RPC_URL", string(""));
        if (bytes(url).length == 0) { vm.skip(true); return; }
        vm.createSelectFork(url);
        WheelBond b = new WheelBond(CORE, VAULT);
        uint256 w = b.work(); assertGt(w, 65_000);
        vm.startPrank(ME);
        (bool d0,) = address(0x5501E1Fa81Be1c3F49225fa7668DA0245d07Db60).call(abi.encodeWithSignature("approve(address,uint256)", VAULT, type(uint256).max)); assertTrue(d0);
        (bool d1,) = VAULT.call(abi.encodeWithSignature("deposit(uint256,uint256)", 2000e18, 0)); assertTrue(d1);
        (bool ok,) = VAULT.call(abi.encodeWithSignature("approve(address,uint256)", address(b), type(uint256).max)); assertTrue(ok);
        uint256 id = b.lock(1000e18, 1000);
        (,, uint64 m,,) = b.bonds(id); assertEq(m, w + 1000);
        b.exitEarly(id, 0);
        vm.stopPrank();
    }
}
