// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;
import {BurrowValuer} from "../src/BurrowValuer.sol";
import {BurrowTestBase, BurrowTestNFT} from "./BurrowVault.t.sol";

contract BurrowValuerTest is BurrowTestBase {
    BurrowTestNFT internal nft;
    BurrowValuer internal valuer;
    address internal stranger;
    event PriceProposed(uint256 oldPrice, uint256 newPrice, uint256 readyAt);
    event PriceExecuted(uint256 oldPrice, uint256 newPrice);
    event PriceProposalCancelled(uint256 proposedPrice);

    function setUp() public {
        vm.warp(10 days);
        stranger = addr("stranger");
        nft = new BurrowTestNFT();
        valuer = new BurrowValuer(address(this), address(nft), powers(), 1e18, 0.5e18, 2e18, 6000);
        for (uint256 i = 1; i <= 32; i++) {
            nft.mint(stranger, i, uint8((i - 1) % 6 + 1));
        }
    }

    function test_ValuesSummedPowerAtPublishedLevels() public view {
        uint256[] memory a = new uint256[](6);
        for (uint256 i; i < 6; i++) {
            a[i] = i + 1;
        }
        assertEq(valuer.totalPower(a), 120000, "six levels power");
        assertEq(valuer.collateralValue(a), 120000e18, "SQK per integer power");
        assertEq(valuer.creditLine(a), 72000e18, "60 percent LTV");
        assertEq(valuer.creditLine(new uint256[](0)), 0, "empty collateral has no credit");
        assertEq(valuer.powerForLevel(7), 127000, "upward power policy");
    }

    /// forge-config: default.fuzz.runs = 1000
    function testFuzz_CreditLineRoundsOnlyAfterAggregating(uint128 price, uint16 ltv, uint8 count) public {
        uint256 p = bound(price, 1, 1e27);
        uint256 ratio = bound(ltv, 0, 6000);
        uint256 n = bound(count, 1, 32);
        BurrowValuer v = new BurrowValuer(address(this), address(nft), powers(), p, p, p, ratio);
        uint256[] memory a = new uint256[](n);
        uint256 power;
        for (uint256 i; i < n; i++) {
            a[i] = i + 1;
            power += 1000 * ((uint256(1) << ((i % 6) + 1)) - 1);
        }
        assertEq(v.creditLine(a), power * p * ratio / 10000, "single rounding after summing");
    }

    function test_FullPrecisionCreditLineDoesNotOverflow() public {
        uint256[] memory table = new uint256[](1);
        table[0] = 1000;
        uint256 price = type(uint256).max / 32000;
        BurrowValuer v = new BurrowValuer(address(this), address(nft), table, price, 1, price, 6000);
        uint256[] memory a = new uint256[](32);
        for (uint256 i; i < 32; i++) {
            a[i] = i + 1;
            nft.setLevel(i + 1, 1);
        }
        uint256 value = 32000 * price;
        assertEq(v.creditLine(a), (value / 5) * 3 + (value % 5) * 3 / 5, "overflow-safe 60 percent");
    }

    function test_TwoDayDelayExecutionEventsAndReplayProtection() public {
        uint256 ready = block.timestamp + 2 days;
        vm.expectEmit(false, false, false, true, address(valuer));
        emit PriceProposed(1e18, 1.2e18, ready);
        valuer.proposePricePerPower(1.2e18);
        assertEq(valuer.pricePerPower(), 1e18, "proposal must not change valuation");
        assertEq(valuer.lastPriceChange(), 0, "proposal must not trigger freeze");
        vm.warp(ready - 1);
        vm.expectRevert(abi.encodeWithSelector(BurrowValuer.PriceChangeNotReady.selector, ready));
        valuer.executePricePerPower();
        vm.warp(ready);
        vm.expectEmit(false, false, false, true, address(valuer));
        emit PriceExecuted(1e18, 1.2e18);
        valuer.executePricePerPower();
        assertEq(valuer.pricePerPower(), 1.2e18, "inclusive 20 percent increase");
        assertEq(valuer.lastPriceChange(), ready, "execution timestamp");
        assertEq(valuer.pendingPricePerPower(), 0, "proposal consumed");
        assertEq(valuer.priceChangeReadyAt(), 0, "timer consumed");
        vm.expectRevert(BurrowValuer.NoPendingPriceChange.selector);
        valuer.executePricePerPower();
    }

    function test_ExactTwentyPercentDecreaseIsAllowed() public {
        valuer.proposePricePerPower(0.8e18);
        vm.warp(block.timestamp + 2 days);
        valuer.executePricePerPower();
        assertEq(valuer.pricePerPower(), 0.8e18, "inclusive decrease");
    }

    function test_OneWeiOversizedMovesUnchangedAndHardBand() public {
        vm.expectRevert(abi.encodeWithSelector(BurrowValuer.PriceChangeTooLarge.selector, 1e18, 1.2e18 + 1));
        valuer.proposePricePerPower(1.2e18 + 1);
        vm.expectRevert(abi.encodeWithSelector(BurrowValuer.PriceChangeTooLarge.selector, 1e18, 0.8e18 - 1));
        valuer.proposePricePerPower(0.8e18 - 1);
        vm.expectRevert(BurrowValuer.PriceUnchanged.selector);
        valuer.proposePricePerPower(1e18);
        vm.expectRevert(abi.encodeWithSelector(BurrowValuer.PriceOutsideBand.selector, 0.5e18 - 1));
        valuer.proposePricePerPower(0.5e18 - 1);
        vm.expectRevert(abi.encodeWithSelector(BurrowValuer.PriceOutsideBand.selector, 2e18 + 1));
        valuer.proposePricePerPower(2e18 + 1);
        vm.expectRevert(abi.encodeWithSelector(BurrowValuer.PriceOutsideBand.selector, 0));
        valuer.proposePricePerPower(0);
        assertEq(valuer.pendingPricePerPower(), 0, "rejected proposal changed state");
    }

    function test_ReplacingProposalRestartsEntireDelayAndCancelDoesNotFreeze() public {
        valuer.proposePricePerPower(1.1e18);
        uint256 firstReady = valuer.priceChangeReadyAt();
        vm.warp(block.timestamp + 1 days);
        valuer.proposePricePerPower(0.9e18);
        uint256 secondReady = valuer.priceChangeReadyAt();
        assertEq(secondReady, firstReady + 1 days, "replacement delay");
        vm.warp(firstReady);
        vm.expectRevert(abi.encodeWithSelector(BurrowValuer.PriceChangeNotReady.selector, secondReady));
        valuer.executePricePerPower();
        vm.expectEmit(false, false, false, true, address(valuer));
        emit PriceProposalCancelled(0.9e18);
        valuer.cancelPriceProposal();
        assertEq(valuer.lastPriceChange(), 0, "cancellation must not freeze");
        assertEq(valuer.pendingPricePerPower(), 0, "cancel clears price");
        vm.expectRevert(BurrowValuer.NoPendingPriceChange.selector);
        valuer.cancelPriceProposal();
        vm.warp(secondReady);
        vm.expectRevert(BurrowValuer.NoPendingPriceChange.selector);
        valuer.executePricePerPower();
    }

    function test_UnauthorizedPriceChangesAndOwnershipHandoff() public {
        bytes memory reason = abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", stranger);
        vm.expectRevert(reason);
        vm.prank(stranger);
        valuer.proposePricePerPower(1.1e18);
        valuer.proposePricePerPower(1.1e18);
        vm.warp(block.timestamp + 2 days);
        vm.expectRevert(reason);
        vm.prank(stranger);
        valuer.executePricePerPower();
        vm.expectRevert(reason);
        vm.prank(stranger);
        valuer.cancelPriceProposal();
        valuer.transferOwnership(stranger);
        vm.expectRevert(reason);
        vm.prank(stranger);
        valuer.executePricePerPower();
        vm.prank(stranger);
        valuer.acceptOwnership();
        vm.prank(stranger);
        valuer.executePricePerPower();
        assertEq(valuer.pricePerPower(), 1.1e18, "new owner executes existing timelock");
    }

    function test_TokenArrayAndLevelFailurePaths() public {
        vm.expectRevert(abi.encodeWithSelector(BurrowValuer.TooManyTokenIds.selector, 33));
        valuer.creditLine(new uint256[](33));
        uint256[] memory a = new uint256[](2);
        a[0] = 2;
        a[1] = 2;
        vm.expectRevert(abi.encodeWithSelector(BurrowValuer.TokenIdsNotStrictlyAscending.selector, 2, 2));
        valuer.creditLine(a);
        a[1] = 1;
        vm.expectRevert(abi.encodeWithSelector(BurrowValuer.TokenIdsNotStrictlyAscending.selector, 2, 1));
        valuer.totalPower(a);
        vm.expectRevert(abi.encodeWithSelector(BurrowValuer.InvalidToken.selector, 999));
        valuer.powerOf(999);
        vm.expectRevert(abi.encodeWithSelector(BurrowValuer.UnsupportedLevel.selector, 0));
        valuer.powerForLevel(0);
        vm.expectRevert(abi.encodeWithSelector(BurrowValuer.UnsupportedLevel.selector, 17));
        valuer.powerForLevel(17);
        nft.setLevel(1, 0);
        vm.expectRevert(abi.encodeWithSelector(BurrowValuer.UnsupportedLevel.selector, 0));
        valuer.powerOf(1);
        vm.mockCallRevert(address(nft), abi.encodeWithSelector(bytes4(keccak256("level(uint256)")), 2), hex"01020304");
        vm.expectRevert(abi.encodeWithSelector(BurrowValuer.LevelReadFailed.selector, 2));
        valuer.powerOf(2);
        vm.mockCall(address(nft), abi.encodeWithSelector(BurrowTestNFT.ownerOf.selector, 3), abi.encode(address(0)));
        vm.expectRevert(abi.encodeWithSelector(BurrowValuer.InvalidToken.selector, 3));
        valuer.powerOf(3);
    }

    function test_ConstructorRejectsInvalidConfiguration() public {
        vm.expectRevert(abi.encodeWithSelector(BurrowValuer.InvalidCollection.selector, stranger));
        new BurrowValuer(address(this), stranger, powers(), 1, 1, 2, 6000);
        vm.expectRevert(abi.encodeWithSelector(BurrowValuer.InvalidLtvBps.selector, 6001));
        new BurrowValuer(address(this), address(nft), powers(), 1, 1, 2, 6001);
        vm.expectRevert(abi.encodeWithSelector(BurrowValuer.InvalidPriceBand.selector, 0, 2));
        new BurrowValuer(address(this), address(nft), powers(), 1, 0, 2, 6000);
        vm.expectRevert(abi.encodeWithSelector(BurrowValuer.InvalidPriceBand.selector, 3, 2));
        new BurrowValuer(address(this), address(nft), powers(), 3, 3, 2, 6000);
        vm.expectRevert(abi.encodeWithSelector(BurrowValuer.PriceOutsideBand.selector, 3));
        new BurrowValuer(address(this), address(nft), powers(), 3, 1, 2, 6000);
        vm.expectRevert(abi.encodeWithSelector(BurrowValuer.InvalidPowerTableLength.selector, 0));
        new BurrowValuer(address(this), address(nft), new uint256[](0), 1, 1, 2, 6000);
        vm.expectRevert(abi.encodeWithSelector(BurrowValuer.InvalidPowerTableLength.selector, 256));
        new BurrowValuer(address(this), address(nft), new uint256[](256), 1, 1, 2, 6000);
        uint256[] memory table = powers();
        table[1] = 3001;
        vm.expectRevert(abi.encodeWithSelector(BurrowValuer.InvalidPower.selector, 2, 3001, 3000));
        new BurrowValuer(address(this), address(nft), table, 1, 1, 2, 6000);
        table = new uint256[](1);
        table[0] = 1000;
        vm.expectRevert(abi.encodeWithSelector(BurrowValuer.InvalidPriceBand.selector, 1, type(uint256).max));
        new BurrowValuer(address(this), address(nft), table, 1, 1, type(uint256).max, 6000);
        table = new uint256[](255);
        uint256 next = 1000;
        for (uint256 i; i < 255; i++) {
            table[i] = next;
            if (next > type(uint256).max / 32) break;
            next = next * 2 + 1000;
        }
        vm.expectRevert(BurrowValuer.PowerTableTooLarge.selector);
        new BurrowValuer(address(this), address(nft), table, 1, 1, 1, 6000);
    }

    function test_SmallIntegerPricesRoundStepCapDown() public {
        BurrowValuer small = new BurrowValuer(address(this), address(nft), powers(), 9, 1, 100, 6000);
        vm.expectRevert(abi.encodeWithSelector(BurrowValuer.PriceChangeTooLarge.selector, 9, 11));
        small.proposePricePerPower(11);
        small.proposePricePerPower(10);
        vm.warp(block.timestamp + 2 days);
        small.executePricePerPower();
        assertEq(small.pricePerPower(), 10, "floored step boundary");
    }
}
