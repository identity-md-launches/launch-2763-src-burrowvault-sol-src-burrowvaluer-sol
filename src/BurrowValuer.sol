// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

/*
 * OpenZeppelin Contracts v5.0.2: Context, Ownable and Ownable2Step are
 * included below to make this single-file submission build offline.
 * Only contract identifiers are prefixed with BurrowValuer; imports and
 * duplicate pragma/license headers are removed. The implementation is unchanged.
 * Source: https://github.com/OpenZeppelin/openzeppelin-contracts/tree/v5.0.2/contracts
 *
 * The MIT License (MIT)
 *
 * Copyright (c) 2016-2023 zOS Global Limited and contributors
 *
 * Permission is hereby granted, free of charge, to any person obtaining
 * a copy of this software and associated documentation files (the
 * "Software"), to deal in the Software without restriction, including
 * without limitation the rights to use, copy, modify, merge, publish,
 * distribute, sublicense, and/or sell copies of the Software, and to
 * permit persons to whom the Software is furnished to do so, subject to
 * the following conditions:
 *
 * The above copyright notice and this permission notice shall be included
 * in all copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS
 * OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
 * MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.
 * IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY
 * CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT,
 * TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE
 * SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
 */

// OpenZeppelin Contracts (last updated v5.0.1) (utils/BurrowValuerContext.sol)

/**
 * @dev Provides information about the current execution context, including the
 * sender of the transaction and its data. While these are generally available
 * via msg.sender and msg.data, they should not be accessed in such a direct
 * manner, since when dealing with meta-transactions the account sending and
 * paying for execution may not be the actual sender (as far as an application
 * is concerned).
 *
 * This contract is only required for intermediate, library-like contracts.
 */
abstract contract BurrowValuerContext {
    function _msgSender() internal view virtual returns (address) {
        return msg.sender;
    }

    function _msgData() internal view virtual returns (bytes calldata) {
        return msg.data;
    }

    function _contextSuffixLength() internal view virtual returns (uint256) {
        return 0;
    }
}

// OpenZeppelin Contracts (last updated v5.0.0) (access/BurrowValuerOwnable.sol)

/**
 * @dev Contract module which provides a basic access control mechanism, where
 * there is an account (an owner) that can be granted exclusive access to
 * specific functions.
 *
 * The initial owner is set to the address provided by the deployer. This can
 * later be changed with {transferOwnership}.
 *
 * This module is used through inheritance. It will make available the modifier
 * `onlyOwner`, which can be applied to your functions to restrict their use to
 * the owner.
 */
abstract contract BurrowValuerOwnable is BurrowValuerContext {
    address private _owner;

    /**
     * @dev The caller account is not authorized to perform an operation.
     */
    error OwnableUnauthorizedAccount(address account);

    /**
     * @dev The owner is not a valid owner account. (eg. `address(0)`)
     */
    error OwnableInvalidOwner(address owner);

    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    /**
     * @dev Initializes the contract setting the address provided by the deployer as the initial owner.
     */
    constructor(address initialOwner) {
        if (initialOwner == address(0)) {
            revert OwnableInvalidOwner(address(0));
        }
        _transferOwnership(initialOwner);
    }

    /**
     * @dev Throws if called by any account other than the owner.
     */
    modifier onlyOwner() {
        _checkOwner();
        _;
    }

    /**
     * @dev Returns the address of the current owner.
     */
    function owner() public view virtual returns (address) {
        return _owner;
    }

    /**
     * @dev Throws if the sender is not the owner.
     */
    function _checkOwner() internal view virtual {
        if (owner() != _msgSender()) {
            revert OwnableUnauthorizedAccount(_msgSender());
        }
    }

    /**
     * @dev Leaves the contract without owner. It will not be possible to call
     * `onlyOwner` functions. Can only be called by the current owner.
     *
     * NOTE: Renouncing ownership will leave the contract without an owner,
     * thereby disabling any functionality that is only available to the owner.
     */
    function renounceOwnership() public virtual onlyOwner {
        _transferOwnership(address(0));
    }

    /**
     * @dev Transfers ownership of the contract to a new account (`newOwner`).
     * Can only be called by the current owner.
     */
    function transferOwnership(address newOwner) public virtual onlyOwner {
        if (newOwner == address(0)) {
            revert OwnableInvalidOwner(address(0));
        }
        _transferOwnership(newOwner);
    }

    /**
     * @dev Transfers ownership of the contract to a new account (`newOwner`).
     * Internal function without access restriction.
     */
    function _transferOwnership(address newOwner) internal virtual {
        address oldOwner = _owner;
        _owner = newOwner;
        emit OwnershipTransferred(oldOwner, newOwner);
    }
}

