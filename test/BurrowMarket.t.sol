// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;
import {BurrowMarket} from "../src/BurrowMarket.sol";
import {BurrowVault, IERC20, IERC721, ERC721Holder} from "../src/BurrowVault.sol";
import {
    BurrowVaultFixture,
    BurrowTestBase,
    BurrowTestNFT,
    BurrowTestToken,
    BurrowSepoliaForkFixture
} from "./BurrowVault.t.sol";

contract BurrowTestFeeSink {
    BurrowTestToken public immutable token;
    bool public fail;
    bool public ignore;
    uint256 public donated;
    error DonationRejected();

    constructor(BurrowTestToken t) {
        token = t;
    }

    function setFail(bool b) external {
        fail = b;
    }

    function setIgnore(bool b) external {
        ignore = b;
    }

    function donate(uint256 amount) external {
        if (fail) revert DonationRejected();
        if (ignore) return;
        token.transferFrom(msg.sender, address(this), amount);
        donated += amount;
    }
}

contract BurrowMarketReentrantBuyer is ERC721Holder {
    BurrowMarket public immutable market;
    BurrowTestToken public immutable token;
    bool public callbackSucceeded;
    bytes public callbackResult;

    constructor(BurrowMarket m, BurrowTestToken t) {
        market = m;
        token = t;
    }

    function buy(uint256 id) external {
        token.approve(address(market), type(uint256).max);
        market.buy(id);
    }

    function onERC721Received(address, address, uint256 id, bytes memory) public override returns (bytes4) {
        (callbackSucceeded, callbackResult) = address(market).call(abi.encodeWithSignature("buy(uint256)", id));
        return this.onERC721Received.selector;
    }
}

contract BurrowMarketRejectingBuyer {
    function buy(BurrowMarket market, BurrowTestToken token, uint256 id) external {
        token.approve(address(market), type(uint256).max);
        market.buy(id);
    }
}

