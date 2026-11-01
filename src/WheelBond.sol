// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

interface ICoreClock {
    struct State {
        uint64 settledThroughRound;
        uint64 cumulativeWork;
        uint96 cumulativeBlockUnits;
        uint64 blockHeight;
        uint96 blockProgress;
        uint32 workPerThousandBlocks;
        uint256 authorizationNonce;
        bool paused;
    }
    function state() external view returns (State memory);
}
interface IBurrowVault {
    function sqk() external view returns (address);
    function transfer(address to, uint256 v) external returns (bool);
    function transferFrom(address f, address t, uint256 v) external returns (bool);
    function withdraw(uint256 shares, uint256 minAssets) external returns (uint256);
    function donate(uint256 amount) external;
}
interface IApprove { function approve(address s, uint256 v) external returns (bool); }

/// @title WheelBond
/// @notice A bond whose calendar is a hamster. Maturity is measured in settled wheel work, so when
///         the hamster sleeps, no bond ages. Holders lock bSQK; leaving early costs a penalty that
///         shrinks as the wheel turns. Half the penalty goes to the bonds still locked, half is
///         donated to the Burrow vault. There is no owner and no admin.
contract WheelBond {
    uint256 public constant MIN_TERM = 500;            // blocks last-moment entries around a penalty
    uint256 public constant MAX_TERM = 1_000_000;
    uint256 public constant MAX_PENALTY_BPS = 2000;    // 20% on day zero, 0 at maturity
    uint256 private constant ONE = 1e36;

    ICoreClock public immutable core;
    IBurrowVault public immutable vault;
    address public immutable sqk;

    struct Bond { address owner; uint64 start; uint64 maturity; uint128 shares; uint256 entry; }
    mapping(uint256 => Bond) public bonds;
    uint256 public nextId = 1;
    uint256 public totalWeight;      // sum of shares x term over open bonds
    uint256 public accPerWeight;     // bSQK per weight, scaled by ONE
    uint256 public undistributed;    // penalty waiting for the next locked bond

    error Term();
    error Zero();
    error NotOwner();
    error NotMature(uint256 work, uint256 maturity);
    error Slip();

    event Locked(uint256 indexed id, address indexed owner, uint256 shares, uint256 startWork, uint256 maturityWork);
    event Redeemed(uint256 indexed id, address indexed owner, uint256 shares, uint256 bonus);
    event ExitedEarly(uint256 indexed id, address indexed owner, uint256 returned, uint256 penalty);
    event Donated(uint256 shares, uint256 assets);

    constructor(address core_, address vault_) {
        core = ICoreClock(core_);
        vault = IBurrowVault(vault_);
        sqk = IBurrowVault(vault_).sqk();
    }

    function work() public view returns (uint256) { return core.state().cumulativeWork; }

    function bonusOf(uint256 id) public view returns (uint256) {
        Bond memory b = bonds[id];
        return _weight(b) * (accPerWeight - b.entry) / ONE;
    }

    /// @return how much of the original term is still ahead, in work units
    function remaining(uint256 id) public view returns (uint256) {
        Bond memory b = bonds[id];
        uint256 w = work();
        return w >= b.maturity ? 0 : b.maturity - (w > b.start ? w : b.start);
    }

    function lock(uint256 shares, uint256 term) external returns (uint256 id) {
        if (shares == 0 || shares > type(uint128).max) revert Zero();
        if (term < MIN_TERM || term > MAX_TERM) revert Term();
        uint256 start = work();
        id = nextId++;
        Bond memory b = Bond(msg.sender, uint64(start), uint64(start + term), uint128(shares), accPerWeight);
        bonds[id] = b;
        totalWeight += _weight(b);
        if (undistributed != 0) { uint256 u = undistributed; undistributed = 0; _spread(u); }
        vault.transferFrom(msg.sender, address(this), shares);
        emit Locked(id, msg.sender, shares, start, b.maturity);
    }

    function redeem(uint256 id) external {
        Bond memory b = _take(id);
        uint256 w = work();
        if (w < b.maturity) revert NotMature(w, b.maturity);
        uint256 bonus = _weight(b) * (accPerWeight - b.entry) / ONE;
        delete bonds[id];
        totalWeight -= _weight(b);
        vault.transfer(b.owner, b.shares + bonus);
        emit Redeemed(id, b.owner, b.shares, bonus);
    }

    /// @notice Leave before maturity. Unclaimed bonus is forfeited. If the clock cannot be read the
    ///         full penalty applies, so principal can always leave even if the core is upgraded away.
    function exitEarly(uint256 id, uint256 minOut) external {
        Bond memory b = _take(id);
        uint256 term = b.maturity - b.start;
        uint256 left = term;
        try core.state() returns (ICoreClock.State memory s) {
            uint256 w = s.cumulativeWork;
            left = w >= b.maturity ? 0 : b.maturity - (w > b.start ? w : b.start);
        } catch {}
        uint256 penalty = uint256(b.shares) * MAX_PENALTY_BPS * left / term / 10_000;
        uint256 bonus = _weight(b) * (accPerWeight - b.entry) / ONE;
        uint256 out = b.shares - penalty;
        if (out < minOut) revert Slip();
        delete bonds[id];
        totalWeight -= uint256(b.shares) * term;
        uint256 toVault = penalty / 2;
        uint256 kept = penalty - toVault + bonus;
        if (toVault != 0) {
            try this.donateShares(toVault) {} catch { kept += toVault; }
        }
        if (kept != 0) _spread(kept);
        vault.transfer(b.owner, out);
        emit ExitedEarly(id, b.owner, out, penalty);
    }

    /// @dev External so a vault without idle cash fails softly. Only callable by this contract.
    function donateShares(uint256 shares) external {
        if (msg.sender != address(this)) revert NotOwner();
        uint256 assets = vault.withdraw(shares, 0);
        IApprove(sqk).approve(address(vault), assets);
        vault.donate(assets);
        emit Donated(shares, assets);
    }

    function _take(uint256 id) private view returns (Bond memory b) {
        b = bonds[id];
        if (b.owner != msg.sender) revert NotOwner();
    }

    function _spread(uint256 amount) private {
        if (totalWeight == 0) { undistributed += amount; return; }
        accPerWeight += amount * ONE / totalWeight;
    }

    function _weight(Bond memory b) private pure returns (uint256) {
        return uint256(b.shares) * (b.maturity - b.start);
    }
}