// OpenZeppelin Contracts (last updated v5.0.0) (access/BurrowValuerOwnable2Step.sol)

/**
 * @dev Contract module which provides access control mechanism, where
 * there is an account (an owner) that can be granted exclusive access to
 * specific functions.
 *
 * The initial owner is specified at deployment time in the constructor for `BurrowValuerOwnable`. This
 * can later be changed with {transferOwnership} and {acceptOwnership}.
 *
 * This module is used through inheritance. It will make available all functions
 * from parent (BurrowValuerOwnable).
 */
abstract contract BurrowValuerOwnable2Step is BurrowValuerOwnable {
    address private _pendingOwner;

    event OwnershipTransferStarted(address indexed previousOwner, address indexed newOwner);

    /**
     * @dev Returns the address of the pending owner.
     */
    function pendingOwner() public view virtual returns (address) {
        return _pendingOwner;
    }

    /**
     * @dev Starts the ownership transfer of the contract to a new account. Replaces the pending transfer if there is one.
     * Can only be called by the current owner.
     */
    function transferOwnership(address newOwner) public virtual override onlyOwner {
        _pendingOwner = newOwner;
        emit OwnershipTransferStarted(owner(), newOwner);
    }

    /**
     * @dev Transfers ownership of the contract to a new account (`newOwner`) and deletes any pending owner.
     * Internal function without access restriction.
     */
    function _transferOwnership(address newOwner) internal virtual override {
        delete _pendingOwner;
        super._transferOwnership(newOwner);
    }

    /**
     * @dev The new owner accepts the ownership transfer.
     */
    function acceptOwnership() public virtual {
        address sender = _msgSender();
        if (pendingOwner() != sender) {
            revert OwnableUnauthorizedAccount(sender);
        }
        _transferOwnership(sender);
    }
}

/// @dev The Squeek NFT's level is one-based; it is not a staking position.
interface IBurrowValuerSqueekNFT {
    function ownerOf(uint256 tokenId) external view returns (address);
    function level(uint256 tokenId) external view returns (uint8);
}

