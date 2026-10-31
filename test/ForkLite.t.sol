// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;
import {Test} from "forge-std/Test.sol";
import {BurrowVaultLite} from "../src/BurrowVaultLite.sol";

interface IValuerLive { function creditLine(uint256[] calldata) external view returns (uint256); function ltvBps() external view returns (uint256); }

contract ForkLiteTest is Test {
    address constant SQK = 0x5501E1Fa81Be1c3F49225fa7668DA0245d07Db60;
    address constant NFT = 0xCB98349c134aB983dA5BfD80527dfe2552bDB70F;
    address constant STAKING = 0x4b67b739dFd832f4EAC67a7Aa3bc244fB74cea4F;
    address constant VALUER = 0x3DAe531514bA050Ec9a03BBC268528A84da2BcFA;   // đã deploy
    uint256 constant RATE = uint256(0.08e18) / 365 days;

    function _fork() internal {
        string memory url = vm.envOr("SEPOLIA_RPC_URL", string(""));
        if (bytes(url).length == 0) { vm.skip(true); return; }
        vm.createSelectFork(url);
        assertEq(block.chainid, 11155111);
    }

    function testFork_DeploysAgainstRealSqueekchain() public {
        _fork();
        BurrowVaultLite v = new BurrowVaultLite(SQK, NFT, STAKING, VALUER, RATE);
        assertEq(address(v.sqk()), SQK);
        assertEq(address(v.valuer()), VALUER);
        assertEq(v.totalSupply(), 0);
        assertEq(v.borrowIndex(), 1e18);
        uint256[] memory ids = new uint256[](1); ids[0] = 8936;
        uint256 line = IValuerLive(VALUER).creditLine(ids);
        assertGt(line, 0, "valuer on chain answers");
        emit log_named_uint("credit line for #8936", line);
        emit log_named_uint("ltvBps", IValuerLive(VALUER).ltvBps());
    }

    function testFork_LenderCanSeedAndWithdraw() public {
        _fork();
        BurrowVaultLite v = new BurrowVaultLite(SQK, NFT, STAKING, VALUER, RATE);
        deal(SQK, address(this), 10_000e18);
        (bool ok,) = SQK.call(abi.encodeWithSignature("approve(address,uint256)", address(v), type(uint256).max));
        assertTrue(ok);
        uint256 shares = v.deposit(1_000e18, 0);
        assertEq(shares, 1_000e18 - 1000);
        uint256 out = v.withdraw(100e18, 0);
        assertApproxEqAbs(out, 100e18, 1e12, "round trip");
    }
}

interface IStakingLive { function accountPower(address) external view returns (uint256); function claimable(address) external view returns (uint256); }
interface INFTLive { function ownerOf(uint256) external view returns (address); function setApprovalForAll(address, bool) external; function transferFrom(address, address, uint256) external; function level(uint256) external view returns (uint8); }

/// Real Squeekchain staking on a Sepolia fork: escrow → stake → borrow → repay → close.
contract ForkLiteIntegration is ForkLiteTest {
    uint256 constant ID = 8936;   // currently in staking custody; pranked out to a test borrower
    address borrower = address(0xB0B);

    function testFork_OpenBorrowRepayCloseAgainstRealStaking() public {
        _fork();
        BurrowVaultLite v = new BurrowVaultLite(SQK, NFT, STAKING, VALUER, RATE);
        INFTLive nft = INFTLive(NFT);
        address holder = nft.ownerOf(ID);
        vm.prank(holder); nft.transferFrom(holder, borrower, ID);
        assertEq(nft.ownerOf(ID), borrower, "pranked out");
        emit log_named_uint("level", nft.level(ID));
        // lender
        deal(SQK, address(this), 10_000e18);
        (bool ok,) = SQK.call(abi.encodeWithSignature("approve(address,uint256)", address(v), type(uint256).max)); assertTrue(ok);
        v.deposit(5_000e18, 0);
        // borrower escrows
        uint256[] memory ids = new uint256[](1); ids[0] = ID;
        vm.startPrank(borrower);
        nft.setApprovalForAll(address(v), true);
        v.openPosition(ids);
        vm.stopPrank();
        assertEq(nft.ownerOf(ID), STAKING, "restaked by vault");
        uint256 pw = IStakingLive(STAKING).accountPower(address(v));
        emit log_named_uint("staking.accountPower(vault)", pw);
        assertGt(pw, 0, "vault holds staking power");
        uint256 line = v.creditLineOf(borrower);
        emit log_named_uint("creditLine", line);
        assertGt(line, 0);
        vm.prank(borrower); v.borrow(line / 2);
        assertEq(v.debtOf(borrower), line / 2);
        // sweep does not revert even with nothing claimable yet
        uint256 swept = v.sweepRewards();
        emit log_named_uint("swept", swept);
        vm.warp(block.timestamp + 30 days);
        uint256 debt = v.debtOf(borrower);
        assertGt(debt, line / 2, "interest accrued");
        deal(SQK, borrower, debt);
        vm.startPrank(borrower);
        (ok,) = SQK.call(abi.encodeWithSignature("approve(address,uint256)", address(v), type(uint256).max)); assertTrue(ok);
        v.repay(type(uint256).max);
        v.closePosition();
        vm.stopPrank();
        assertEq(nft.ownerOf(ID), borrower, "NFT returned from real staking");
        assertEq(v.debtOf(borrower), 0);
        // lender exits with interest
        uint256 out = v.withdraw(v.balanceOf(address(this)), 0);
        assertGt(out, 5_000e18, "lender earned interest");
    }

    function testFork_LiquidateAgainstRealStaking() public {
        _fork();
        BurrowVaultLite v = new BurrowVaultLite(SQK, NFT, STAKING, VALUER, RATE);
        INFTLive nft = INFTLive(NFT);
        address holder = nft.ownerOf(ID);
        vm.prank(holder); nft.transferFrom(holder, borrower, ID);
        deal(SQK, address(this), 100_000e18);
        (bool ok,) = SQK.call(abi.encodeWithSignature("approve(address,uint256)", address(v), type(uint256).max)); assertTrue(ok);
        v.deposit(50_000e18, 0);
        uint256[] memory ids = new uint256[](1); ids[0] = ID;
        vm.startPrank(borrower); nft.setApprovalForAll(address(v), true); v.openPosition(ids);
        uint256 line = v.creditLineOf(borrower); v.borrow(line); vm.stopPrank();
        vm.warp(block.timestamp + 1500 days);       // 8% APR for ~4 years pushes debt past 75% of value
        assertGt(v.debtOf(borrower), line);
        uint256 before = IERC20B(SQK).balanceOf(address(this));
        v.liquidate(borrower);
        uint256 paid = before - IERC20B(SQK).balanceOf(address(this));
        emit log_named_uint("liquidator paid", paid);
        assertEq(nft.ownerOf(ID), address(this), "liquidator got the NFT back from real staking");
        assertGe(paid, line, "paid at least the debt");
    }
}
interface IERC20B { function balanceOf(address) external view returns (uint256); }