contract BurrowMarketTest is BurrowVaultFixture {
    BurrowMarket internal market;
    event Listed(uint256 indexed tokenId, address indexed seller, uint256 price, uint256 feeBps);
    event Sold(uint256 indexed tokenId, address indexed seller, address indexed buyer, uint256 price, uint256 fee);

    function setUp() public {
        _setup(0);
        _seed(10000e18);
        market = new BurrowMarket(address(token), address(nft), address(vault), address(this), 250, 1 days);
        vm.prank(alice);
        nft.setApprovalForAll(address(market), true);
        vm.prank(bob);
        token.approve(address(market), type(uint256).max);
        nft.mint(alice, 1, 1);
        nft.mint(alice, 2, 2);
    }

    function _list(uint256 id, uint256 price) internal {
        vm.prank(alice);
        market.list(id, price);
    }

    function test_FixedSalePaysSellerAndRaisesVaultSharePriceAtomically() public {
        uint256 backing = vault.totalAssets();
        uint256 supply = vault.totalSupply();
        uint256 seller = token.balanceOf(alice);
        uint256 buyer = token.balanceOf(bob);
        vm.expectEmit(true, true, false, true, address(market));
        emit Listed(1, alice, 100e18, 250);
        _list(1, 100e18);
        assertEq(nft.ownerOf(1), address(market), "listing escrow");
        vm.expectEmit(true, true, true, true, address(market));
        emit Sold(1, alice, bob, 100e18, 2.5e18);
        vm.prank(bob);
        market.buy(1);
        assertEq(token.balanceOf(alice), seller + 97.5e18, "seller net same transaction");
        assertEq(token.balanceOf(bob), buyer - 100e18, "buyer gross");
        assertEq(vault.totalAssets(), backing + 2.5e18, "fee reaches actual vault");
        assertEq(vault.totalSupply(), supply, "fee mints no shares");
        assertTrue(vault.convertToAssets(1e18) > 1e18, "all lenders benefit");
        assertEq(nft.ownerOf(1), bob, "buyer custody");
        assertEq(token.balanceOf(address(market)), 0, "no SQK stranded");
        assertEq(token.allowance(address(market), address(vault)), 0, "fee allowance revoked");
        (address sellerAfter,,,,,) = market.listings(1);
        assertEq(sellerAfter, address(0), "listing consumed");
        vm.expectRevert(abi.encodeWithSelector(BurrowMarket.NotListed.selector, 1));
        vm.prank(bob);
        market.buy(1);
    }

    function test_CancelOnlyBySellerRestoresNFTAndCanRelist() public {
        _list(1, 100e18);
        vm.expectRevert(abi.encodeWithSelector(BurrowMarket.NotSeller.selector, 1));
        vm.prank(bob);
        market.cancel(1);
        vm.expectRevert(abi.encodeWithSelector(BurrowMarket.NotSeller.selector, 1));
        market.cancel(1);
        vm.prank(alice);
        market.cancel(1);
        assertEq(nft.ownerOf(1), alice, "seller custody restored");
        vm.expectRevert(abi.encodeWithSelector(BurrowMarket.NotListed.selector, 1));
        vm.prank(alice);
        market.cancel(1);
        _list(1, 200e18);
        assertEq(market.currentPrice(1), 200e18, "relisted price");
    }

    function test_FeeChangesCannotRewriteExistingSellerTerms() public {
        _list(1, 100e18);
        market.setFeeBps(500);
        _list(2, 100e18);
        uint256 backing = vault.totalAssets();
        vm.prank(bob);
        market.buy(1);
        assertEq(vault.totalAssets(), backing + 2.5e18, "old fee preserved");
        vm.prank(bob);
        market.buy(2);
        assertEq(vault.totalAssets(), backing + 7.5e18, "new listing fee applied");
    }

    function test_DutchAuctionStartMidpointLastSecondAndFloor() public {
        vm.prank(alice);
        market.startAuction(1, 200e18, 100e18);
        uint256 start = block.timestamp;
        assertEq(market.currentPrice(1), 200e18, "premium at start");
        vm.warp(start + 12 hours);
        assertEq(market.currentPrice(1), 150e18, "linear midpoint");
        vm.warp(start + 1 days - 1);
        assertTrue(market.currentPrice(1) > 100e18, "above floor before expiry");
        vm.warp(start + 1 days);
        assertEq(market.currentPrice(1), 100e18, "floor at expiry");
        vm.warp(start + 30 days);
        assertEq(market.currentPrice(1), 100e18, "floor persists");
        vm.prank(bob);
        market.buy(1, 100e18);
        assertEq(nft.ownerOf(1), bob, "expired auction remains buyable");
    }

    /// forge-config: default.fuzz.runs = 1000
    function testFuzz_DutchPriceMonotoneAndSettlementConservesSQK(
        uint128 premium,
        uint128 floorRaw,
        uint32 t,
        uint16 feeRaw
    ) public {
        uint256 floor = bound(floorRaw, 1, 1e25);
        uint256 start = floor + bound(premium, 1, 1e25);
        uint256 fee = bound(feeRaw, 0, 500);
        market.setFeeBps(fee);
        vm.prank(alice);
        market.startAuction(1, start, floor);
        uint256 elapsed = bound(t, 0, 2 days);
        vm.warp(block.timestamp + elapsed);
        uint256 price = elapsed >= 1 days ? floor : start - (start - floor) * elapsed / 1 days;
        assertEq(market.currentPrice(1), price, "linear auction quote");
        assertGe(price, floor, "floor");
        assertLe(price, start, "premium");
        uint256 a = token.balanceOf(alice);
        uint256 b = token.balanceOf(bob);
        uint256 backing = vault.totalAssets();
        vm.prank(bob);
        market.buy(1, price);
        uint256 charge = price * fee / 10000;
        assertEq(token.balanceOf(alice) - a, price - charge, "seller receives price less fee");
        assertEq(b - token.balanceOf(bob), price, "buyer pays quote");
        assertEq(vault.totalAssets() - backing, charge, "fee exact");
        assertEq(token.balanceOf(address(market)), 0, "no residue");
    }

    function test_DutchPricingHandlesMaximumUintWithoutOverflow() public {
        vm.prank(alice);
        market.startAuction(1, type(uint256).max, 1);
        vm.warp(block.timestamp + 12 hours);
        assertEq(market.currentPrice(1), type(uint256).max - (type(uint256).max - 1) / 2, "full precision price");
    }

    function test_SlippageRejectsRelistedPriceWithoutMovingValue() public {
        _list(1, 100e18);
        vm.prank(alice);
        market.cancel(1);
        _list(1, 200e18);
        uint256 b = token.balanceOf(bob);
        vm.expectRevert(abi.encodeWithSelector(BurrowMarket.PriceExceedsLimit.selector, 200e18, 100e18));
        vm.prank(bob);
        market.buy(1, 100e18);
        assertEq(token.balanceOf(bob), b, "slippage charged buyer");
        assertEq(nft.ownerOf(1), address(market), "failed purchase moved NFT");
    }

    function test_ListingAuctionAndMissingListingErrors() public {
        vm.expectRevert(BurrowMarket.InvalidPrice.selector);
        vm.prank(alice);
        market.list(1, 0);
        vm.expectRevert(abi.encodeWithSelector(BurrowMarket.NotTokenOwner.selector, 1));
        vm.prank(bob);
        market.list(1, 1);
        vm.expectRevert(abi.encodeWithSelector(BurrowMarket.InvalidAuctionPrices.selector, 1, 0));
        vm.prank(alice);
        market.startAuction(1, 1, 0);
        vm.expectRevert(abi.encodeWithSelector(BurrowMarket.InvalidAuctionPrices.selector, 1, 1));
        vm.prank(alice);
        market.startAuction(1, 1, 1);
        vm.expectRevert(abi.encodeWithSelector(BurrowMarket.InvalidAuctionPrices.selector, 1, 2));
        vm.prank(alice);
        market.startAuction(1, 1, 2);
        _list(1, 1);
        vm.expectRevert(abi.encodeWithSelector(BurrowMarket.AlreadyListed.selector, 1));
        vm.prank(alice);
        market.list(1, 2);
        vm.expectRevert(abi.encodeWithSelector(BurrowMarket.AlreadyListed.selector, 1));
        vm.prank(alice);
        market.startAuction(1, 2, 1);
        vm.expectRevert(abi.encodeWithSelector(BurrowMarket.NotListed.selector, 2));
        market.currentPrice(2);
        vm.expectRevert(abi.encodeWithSelector(BurrowMarket.NotListed.selector, 2));
        market.buy(2);
        vm.expectRevert(abi.encodeWithSelector(BurrowMarket.NotListed.selector, 2));
        market.cancel(2);
    }

    function test_ApprovalAndPaymentFailuresPreserveListing() public {
        vm.prank(alice);
        nft.setApprovalForAll(address(market), false);
        vm.expectRevert(BurrowTestNFT.Unauthorized.selector);
        vm.prank(alice);
        market.list(1, 100e18);
        (address seller,,,,,) = market.listings(1);
        assertEq(seller, address(0), "failed escrow left listing");
        vm.prank(alice);
        nft.setApprovalForAll(address(market), true);
        _list(1, 100e18);
        vm.prank(bob);
        token.approve(address(market), 0);
        vm.expectRevert(
            abi.encodeWithSignature("ERC20InsufficientAllowance(address,uint256,uint256)", address(market), 0, 100e18)
        );
        vm.prank(bob);
        market.buy(1);
        assertEq(nft.ownerOf(1), address(market), "payment failure released NFT");
        assertEq(market.currentPrice(1), 100e18, "payment failure consumed listing");
    }

    function test_UnsolicitedNFTAndForgedCallbackRejected() public {
        vm.expectRevert(BurrowMarket.UnexpectedNFT.selector);
        vm.prank(alice);
        nft.safeTransferFrom(alice, address(market), 1);
        vm.expectRevert(BurrowMarket.UnexpectedNFT.selector);
        market.onERC721Received(address(market), alice, 1, "");
        vm.expectRevert(BurrowMarket.UnexpectedNFT.selector);
        vm.prank(address(nft));
        market.onERC721Received(address(market), alice, 1, "");
    }

    function test_TaxedSQKAndNonCollectingSinkRollbackEntireSale() public {
        _list(1, 100e18);
        token.setTax(true);
        uint256 b = token.balanceOf(bob);
        vm.expectRevert(BurrowMarket.UnexpectedSQKTransfer.selector);
        vm.prank(bob);
        market.buy(1);
        assertEq(token.balanceOf(bob), b, "taxed payment charged");
        assertEq(market.currentPrice(1), 100e18, "taxed payment consumed listing");
        token.setTax(false);
        BurrowTestFeeSink bad = new BurrowTestFeeSink(token);
        bad.setIgnore(true);
        BurrowMarket m = new BurrowMarket(address(token), address(nft), address(bad), address(this), 500, 1 days);
        vm.startPrank(alice);
        nft.setApprovalForAll(address(m), true);
        m.list(2, 100e18);
        vm.stopPrank();
        vm.prank(bob);
        token.approve(address(m), type(uint256).max);
        vm.expectRevert(BurrowMarket.FeeNotCollected.selector);
        vm.prank(bob);
        m.buy(2);
        assertEq(nft.ownerOf(2), address(m), "noncollecting sink released NFT");
        assertEq(token.balanceOf(bob), b, "sink failure charged buyer");
        bad.setIgnore(false);
        bad.setFail(true);
        vm.expectRevert(BurrowTestFeeSink.DonationRejected.selector);
        vm.prank(bob);
        m.buy(2);
        assertEq(m.currentPrice(2), 100e18, "rejected donation consumed listing");
    }

    function test_NFTReceiverCannotReenterSaleAndRejectedReceiverRollsBack() public {
        _list(1, 100e18);
        BurrowMarketReentrantBuyer attacker = new BurrowMarketReentrantBuyer(market, token);
        token.mint(address(attacker), 100e18);
        attacker.buy(1);
        assertTrue(!attacker.callbackSucceeded(), "receiver reentered sale");
        assertEq(
            keccak256(attacker.callbackResult()),
            keccak256(abi.encodeWithSignature("ReentrancyGuardReentrantCall()")),
            "guard error"
        );
        assertEq(nft.ownerOf(1), address(attacker), "legitimate outer sale completes");
        _list(2, 100e18);
        BurrowMarketRejectingBuyer rejector = new BurrowMarketRejectingBuyer();
        token.mint(address(rejector), 100e18);
        uint256 backing = vault.totalAssets();
        vm.expectRevert();
        rejector.buy(market, token, 2);
        assertEq(token.balanceOf(address(rejector)), 100e18, "rejected recipient charged");
        assertEq(vault.totalAssets(), backing, "reverted sale leaked fees");
        assertEq(nft.ownerOf(2), address(market), "NFT lost");
    }

    function test_ZeroFeeAndSubWeiFeeDoNotCallDonateZero() public {
        market.setFeeBps(0);
        _list(1, 100e18);
        uint256 backing = vault.totalAssets();
        vm.prank(bob);
        market.buy(1);
        assertEq(vault.totalAssets(), backing, "zero fee");
        market.setFeeBps(500);
        _list(2, 1);
        vm.prank(bob);
        market.buy(2);
        assertEq(vault.totalAssets(), backing, "rounded zero fee");
    }

    function test_ConstructorValidationAndOwnerFeeCap() public {
        vm.expectRevert(abi.encodeWithSelector(BurrowMarket.InvalidContract.selector, alice));
        new BurrowMarket(alice, address(nft), address(vault), address(this), 0, 1);
        vm.expectRevert(abi.encodeWithSelector(BurrowMarket.InvalidContract.selector, alice));
        new BurrowMarket(address(token), alice, address(vault), address(this), 0, 1);
        vm.expectRevert(abi.encodeWithSelector(BurrowMarket.InvalidContract.selector, alice));
        new BurrowMarket(address(token), address(nft), alice, address(this), 0, 1);
        vm.expectRevert(abi.encodeWithSelector(BurrowMarket.FeeTooHigh.selector, 501));
        new BurrowMarket(address(token), address(nft), address(vault), address(this), 501, 1);
        vm.expectRevert(BurrowMarket.InvalidAuctionDuration.selector);
        new BurrowMarket(address(token), address(nft), address(vault), address(this), 0, 0);
        vm.expectRevert(abi.encodeWithSelector(BurrowMarket.FeeTooHigh.selector, 501));
        market.setFeeBps(501);
        vm.expectRevert(abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", bob));
        vm.prank(bob);
        market.setFeeBps(1);
        market.setFeeBps(500);
        assertEq(market.feeBps(), 500, "inclusive cap");
    }

    function test_LiquidatorCanAuctionCollateralAndRouteSaleFee() public {
        _open(alice, 10, 1);
        _borrow(alice, 600e18);
        valuer.proposePricePerPower(0.8e18);
        vm.warp(block.timestamp + 2 days);
        valuer.executePricePerPower();
        vm.warp(block.timestamp + 1 hours);
        vm.prank(liquidator);
        vault.liquidate(alice);
        vm.startPrank(liquidator);
        nft.setApprovalForAll(address(market), true);
        market.startAuction(10, 1000e18, 800e18);
        vm.stopPrank();
        vm.warp(block.timestamp + 12 hours);
        uint256 assets = vault.totalAssets();
        vm.prank(bob);
        market.buy(10, 900e18);
        assertEq(nft.ownerOf(10), bob, "liquidated NFT sold");
        assertEq(vault.totalAssets(), assets + 22.5e18, "liquidation auction fee");
    }
}

contract BurrowMarketHandler is BurrowTestBase {
    BurrowMarket public immutable market;
    BurrowTestNFT public immutable nft;
    BurrowTestToken public immutable token;
    BurrowVault public immutable vault;
    address[3] public actors;
    address[9] public modelOwner;
    address[9] public seller;
    uint256[9] public startPrice;
    uint256[9] public floorPrice;
    uint256[9] public listedAt;
    uint256[9] public listingFee;
    uint256 public expectedFees;
    bool public badSettlement;

    constructor(BurrowMarket m, BurrowTestNFT n, BurrowTestToken t, BurrowVault v) {
        market = m;
        nft = n;
        token = t;
        vault = v;
        for (uint256 i; i < 3; i++) {
            address who = address(uint160(uint256(keccak256(abi.encode("market actor", i)))));
            actors[i] = who;
            t.mint(who, 1e27);
            vm.startPrank(who);
            n.setApprovalForAll(address(m), true);
            t.approve(address(m), type(uint256).max);
            vm.stopPrank();
        }
        for (uint256 id = 1; id <= 8; id++) {
            address who = actors[id % 3];
            n.mint(who, id, 1);
            modelOwner[id] = who;
        }
    }

    function acceptOwnership() external {
        market.acceptOwnership();
    }

    function list(uint256 rawId, uint256 rawPrice, bool auction) external {
        uint256 id = bound(rawId, 1, 8);
        if (seller[id] != address(0)) return;
        uint256 price = bound(rawPrice, 2, 1e22);
        address who = modelOwner[id];
        seller[id] = who;
        startPrice[id] = price;
        floorPrice[id] = auction ? price / 2 : price;
        listedAt[id] = block.timestamp;
        listingFee[id] = market.feeBps();
        vm.prank(who);
        if (auction) market.startAuction(id, price, price / 2);
        else market.list(id, price);
    }

    function cancel(uint256 rawId) external {
        uint256 id = bound(rawId, 1, 8);
        address who = seller[id];
        if (who == address(0)) return;
        seller[id] = address(0);
        vm.prank(who);
        market.cancel(id);
    }

    function buy(uint256 rawId, uint256 buyerIndex) external {
        uint256 id = bound(rawId, 1, 8);
        address who = seller[id];
        if (who == address(0)) return;
        address buyer = actors[buyerIndex % 3];
        if (buyer == who) buyer = actors[(buyerIndex % 3 + 1) % 3];
        uint256 elapsed = block.timestamp - listedAt[id];
        uint256 price =
            elapsed >= 1 days ? floorPrice[id] : startPrice[id] - (startPrice[id] - floorPrice[id]) * elapsed / 1 days;
        uint256 fee = price * listingFee[id] / 10000;
        uint256 oldSeller = token.balanceOf(who);
        uint256 oldBuyer = token.balanceOf(buyer);
        uint256 oldVault = vault.totalAssets();
        seller[id] = address(0);
        modelOwner[id] = buyer;
        expectedFees += fee;
        vm.prank(buyer);
        market.buy(id, price);
        if (
            token.balanceOf(who) != oldSeller + price - fee || token.balanceOf(buyer) != oldBuyer - price
                || vault.totalAssets() != oldVault + fee
        ) badSettlement = true;
    }

    function advance(uint32 raw) external {
        vm.warp(block.timestamp + bound(raw, 1, 2 days));
    }

    function setFee(uint16 raw) external {
        market.setFeeBps(bound(raw, 0, 500));
    }
}

contract BurrowMarketInvariantTest is BurrowVaultFixture {
    BurrowMarket internal market;
    BurrowMarketHandler internal handler;

    function setUp() public {
        _setup(0);
        _seed(1e24);
        market = new BurrowMarket(address(token), address(nft), address(vault), address(this), 250, 1 days);
        handler = new BurrowMarketHandler(market, nft, token, vault);
        market.transferOwnership(address(handler));
        handler.acceptOwnership();
    }

    function targetContracts() public view returns (address[] memory a) {
        a = new address[](1);
        a[0] = address(handler);
    }

    struct FuzzSelector {
        address addr;
        bytes4[] selectors;
    }

    function targetSelectors() public view returns (FuzzSelector[] memory s) {
        s = new FuzzSelector[](1);
        bytes4[] memory a = new bytes4[](5);
        a[0] = handler.list.selector;
        a[1] = handler.cancel.selector;
        a[2] = handler.buy.selector;
        a[3] = handler.advance.selector;
        a[4] = handler.setFee.selector;
        s[0] = FuzzSelector(address(handler), a);
    }

    /// forge-config: default.invariant.runs = 256
    /// forge-config: default.invariant.depth = 64
    /// forge-config: default.invariant.fail-on-revert = true
    function invariant_EscrowOwnershipAndSaleAccounting() public view {
        assertTrue(!handler.badSettlement(), "sale did not conserve price and fee");
        assertEq(token.balanceOf(address(market)), 0, "market retained SQK");
        assertEq(token.allowance(address(market), address(vault)), 0, "residual allowance");
        assertEq(vault.totalAssets(), 1e24 + handler.expectedFees(), "fee income reconciliation");
        uint256 held;
        for (uint256 i; i < 3; i++) {
            held += token.balanceOf(handler.actors(i));
        }
        assertEq(held + handler.expectedFees(), 3e27, "all SQK conserved between buyers sellers and vault");
        for (uint256 id = 1; id <= 8; id++) {
            address expectedSeller = handler.seller(id);
            (address actualSeller,,,,,) = market.listings(id);
            assertEq(actualSeller, expectedSeller, "listing model");
            assertEq(
                nft.ownerOf(id),
                expectedSeller == address(0) ? handler.modelOwner(id) : address(market),
                "NFT escrow model"
            );
        }
    }
}

contract BurrowMarketSepoliaForkTest is BurrowSepoliaForkFixture {
    function testFork_SepoliaRealNFTSalePaysRealSQKToVault() public {
        _fork();
        (BurrowVault v,) = _liveVault();
        BurrowMarket m = new BurrowMarket(SQK, NFT, address(v), address(this), 250, 1 days);
        address holder = IERC721(NFT).ownerOf(2);
        address buyer = addr("fork market buyer");
        address lender = addr("fork market lender");
        deal(SQK, lender, 10000e18);
        vm.startPrank(lender);
        IERC20(SQK).approve(address(v), type(uint256).max);
        v.deposit(10000e18);
        vm.stopPrank();
        vm.startPrank(holder);
        IERC721(NFT).approve(address(m), 2);
        m.list(2, 100e18);
        vm.stopPrank();
        deal(SQK, buyer, 100e18);
        uint256 sellerBalance = IERC20(SQK).balanceOf(holder);
        vm.startPrank(buyer);
        IERC20(SQK).approve(address(m), 100e18);
        m.buy(2, 100e18);
        vm.stopPrank();
        assertEq(IERC721(NFT).ownerOf(2), buyer, "real NFT delivered");
        assertEq(IERC20(SQK).balanceOf(holder), sellerBalance + 97.5e18, "real seller paid");
        assertEq(v.totalAssets(), 10002.5e18, "real SQK fee reached vault");
        assertTrue(v.convertToAssets(1e18) > 1e18, "live fee raised share price");
    }
}
