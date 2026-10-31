// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

interface IERC20 {
    function transfer(address to, uint256 v) external returns (bool);
    function transferFrom(address f, address t, uint256 v) external returns (bool);
    function balanceOf(address a) external view returns (uint256);
}
interface IERC721 {
    function transferFrom(address f, address t, uint256 id) external;
    function setApprovalForAll(address op, bool ok) external;
    function ownerOf(uint256 id) external view returns (address);
}
interface IStaking {
    function deposit(address collection, uint256[] calldata tokenIds) external;
    function withdraw(address collection, uint256[] calldata tokenIds) external;
    function claim(address recipient) external;
    function setClaimRecipient(address recipient) external;
    function claimable(address account) external view returns (uint256);
    function accountPower(address account) external view returns (uint256);
}
interface IValuer {
    function creditLine(uint256[] calldata tokenIds) external view returns (uint256);
    function ltvBps() external view returns (uint256);
    function lastPriceChange() external view returns (uint256);
}

/// @title Burrow vault, lean build
/// @notice Lenders supply SQK and hold bSQK. Borrowers escrow Squeek NFTs, which the
/// vault re-stakes on Squeekchain, and borrow SQK against the mining power of those
/// NFTs. Staking rewards earned by the escrowed collateral pay the debt down by
/// themselves. Marketplace and v4 swap fees arrive through donate() and raise the
/// share price. Deliberately small: Sepolia currently charges about 1,550 gas per byte
/// of deployed code against a 16,777,216 gas cap per transaction, so a contract has to
/// stay near 10 KB to exist at all.
contract BurrowVaultLite {
    // --- ERC20 (bSQK) ---
    string public constant name = "Burrow SQK";
    string public constant symbol = "bSQK";
    uint8 public constant decimals = 18;
    uint256 public totalSupply;
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;
    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    // --- config ---
    IERC20 public immutable sqk;
    IERC721 public immutable squeek;
    IStaking public immutable staking;
    IValuer public immutable valuer;
    uint256 public immutable ratePerSecond;      // 1e18 scale
    uint256 public constant MAX_RATE = uint256(0.5e18) / 365 days;
    uint256 public constant MINIMUM_LIQUIDITY = 1000;
    uint256 public constant LIQ_BONUS_BPS = 1000;        // liquidator pays value less this
    uint256 public constant LIQ_THRESHOLD_BPS = 7500;    // debt/value that opens liquidation; borrow cap is the 60% line
    uint256 public constant MAX_IDS = 32;
    uint256 public constant FREEZE_AFTER_PRICE_MOVE = 1 hours;

    // --- lending state ---
    struct Position { uint256 principal; uint256 index; uint256 power; uint256 rewardMark; uint256[] ids; }
    mapping(address => Position) private _pos;
    uint256 public borrowIndex = 1e18;           // compounding debt index
    uint256 public lastAccrual;
    uint256 public scaledDebt;                   // sum of principal/index, 1e18 scale
    uint256 public totalPower;                   // escrowed NFT power
    uint256 public rewardPerPower;               // 1e18 scale, grows on sweep
    uint256 public unsettled;                    // swept SQK not yet credited to any debt; not lender money
    uint256 public tracked;                      // SQK this contract moved itself; the rest is rewards

    event Deposit(address indexed who, uint256 assets, uint256 shares);
    event Withdraw(address indexed who, uint256 shares, uint256 assets);
    event Opened(address indexed who, uint256 power);
    event Borrowed(address indexed who, uint256 amount);
    event Repaid(address indexed who, uint256 amount);
    event Closed(address indexed who);
    event Swept(uint256 amount, uint256 perPower);
    event Donated(address indexed from, uint256 amount);
    event Liquidated(address indexed borrower, address indexed by, uint256 debt, uint256 paid);
    event Surplus(address indexed who, uint256 amount);

    error Zero();
    error BadIds();
    error NoPosition();
    error HasPosition();
    error OverLine(uint256 debt, uint256 line);
    error Healthy();
    error Frozen();
    error NoLiquidity(uint256 want, uint256 have);
    error Slip();
    error MinFirstDeposit();
    error DebtOutstanding();

    constructor(address sqk_, address squeek_, address staking_, address valuer_, uint256 rate_) {
        if (sqk_.code.length == 0 || squeek_.code.length == 0 || staking_.code.length == 0 || valuer_.code.length == 0) revert Zero();
        if (rate_ > MAX_RATE) revert Zero();
        sqk = IERC20(sqk_); squeek = IERC721(squeek_); staking = IStaking(staking_); valuer = IValuer(valuer_);
        ratePerSecond = rate_; lastAccrual = block.timestamp;
        IERC721(squeek_).setApprovalForAll(staking_, true);
        IStaking(staking_).setClaimRecipient(address(this));
    }

    // --- ERC20 ---
    function approve(address s, uint256 v) external returns (bool) { allowance[msg.sender][s] = v; emit Approval(msg.sender, s, v); return true; }
    function transfer(address t, uint256 v) external returns (bool) { _move(msg.sender, t, v); return true; }
    function transferFrom(address f, address t, uint256 v) external returns (bool) {
        uint256 a = allowance[f][msg.sender];
        if (a != type(uint256).max) allowance[f][msg.sender] = a - v;
        _move(f, t, v); return true;
    }
    function _move(address f, address t, uint256 v) private {
        if (t == address(0)) revert Zero();
        balanceOf[f] -= v; unchecked { balanceOf[t] += v; } emit Transfer(f, t, v);
    }
    function _mint(address t, uint256 v) private { totalSupply += v; unchecked { balanceOf[t] += v; } emit Transfer(address(0), t, v); }
    function _burn(address f, uint256 v) private { balanceOf[f] -= v; unchecked { totalSupply -= v; } emit Transfer(f, address(0), v); }

    // --- accounting ---
    function accrue() public {
        uint256 dt = block.timestamp - lastAccrual;
        if (dt == 0) return;
        lastAccrual = block.timestamp;
        if (scaledDebt != 0) borrowIndex += borrowIndex * ratePerSecond * dt / 1e18;
    }
    function totalBorrows() public view returns (uint256) {
        uint256 dt = block.timestamp - lastAccrual;
        uint256 idx = scaledDebt == 0 ? borrowIndex : borrowIndex + borrowIndex * ratePerSecond * dt / 1e18;
        return scaledDebt * idx / 1e18;
    }
    /// @dev Swept rewards sit in this contract until a borrower settles, so they are
    /// excluded here and from idle liquidity; otherwise the share price would jump on
    /// every sweep and fall again as positions settle.
    function totalAssets() public view returns (uint256) { return idle() + totalBorrows(); }
    function idle() public view returns (uint256) { return tracked - unsettled; }
    function convertToShares(uint256 a) public view returns (uint256) {
        uint256 s = totalSupply; return s == 0 ? a : a * s / totalAssets();
    }
    function convertToAssets(uint256 sh) public view returns (uint256) {
        uint256 s = totalSupply; return s == 0 ? sh : sh * totalAssets() / s;
    }

    function debtOf(address b) public view returns (uint256) {
        Position storage p = _pos[b];
        if (p.index == 0) return 0;
        uint256 dt = block.timestamp - lastAccrual;
        uint256 idx = scaledDebt == 0 ? borrowIndex : borrowIndex + borrowIndex * ratePerSecond * dt / 1e18;
        uint256 gross = p.principal * idx / p.index;
        uint256 credit = p.power * (rewardPerPower - p.rewardMark) / 1e18;
        return credit >= gross ? 0 : gross - credit;
    }
    function creditLineOf(address b) public view returns (uint256) {
        Position storage p = _pos[b];
        return p.ids.length == 0 ? 0 : valuer.creditLine(p.ids);
    }
    function positionIds(address b) external view returns (uint256[] memory) { return _pos[b].ids; }
    /// @notice Debt above which `liquidate` is open for this borrower.
    function liquidationThresholdOf(address b) external view returns (uint256) { return creditLineOf(b) * 10000 / valuer.ltvBps() * LIQ_THRESHOLD_BPS / 10000; }
    function positionPower(address b) external view returns (uint256) { return _pos[b].power; }

    function _settle(address b) private returns (Position storage p) {
        accrue();
        p = _pos[b];
        if (p.index == 0) return p;
        sweepRewards();                        // credit everything mined up to this moment
        uint256 gross = p.principal * borrowIndex / p.index;
        uint256 credit = p.power * (rewardPerPower - p.rewardMark) / 1e18;
        unsettled = credit > unsettled ? 0 : unsettled - credit;   // rounding dust only
        uint256 net = credit >= gross ? 0 : gross - credit;
        scaledDebt -= p.principal * 1e18 / p.index;
        p.principal = net;
        p.index = borrowIndex;
        p.rewardMark = rewardPerPower;
        scaledDebt += net * 1e18 / borrowIndex;
        if (credit > gross) { _push(b, credit - gross); emit Surplus(b, credit - gross); }
    }

    // --- lenders ---
    function deposit(uint256 assets, uint256 minShares) external returns (uint256 shares) {
        if (assets == 0) revert Zero();
        accrue();
        if (totalSupply == 0) {
            if (assets <= MINIMUM_LIQUIDITY) revert MinFirstDeposit();
            _mint(address(this), totalAssets() + MINIMUM_LIQUIDITY);
            shares = assets - MINIMUM_LIQUIDITY;
        } else {
            shares = convertToShares(assets);
        }
        if (shares == 0 || shares < minShares) revert Slip();
        _mint(msg.sender, shares);
        _pull(msg.sender, assets);
        emit Deposit(msg.sender, assets, shares);
    }

    function withdraw(uint256 shares, uint256 minAssets) external returns (uint256 assets) {
        if (shares == 0) revert Zero();
        accrue();
        assets = convertToAssets(shares);
        if (assets == 0 || assets < minAssets) revert Slip();
        uint256 cash = idle();
        if (assets > cash) revert NoLiquidity(assets, cash);
        _burn(msg.sender, shares);
        _push(msg.sender, assets);
        emit Withdraw(msg.sender, shares, assets);
    }

    /// @notice Route a fee in. Raises the share price for every holder, mints nothing.
    function donate(uint256 amount) external {
        if (amount == 0) revert Zero();
        _pull(msg.sender, amount);
        emit Donated(msg.sender, amount);
    }

    // --- borrowers ---
    function openPosition(uint256[] calldata ids) external {
        if (ids.length == 0 || ids.length > MAX_IDS) revert BadIds();
        Position storage p = _pos[msg.sender];
        if (p.ids.length != 0) revert HasPosition();
        accrue();
        sweepRewards();                        // rewards mined before this position never reach it
        uint256 prev;
        for (uint256 i; i < ids.length; ++i) {
            if (i != 0 && ids[i] <= prev) revert BadIds();
            prev = ids[i];
            squeek.transferFrom(msg.sender, address(this), ids[i]);
            p.ids.push(ids[i]);
        }
        // Power is what Squeekchain itself credits the vault for these NFTs, so reward
        // splitting between borrowers matches the real reward stream exactly.
        uint256 power = staking.accountPower(address(this));
        staking.deposit(address(squeek), ids);
        power = staking.accountPower(address(this)) - power;
        if (power == 0 || valuer.creditLine(ids) == 0) revert Zero();
        p.power = power; p.index = borrowIndex; p.rewardMark = rewardPerPower;
        totalPower += power;
        emit Opened(msg.sender, power);
    }

    function borrow(uint256 amount) external {
        if (amount == 0) revert Zero();
        Position storage p = _settle(msg.sender);
        if (p.ids.length == 0) revert NoPosition();
        uint256 cash = idle();
        if (amount > cash) revert NoLiquidity(amount, cash);
        uint256 newDebt = p.principal + amount;
        uint256 line = valuer.creditLine(p.ids);
        if (newDebt > line) revert OverLine(newDebt, line);
        scaledDebt -= p.principal * 1e18 / p.index;
        p.principal = newDebt;
        scaledDebt += newDebt * 1e18 / borrowIndex;
        _push(msg.sender, amount);
        emit Borrowed(msg.sender, amount);
    }

    function repay(uint256 amount) external {
        Position storage p = _settle(msg.sender);
        if (p.ids.length == 0) revert NoPosition();
        if (amount > p.principal) amount = p.principal;
        if (amount == 0) revert Zero();
        scaledDebt -= p.principal * 1e18 / p.index;
        p.principal -= amount;
        scaledDebt += p.principal * 1e18 / borrowIndex;
        _pull(msg.sender, amount);
        emit Repaid(msg.sender, amount);
    }

    function closePosition() external {
        Position storage p = _settle(msg.sender);
        if (p.ids.length == 0) revert NoPosition();
        if (p.principal != 0) revert DebtOutstanding();
        _release(msg.sender, p);
        emit Closed(msg.sender);
    }

    /// @notice Pull in what the escrowed collateral mined and credit it against debt,
    /// pro rata by power. Anyone may call it; the hamster pays the loans down.
    /// @dev Measures against `tracked`, not a before/after balance, so rewards that
    /// anyone pushed here earlier via staking.claim(vault) still reach the borrowers.
    function sweepRewards() public returns (uint256 amount) {
        staking.claim(address(this));
        amount = sqk.balanceOf(address(this)) - tracked;
        tracked += amount;
        if (amount == 0 || totalPower == 0) return amount;
        uint256 per = amount * 1e18 / totalPower;
        rewardPerPower += per;
        unsettled += per * totalPower / 1e18;
        emit Swept(amount, per);
    }

    function liquidate(address borrower) external {
        if (block.timestamp < valuer.lastPriceChange() + FREEZE_AFTER_PRICE_MOVE) revert Frozen();
        Position storage p = _settle(borrower);
        if (p.ids.length == 0) revert NoPosition();
        uint256 debt = p.principal;
        uint256 value = valuer.creditLine(p.ids) * 10000 / valuer.ltvBps();
        if (debt <= value * LIQ_THRESHOLD_BPS / 10000) revert Healthy();
        // Liquidator takes every NFT and pays collateral value less LIQ_BONUS_BPS. Anything
        // above the debt goes back to the borrower; any shortfall is written off against
        // the share price, so a sunk position can always be cleared.
        uint256 pay = value * (10000 - LIQ_BONUS_BPS) / 10000;
        scaledDebt -= debt * 1e18 / p.index;
        p.principal = 0;
        _pull(msg.sender, pay);
        uint256[] memory ids = _release(borrower, p);
        for (uint256 i; i < ids.length; ++i) squeek.transferFrom(address(this), msg.sender, ids[i]);
        if (pay > debt) _push(borrower, pay - debt);
        emit Liquidated(borrower, msg.sender, debt, pay);
    }

    function _release(address b, Position storage p) private returns (uint256[] memory ids) {
        ids = p.ids;
        staking.withdraw(address(squeek), ids);
        totalPower -= p.power;
        delete _pos[b];
        if (msg.sender == b) for (uint256 i; i < ids.length; ++i) squeek.transferFrom(address(this), b, ids[i]);
    }

    function _pull(address f, uint256 v) private { tracked += v; if (!sqk.transferFrom(f, address(this), v)) revert Zero(); }
    function _push(address t, uint256 v) private { tracked -= v; if (!sqk.transfer(t, v)) revert Zero(); }

    function onERC721Received(address, address, uint256, bytes calldata) external pure returns (bytes4) {
        return this.onERC721Received.selector;
    }
}