/// @title BurrowValuer
/// @notice Values up to 32 distinct Squeek NFTs in SQK base units.
/// @dev Unaudited, testnet only. Power is an integer, and pricePerPower is SQK
///      base units (18 decimals) per one power, NOT per 1e18 power. Consequently
///      creditLine = floor(sum(power) * pricePerPower * ltvBps / 10_000).
///      The collection, power policy, LTV and price band cannot be changed.
///      The owner may only govern price within the band and rate limit, through
///      a two-day delay. This contract never holds or moves collateral.
contract BurrowValuer is BurrowValuerOwnable2Step {
    uint256 public constant BPS = 10_000;
    uint256 public constant MAX_LTV_BPS = 6_000;
    uint256 public constant MAX_PRICE_CHANGE_BPS = 2_000;
    uint256 public constant PRICE_TIMELOCK = 2 days;
    uint256 public constant MAX_TOKEN_IDS = 32;

    IBurrowValuerSqueekNFT public immutable squeekNFT;
    uint256 public immutable minPricePerPower;
    uint256 public immutable maxPricePerPower;
    uint256 public immutable ltvBps;
    uint256 public immutable maxLevel;

    uint256 public pricePerPower;
    uint256 public pendingPricePerPower;
    uint256 public priceChangeReadyAt;

    /// @notice Timestamp of the last EXECUTED price change; zero before any change.
    /// @dev The vault must reject liquidation until lastPriceChange + 1 hours
    ///      after an execution. A proposal or cancellation does not change this.
    uint256 public lastPriceChange;

    // Index zero corresponds to NFT level one. There is deliberately no setter.
    uint256[] private _powerTable;

    error InvalidCollection(address collection);
    error InvalidLtvBps(uint256 supplied);
    error InvalidPriceBand(uint256 minimum, uint256 maximum);
    error InvalidPowerTableLength(uint256 length);
    error InvalidPower(uint256 level, uint256 supplied, uint256 expected);
    error PowerTableTooLarge();
    error TooManyTokenIds(uint256 supplied);
    error TokenIdsNotStrictlyAscending(uint256 previous, uint256 current);
    error InvalidToken(uint256 tokenId);
    error LevelReadFailed(uint256 tokenId);
    error UnsupportedLevel(uint256 level);
    error PriceOutsideBand(uint256 supplied);
    error PriceUnchanged();
    error PriceChangeTooLarge(uint256 oldPrice, uint256 newPrice);
    error NoPendingPriceChange();
    error PriceChangeNotReady(uint256 readyAt);

    event PriceProposed(uint256 oldPrice, uint256 newPrice, uint256 readyAt);
    event PriceExecuted(uint256 oldPrice, uint256 newPrice);
    event PriceProposalCancelled(uint256 proposedPrice);

    /// @param initialOwner Explicit governance address; ownership transfers take two steps.
    /// @param collection The live Squeek ERC721, supplied by the deployer.
    /// @param powerTable Entry i is power at level i+1: 1000, 3000, 7000, ... .
    ///        Supply every supported level. Unsupported levels fail closed.
    /// @param initialPrice Initial SQK base units per power, within the immutable band.
    /// @param minimumPrice Nonzero inclusive floor for pricePerPower.
    /// @param maximumPrice Inclusive ceiling; must allow a 32-NFT value to fit uint256.
    /// @param initialLtvBps Fixed loan-to-value ratio, at most 6000 basis points.
    constructor(
        address initialOwner,
        address collection,
        uint256[] memory powerTable,
        uint256 initialPrice,
        uint256 minimumPrice,
        uint256 maximumPrice,
        uint256 initialLtvBps
    ) BurrowValuerOwnable(initialOwner) {
        if (collection.code.length == 0) revert InvalidCollection(collection);
        if (initialLtvBps > MAX_LTV_BPS) revert InvalidLtvBps(initialLtvBps);
        if (minimumPrice == 0 || minimumPrice > maximumPrice) {
            revert InvalidPriceBand(minimumPrice, maximumPrice);
        }
        if (initialPrice < minimumPrice || initialPrice > maximumPrice) {
            revert PriceOutsideBand(initialPrice);
        }

        uint256 count = powerTable.length;
        if (count == 0 || count > type(uint8).max) revert InvalidPowerTableLength(count);
        uint256 expected = 1_000;
        for (uint256 i; i < count; ++i) {
            if (powerTable[i] != expected) revert InvalidPower(i + 1, powerTable[i], expected);
            // Bound the aggregate before multiplication; arithmetic must never
            // panic even for extreme constructor parameters or future prices.
            if (expected > type(uint256).max / MAX_TOKEN_IDS) revert PowerTableTooLarge();
            if (i + 1 < count) expected = expected * 2 + 1_000;
        }
        if (maximumPrice > type(uint256).max / (expected * MAX_TOKEN_IDS)) {
            revert InvalidPriceBand(minimumPrice, maximumPrice);
        }

        squeekNFT = IBurrowValuerSqueekNFT(collection);
        minPricePerPower = minimumPrice;
        maxPricePerPower = maximumPrice;
        pricePerPower = initialPrice;
        ltvBps = initialLtvBps;
        maxLevel = count;
        _powerTable = powerTable;
    }

    /// @notice Maximum debt, rounded down once after summing collateral power.
    /// @dev Empty collateral has a zero line. IDs must be strictly ascending.
    function creditLine(uint256[] calldata tokenIds) external view returns (uint256) {
        uint256 value = collateralValue(tokenIds);
        // Quotient/remainder decomposition is exactly floor(value * LTV / BPS)
        // without overflowing the intermediate product for large valid bands.
        return (value / BPS) * ltvBps + (value % BPS) * ltvBps / BPS;
    }

    /// @notice Undiscounted SQK value, before LTV, also usable for NFT bonds.
    function collateralValue(uint256[] calldata tokenIds) public view returns (uint256) {
        return totalPower(tokenIds) * pricePerPower;
    }

    /// @notice Sum of the immutable table powers for the NFTs' current levels.
    /// @dev The caller (vault) is responsible for escrow and ownership checks for
    ///      its borrower; valuation remains valid while staking owns the NFTs.
    function totalPower(uint256[] calldata tokenIds) public view returns (uint256 power) {
        uint256 count = tokenIds.length;
        if (count > MAX_TOKEN_IDS) revert TooManyTokenIds(count);
        for (uint256 i; i < count; ++i) {
            if (i != 0 && tokenIds[i] <= tokenIds[i - 1]) {
                revert TokenIdsNotStrictlyAscending(tokenIds[i - 1], tokenIds[i]);
            }
            power += powerOf(tokenIds[i]);
        }
    }

    /// @notice Power of one existing NFT, independent of its current custodian.
    function powerOf(uint256 tokenId) public view returns (uint256) {
        // Check existence independently: a mapping-backed level getter might
        // retain a burned NFT's level. Never credit that stale collateral.
        try squeekNFT.ownerOf(tokenId) returns (address tokenOwner) {
            if (tokenOwner == address(0)) revert InvalidToken(tokenId);
        } catch {
            revert InvalidToken(tokenId);
        }
        try squeekNFT.level(tokenId) returns (uint8 nftLevel) {
            return powerForLevel(nftLevel);
        } catch {
            revert LevelReadFailed(tokenId);
        }
    }

    /// @notice Table lookup for a one-based NFT level, useful for escrow accounting.
    function powerForLevel(uint256 nftLevel) public view returns (uint256) {
        if (nftLevel == 0 || nftLevel > maxLevel) revert UnsupportedLevel(nftLevel);
        return _powerTable[nftLevel - 1];
    }

    /// @notice Propose a price. Replacing a pending proposal restarts the full delay.
    function proposePricePerPower(uint256 newPrice) external onlyOwner {
        _validatePriceChange(newPrice);
        pendingPricePerPower = newPrice;
        priceChangeReadyAt = block.timestamp + PRICE_TIMELOCK;
        emit PriceProposed(pricePerPower, newPrice, priceChangeReadyAt);
    }

    /// @notice Apply the sole pending proposal after two days, consuming it once.
    function executePricePerPower() external onlyOwner {
        uint256 newPrice = pendingPricePerPower;
        if (newPrice == 0) revert NoPendingPriceChange();
        if (block.timestamp < priceChangeReadyAt) revert PriceChangeNotReady(priceChangeReadyAt);
        _validatePriceChange(newPrice);

        uint256 oldPrice = pricePerPower;
        delete pendingPricePerPower;
        delete priceChangeReadyAt;
        pricePerPower = newPrice;
        lastPriceChange = block.timestamp;
        emit PriceExecuted(oldPrice, newPrice);
    }

    /// @notice Discard a proposal without moving the price or liquidation timestamp.
    function cancelPriceProposal() external onlyOwner {
        uint256 proposed = pendingPricePerPower;
        if (proposed == 0) revert NoPendingPriceChange();
        delete pendingPricePerPower;
        delete priceChangeReadyAt;
        emit PriceProposalCancelled(proposed);
    }

    function _validatePriceChange(uint256 newPrice) private view {
        if (newPrice < minPricePerPower || newPrice > maxPricePerPower) revert PriceOutsideBand(newPrice);
        uint256 current = pricePerPower;
        if (newPrice == current) revert PriceUnchanged();
        uint256 difference = newPrice > current ? newPrice - current : current - newPrice;
        // 20% = 1/5. Rounding the allowed change DOWN rejects even one wei over
        // the exact limit, in either direction, without current * BPS overflow.
        if (difference > current / (BPS / MAX_PRICE_CHANGE_BPS)) {
            revert PriceChangeTooLarge(current, newPrice);
        }
    }
}
