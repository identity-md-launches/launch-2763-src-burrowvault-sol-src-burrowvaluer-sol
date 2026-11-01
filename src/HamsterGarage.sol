// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

interface IHMTR {
    function transferFrom(address f, address t, uint256 v) external returns (bool);
    function transfer(address t, uint256 v) external returns (bool);
    function approve(address s, uint256 v) external returns (bool);
    function stake(uint256 shares) external returns (uint256);
    function unstake(uint256 units) external returns (uint256);
    function unitsOf(address who) external view returns (uint256);
    function stakedShares() external view returns (uint256);
    function totalUnits() external view returns (uint256);
}
interface IERC721Receiver { function onERC721Received(address, address, uint256, bytes calldata) external returns (bytes4); }

/// @title HamsterGarage
/// @notice Park HMTR here and the garage stakes it back, so the position keeps compounding exit fees.
///         After 30 days parked the owner can claim one Hamster Motors car, an on-chain ERC-721.
///         Parking can end at any time, keeping the compounded HMTR but forfeiting an unclaimed car.
///         There is no owner and no admin.
contract HamsterGarage {
    string public constant name = "Hamster Motors Car";
    string public constant symbol = "HCAR";
    uint256 public constant HOLD = 30 days;
    uint256 public constant MIN_PARK = 100e18;   // makes restarting the stake wait expensive to grief

    IHMTR public immutable hmtr;

    struct Spot { address owner; uint64 parkedAt; bool claimed; uint256 units; uint256 shares; }
    mapping(uint256 => Spot) public spots;
    uint256 public nextSpot = 1;
    uint256 public nextCar = 1;

    mapping(uint256 => address) private _owner;
    mapping(address => uint256) public balanceOf;
    mapping(uint256 => address) public getApproved;
    mapping(address => mapping(address => bool)) public isApprovedForAll;
    mapping(uint256 => uint256) public carParkedShares;   // size of the position that earned the car

    error Small();
    error NotOwner();
    error TooSoon(uint256 readyAt);
    error Claimed();
    error NotApproved();
    error BadReceiver();

    event Transfer(address indexed from, address indexed to, uint256 indexed tokenId);
    event Approval(address indexed owner, address indexed spender, uint256 indexed tokenId);
    event ApprovalForAll(address indexed owner, address indexed operator, bool approved);
    event Parked(uint256 indexed spot, address indexed owner, uint256 shares, uint256 units);
    event Left(uint256 indexed spot, address indexed owner, uint256 shares);
    event CarClaimed(uint256 indexed spot, address indexed owner, uint256 carId);

    constructor(address hmtr_) {
        hmtr = IHMTR(hmtr_);
        IHMTR(hmtr_).approve(hmtr_, type(uint256).max);
    }

    function readyAt(uint256 id) public view returns (uint256) { return uint256(spots[id].parkedAt) + HOLD; }

    /// @return current HMTR value of the spot, including compounded fees
    function valueOf(uint256 id) external view returns (uint256) {
        uint256 t = hmtr.totalUnits();
        return t == 0 ? 0 : spots[id].units * hmtr.stakedShares() / t;
    }

    function park(uint256 shares) external returns (uint256 id) {
        if (shares < MIN_PARK) revert Small();
        hmtr.transferFrom(msg.sender, address(this), shares);
        uint256 units = hmtr.stake(shares);
        id = nextSpot++;
        spots[id] = Spot(msg.sender, uint64(block.timestamp), false, units, shares);
        emit Parked(id, msg.sender, shares, units);
    }

    function claimCar(uint256 id) public returns (uint256 car) {
        Spot storage s = spots[id];
        if (s.owner != msg.sender) revert NotOwner();
        if (s.claimed) revert Claimed();
        if (block.timestamp < readyAt(id)) revert TooSoon(readyAt(id));
        s.claimed = true;
        car = nextCar++;
        carParkedShares[car] = s.shares;
        _owner[car] = msg.sender;
        balanceOf[msg.sender]++;
        emit Transfer(address(0), msg.sender, car);
        emit CarClaimed(id, msg.sender, car);
    }

    function leave(uint256 id) external returns (uint256 out) {
        Spot memory s = spots[id];
        if (s.owner != msg.sender) revert NotOwner();
        delete spots[id];
        out = hmtr.unstake(s.units);
        hmtr.transfer(msg.sender, out);
        emit Left(id, msg.sender, out);
    }

    // --- ERC-721 ---
    function ownerOf(uint256 id) public view returns (address o) {
        o = _owner[id];
        if (o == address(0)) revert NotOwner();
    }

    function supportsInterface(bytes4 i) external pure returns (bool) {
        return i == 0x01ffc9a7 || i == 0x80ac58cd || i == 0x5b5e139f;
    }

    function approve(address to, uint256 id) external {
        address o = ownerOf(id);
        if (msg.sender != o && !isApprovedForAll[o][msg.sender]) revert NotApproved();
        getApproved[id] = to;
        emit Approval(o, to, id);
    }

    function setApprovalForAll(address op, bool ok) external {
        isApprovedForAll[msg.sender][op] = ok;
        emit ApprovalForAll(msg.sender, op, ok);
    }

    function transferFrom(address from, address to, uint256 id) public {
        address o = ownerOf(id);
        if (o != from || to == address(0)) revert NotOwner();
        if (msg.sender != o && msg.sender != getApproved[id] && !isApprovedForAll[o][msg.sender]) revert NotApproved();
        delete getApproved[id];
        balanceOf[from]--; balanceOf[to]++;
        _owner[id] = to;
        emit Transfer(from, to, id);
    }

    function safeTransferFrom(address from, address to, uint256 id) external { safeTransferFrom(from, to, id, ""); }

    function safeTransferFrom(address from, address to, uint256 id, bytes memory data) public {
        transferFrom(from, to, id);
        if (to.code.length != 0 && IERC721Receiver(to).onERC721Received(msg.sender, from, id, data) != IERC721Receiver.onERC721Received.selector) revert BadReceiver();
    }

    /// @notice A car drawn on-chain. Paint comes from the token id, plain rgb() so the SVG needs no escaping.
    function tokenURI(uint256 id) external view returns (string memory) {
        ownerOf(id);
        uint256 h = uint256(keccak256(abi.encode(id)));
        string memory paint = string.concat("rgb(", _s(80 + h % 170), ",", _s(80 + (h >> 8) % 170), ",", _s(80 + (h >> 16) % 170), ")");
        string memory svg = string.concat(
            "<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 320 320'><rect width='320' height='320' fill='rgb(11,10,9)'/>",
            "<path d='M50 200h220v-30l-44-8-30-44h-70l-34 44-42 12z' fill='", paint, "'/>",
            "<circle cx='104' cy='206' r='30' fill='none' stroke='rgb(196,199,203)' stroke-width='8'/><circle cx='216' cy='206' r='30' fill='none' stroke='rgb(196,199,203)' stroke-width='8'/>",
            "<circle cx='104' cy='206' r='5' fill='rgb(210,160,74)'/><circle cx='216' cy='206' r='5' fill='rgb(210,160,74)'/>",
            "<circle cx='168' cy='142' r='15' fill='rgb(217,154,78)'/><circle cx='158' cy='128' r='5' fill='rgb(233,166,160)'/><circle cx='178' cy='128' r='5' fill='rgb(233,166,160)'/></svg>"
        );
        return string.concat("data:application/json;utf8,{\"name\":\"Hamster Motors Car #", _s(id), "\",\"description\":\"Earned by parking HMTR for 30 days.\",\"image\":\"data:image/svg+xml;utf8,", svg, "\"}");
    }

    function _s(uint256 v) private pure returns (string memory) {
        if (v == 0) return "0";
        uint256 n = v; uint256 d;
        while (n != 0) { d++; n /= 10; }
        bytes memory b = new bytes(d);
        while (v != 0) { b[--d] = bytes1(uint8(48 + v % 10)); v /= 10; }
        return string(b);
    }
}
