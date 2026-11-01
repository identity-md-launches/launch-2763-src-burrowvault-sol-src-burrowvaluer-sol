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
interface IBSQK {
    function transfer(address to, uint256 v) external returns (bool);
    function transferFrom(address f, address t, uint256 v) external returns (bool);
}

/// @title WheelStock
/// @notice A share token backed by bSQK, with no maturity. Anyone mints at net asset value and can
///         trade the token freely. Redeeming charges an exit fee that stays in the pool, which raises
///         the price of every remaining share: the fee is the dividend. The market keeps hamster
///         hours: the fee is low while the wheel has moved recently and high while the hamster sleeps.
///         Shares staked back into the contract earn half of every exit fee as new shares, so a
///         stake compounds. An unstake waits for the wheel to turn STAKE_WORK units.
///         A hamster hoards food in its cheeks, so a quarter of each fee goes into the cheek pouch,
///         outside the share price. Each POUCH_WORK of running empties the pouch into the pool.
///         There is no owner and no admin, and redeeming is never blocked.
contract WheelStock {
    string public constant name = "Hamster Motors";
    string public constant symbol = "HMTR";
    uint8 public constant decimals = 18;
    uint256 public constant OPEN_FEE_BPS = 100;     // 1% during hamster hours
    uint256 public constant CLOSED_FEE_BPS = 500;   // 5% while the hamster sleeps
    uint256 public constant OPEN_WINDOW = 1 hours;  // how long a wheel move keeps the market open
    uint256 public constant STAKE_WORK = 200;       // wheel work a stake must wait, blocks fee sniping
    uint256 public constant POUCH_WORK = 500;       // one run of this much empties the cheek pouch
    uint256 private constant VIRTUAL = 1e6;         // blunts first-depositor share inflation

    ICoreClock public immutable core;
    IBSQK public immutable bsqk;

    uint256 public totalSupply;
    uint256 public nav;                             // bSQK backing the shares; direct transfers do not count
    uint256 public lastWork;
    uint256 public pouch;                           // fees hoarded outside the share price
    uint256 public pouchWork;                       // wheel work at the last time the pouch emptied
    uint256 public lastMove;
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;
    uint256 public stakedShares;                    // shares held for stakers, grows as fees compound
    uint256 public totalUnits;
    mapping(address => uint256) public unitsOf;
    mapping(address => uint256) public unstakeAt;   // wheel work at which a stake can leave

    error Zero();
    error Slip();
    error WheelTooEarly(uint256 work, uint256 needed);

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);
    event Minted(address indexed to, uint256 assets, uint256 shares);
    event Redeemed(address indexed from, uint256 shares, uint256 assets, uint256 fee);
    event Staked(address indexed who, uint256 shares, uint256 units);
    event Unstaked(address indexed who, uint256 shares, uint256 units);
    event Compounded(uint256 assets, uint256 shares);
    event PouchEmptied(uint256 assets, uint256 work);
    event WheelMoved(uint256 work, uint256 at);

    constructor(address core_, address bsqk_) {
        core = ICoreClock(core_);
        bsqk = IBSQK(bsqk_);
        lastWork = pouchWork = _work();
    }

    function sharePrice() external view returns (uint256) { return (nav + VIRTUAL) * 1e18 / (totalSupply + VIRTUAL); }

    function marketOpen() public view returns (bool) {
        return _work() > lastWork || (lastMove != 0 && block.timestamp < lastMove + OPEN_WINDOW);
    }

    function exitFeeBps() public view returns (uint256) { return marketOpen() ? OPEN_FEE_BPS : CLOSED_FEE_BPS; }

    /// @notice Records a wheel move. Anyone can call it; mint and redeem call it too.
    function poke() public {
        uint256 w = _work();
        if (w > lastWork) { lastWork = w; lastMove = block.timestamp; emit WheelMoved(w, block.timestamp); }
        if (pouch != 0 && (w == 0 || w >= pouchWork + POUCH_WORK)) {   // a dead clock cannot trap the pouch
            emit PouchEmptied(pouch, w);
            nav += pouch;
            pouch = 0;
            pouchWork = w;
        }
    }

    function previewMint(uint256 assets) public view returns (uint256) { return assets * (totalSupply + VIRTUAL) / (nav + VIRTUAL); }

    function previewRedeem(uint256 shares) public view returns (uint256 assets, uint256 fee) {
        uint256 gross = shares == totalSupply ? nav : shares * (nav + VIRTUAL) / (totalSupply + VIRTUAL);
        if (gross > nav) gross = nav;
        fee = shares == totalSupply ? 0 : gross * exitFeeBps() / 10_000;   // the last holder has nobody to pay
        assets = gross - fee;
    }

    function mint(uint256 assets, uint256 minShares) external returns (uint256 shares) {
        poke();
        shares = previewMint(assets);
        if (shares == 0) revert Zero();
        if (shares < minShares) revert Slip();
        nav += assets;
        totalSupply += shares;
        balanceOf[msg.sender] += shares;
        emit Transfer(address(0), msg.sender, shares);
        emit Minted(msg.sender, assets, shares);
        bsqk.transferFrom(msg.sender, address(this), assets);
    }

    function redeem(uint256 shares, uint256 minAssets) external returns (uint256 assets) {
        if (shares == 0) revert Zero();
        poke();
        uint256 fee;
        (assets, fee) = previewRedeem(shares);
        if (assets < minAssets) revert Slip();
        balanceOf[msg.sender] -= shares;
        totalSupply -= shares;
        nav -= assets;
        emit Transfer(msg.sender, address(0), shares);
        emit Redeemed(msg.sender, shares, assets, fee);
        uint256 cheek = fee / 4;
        nav -= cheek;
        pouch += cheek;
        if (totalUnits != 0) _compound(fee / 2);
        bsqk.transfer(msg.sender, assets);
    }

    function stakedOf(address who) public view returns (uint256) {
        return totalUnits == 0 ? 0 : unitsOf[who] * stakedShares / totalUnits;
    }

    /// @notice Stake shares back. A new stake restarts the wheel wait on the whole position.
    function stake(uint256 shares) external returns (uint256 units) {
        if (shares == 0) revert Zero();
        poke();
        units = totalUnits == 0 ? shares : shares * totalUnits / stakedShares;
        if (units == 0) revert Zero();
        _move(msg.sender, address(this), shares);
        stakedShares += shares;
        totalUnits += units;
        unitsOf[msg.sender] += units;
        unstakeAt[msg.sender] = lastWork + STAKE_WORK;
        emit Staked(msg.sender, shares, units);
    }

    /// @notice Leave the stake. If the clock cannot be read the wait no longer applies.
    function unstake(uint256 units) external returns (uint256 shares) {
        if (units == 0) revert Zero();
        uint256 w = _work();
        if (w != 0 && w < unstakeAt[msg.sender]) revert WheelTooEarly(w, unstakeAt[msg.sender]);
        shares = units * stakedShares / totalUnits;
        unitsOf[msg.sender] -= units;
        totalUnits -= units;
        stakedShares -= shares;
        _move(address(this), msg.sender, shares);
        emit Unstaked(msg.sender, shares, units);
    }

    function _compound(uint256 assets) private {
        if (assets == 0) return;
        uint256 sh = assets * (totalSupply + VIRTUAL) / (nav - assets + VIRTUAL);
        totalSupply += sh;
        balanceOf[address(this)] += sh;
        stakedShares += sh;
        emit Transfer(address(0), address(this), sh);
        emit Compounded(assets, sh);
    }

    function approve(address s, uint256 v) external returns (bool) {
        allowance[msg.sender][s] = v;
        emit Approval(msg.sender, s, v);
        return true;
    }

    function transfer(address to, uint256 v) external returns (bool) { _move(msg.sender, to, v); return true; }

    function transferFrom(address f, address to, uint256 v) external returns (bool) {
        uint256 a = allowance[f][msg.sender];
        if (a != type(uint256).max) allowance[f][msg.sender] = a - v;
        _move(f, to, v);
        return true;
    }

    function _move(address f, address to, uint256 v) private {
        balanceOf[f] -= v;
        balanceOf[to] += v;
        emit Transfer(f, to, v);
    }

    /// @dev An unreadable clock counts as a closed market, so redeeming still works at the higher fee.
    function _work() private view returns (uint256) {
        try core.state() returns (ICoreClock.State memory s) { return s.cumulativeWork; } catch { return 0; }
    }
}
