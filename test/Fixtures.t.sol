// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;
import {BurrowVaultLite} from "../src/BurrowVaultLite.sol";
import {BurrowValuer} from "../src/BurrowValuer.sol";

// Shared harness for the Market and Hook suites. No forge-std: Foundry's cheatcode ABI is
// declared directly so the whole repository builds offline.
interface IERC20 {
    function totalSupply() external view returns (uint256);
    function balanceOf(address) external view returns (uint256);
    function allowance(address, address) external view returns (uint256);
    function approve(address, uint256) external returns (bool);
    function transfer(address, uint256) external returns (bool);
    function transferFrom(address, address, uint256) external returns (bool);
}
interface IERC721 {
    function ownerOf(uint256) external view returns (address);
    function approve(address, uint256) external;
    function setApprovalForAll(address, bool) external;
    function transferFrom(address, address, uint256) external;
    function safeTransferFrom(address, address, uint256) external;
}
interface IERC721Receiver { function onERC721Received(address, address, uint256, bytes calldata) external returns (bytes4); }
abstract contract ERC721Holder is IERC721Receiver {
    function onERC721Received(address, address, uint256, bytes calldata) external virtual returns (bytes4) { return IERC721Receiver.onERC721Received.selector; }
}
/// Minimal ERC20 base for the test token.
abstract contract ERC20 is IERC20 {
    error ERC20InsufficientAllowance(address spender, uint256 allowance, uint256 needed);
    error ERC20InsufficientBalance(address sender, uint256 balance, uint256 needed);
    string public name; string public symbol;
    uint256 public totalSupply;
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;
    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);
    constructor(string memory n, string memory s) { name = n; symbol = s; }
    function decimals() public view virtual returns (uint8) { return 18; }
    function approve(address sp, uint256 v) public virtual returns (bool) { allowance[msg.sender][sp] = v; emit Approval(msg.sender, sp, v); return true; }
    function transfer(address to, uint256 v) public virtual returns (bool) { _move(msg.sender, to, v); return true; }
    function transferFrom(address f, address t, uint256 v) public virtual returns (bool) {
        uint256 a = allowance[f][msg.sender]; if (a < v) revert ERC20InsufficientAllowance(msg.sender, a, v);
        if (a != type(uint256).max) allowance[f][msg.sender] = a - v;
        _move(f, t, v); return true;
    }
    function _move(address f, address t, uint256 v) internal { if (balanceOf[f] < v) revert ERC20InsufficientBalance(f, balanceOf[f], v); balanceOf[f] -= v; balanceOf[t] += v; emit Transfer(f, t, v); }
    function _mint(address t, uint256 v) internal { totalSupply += v; balanceOf[t] += v; emit Transfer(address(0), t, v); }
    function _burn(address f, uint256 v) internal { if (balanceOf[f] < v) revert ERC20InsufficientBalance(f, balanceOf[f], v); balanceOf[f] -= v; totalSupply -= v; emit Transfer(f, address(0), v); }
}

// This repository has no forge-std dependency. The small test harness below uses
// Foundry's public cheatcode ABI and invariant discovery ABI directly, so all four
// test files compile offline without adding libraries or remappings.
interface BurrowVm {
    function prank(address) external;
    function startPrank(address) external;
    function stopPrank() external;
    function warp(uint256) external;
    function expectRevert() external;
    function expectRevert(bytes4) external;
    function expectRevert(bytes calldata) external;
    function expectEmit(bool, bool, bool, bool, address) external;
    function envOr(string calldata, string calldata) external returns (string memory);
    function createSelectFork(string calldata, uint256) external returns (uint256);
    function createSelectFork(string calldata) external returns (uint256);
    function skip(bool) external;
    function record() external;
    function accesses(address) external returns (bytes32[] memory, bytes32[] memory);
    function load(address, bytes32) external view returns (bytes32);
    function store(address, bytes32, bytes32) external;
    function etch(address, bytes calldata) external;
    function mockCall(address, bytes calldata, bytes calldata) external;
    function mockCallRevert(address, bytes calldata, bytes calldata) external;
    function clearMockedCalls() external;
    function snapshotState() external returns (uint256);
    function revertToState(uint256) external returns (bool);
    function getCode(string calldata) external view returns (bytes memory);
}

abstract contract BurrowTestBase {
    BurrowVm internal constant vm = BurrowVm(address(uint160(uint256(keccak256("hevm cheat code")))));
    error AssertionFailed(string reason);

    function assertTrue(bool a, string memory why) internal pure {
        if (!a) revert AssertionFailed(why);
    }

    function assertEq(uint256 a, uint256 b, string memory why) internal pure {
        assertTrue(a == b, why);
    }

    function assertEq(address a, address b, string memory why) internal pure {
        assertTrue(a == b, why);
    }

    function assertEq(bytes32 a, bytes32 b, string memory why) internal pure {
        assertTrue(a == b, why);
    }

    function assertGe(uint256 a, uint256 b, string memory why) internal pure {
        assertTrue(a >= b, why);
    }

    function assertLe(uint256 a, uint256 b, string memory why) internal pure {
        assertTrue(a <= b, why);
    }

    function addr(string memory label) internal pure returns (address) {
        return address(uint160(uint256(keccak256(bytes(label)))));
    }

    function bound(uint256 x, uint256 lo, uint256 hi) internal pure returns (uint256) {
        if (x >= lo && x <= hi) return x;
        return lo + x % (hi - lo + 1);
    }

    function ids(uint256 id) internal pure returns (uint256[] memory a) {
        a = new uint256[](1);
        a[0] = id;
    }

    function powers() internal pure returns (uint256[] memory p) {
        p = new uint256[](16);
        uint256 n = 1000;
        for (uint256 i; i < p.length; i++) {
            p[i] = n;
            n = n * 2 + 1000;
        }
    }

    // Equivalent to forge-std's ERC20 deal: discover and update only balanceOf's
    // backing slot. No RPC endpoint, key, or chain balance is hardcoded.
    function deal(address token, address account, uint256 amount) internal {
        vm.record();
        IERC20(token).balanceOf(account);
        (bytes32[] memory reads,) = vm.accesses(token);
        bool found;
        for (uint256 i; i < reads.length; i++) {
            bytes32 old = vm.load(token, reads[i]);
            vm.store(token, reads[i], bytes32(amount));
            if (IERC20(token).balanceOf(account) == amount) {
                found = true;
                break;
            }
            vm.store(token, reads[i], old);
        }
        assertTrue(found, "ERC20 balance slot was not found");
    }
}

contract BurrowTestToken is ERC20 {
    uint8 private _decimals = 18;
    bool public tax;
    bool public rejectApproval;
    address public callbackTarget;
    bytes public callbackData;
    bytes public callbackResult;
    bool public callbackSucceeded;
    constructor() ERC20("Mock SQK", "SQK") {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    function burn(address from, uint256 amount) external {
        _burn(from, amount);
    }

    function setDecimals(uint8 d) external {
        _decimals = d;
    }

    function decimals() public view override returns (uint8) {
        return _decimals;
    }

    function setTax(bool b) external {
        tax = b;
    }

    function setRejectApproval(bool b) external {
        rejectApproval = b;
    }

    function setCallback(address target, bytes calldata data) external {
        callbackTarget = target;
        callbackData = data;
    }

    function approve(address spender, uint256 amount) public override returns (bool) {
        if (rejectApproval) return false;
        return super.approve(spender, amount);
    }

    function transferFrom(address from, address to, uint256 amount) public override returns (bool) {
        bool ok = super.transferFrom(from, to, amount);
        if (tax && amount != 0) _burn(to, 1);
        if (callbackTarget != address(0)) {
            (callbackSucceeded, callbackResult) = callbackTarget.call(callbackData);
        }
        return ok;
    }
}

contract BurrowTestNFT {
    mapping(uint256 => address) private owners;
    mapping(uint256 => uint8) public level;
    mapping(uint256 => address) public getApproved;
    mapping(address => mapping(address => bool)) public isApprovedForAll;
    error MissingToken();
    error Unauthorized();
    error UnsafeRecipient();

    function mint(address to, uint256 id, uint8 lev) external {
        if (owners[id] != address(0)) revert Unauthorized();
        owners[id] = to;
        level[id] = lev;
    }

    function setLevel(uint256 id, uint8 lev) external {
        level[id] = lev;
    }

    function ownerOf(uint256 id) public view returns (address) {
        if (owners[id] == address(0)) revert MissingToken();
        return owners[id];
    }

    function approve(address spender, uint256 id) external {
        address owner = ownerOf(id);
        if (msg.sender != owner && !isApprovedForAll[owner][msg.sender]) revert Unauthorized();
        getApproved[id] = spender;
    }

    function setApprovalForAll(address operator, bool approved) external {
        isApprovedForAll[msg.sender][operator] = approved;
    }

    function transferFrom(address from, address to, uint256 id) public {
        address owner = ownerOf(id);
        if (
            owner != from
                || (msg.sender != owner && msg.sender != getApproved[id] && !isApprovedForAll[owner][msg.sender])
        ) {
            revert Unauthorized();
        }
        owners[id] = to;
        delete getApproved[id];
    }

    function safeTransferFrom(address from, address to, uint256 id) public {
        safeTransferFrom(from, to, id, "");
    }

    function safeTransferFrom(address from, address to, uint256 id, bytes memory data) public {
        transferFrom(from, to, id);
        if (
            to.code.length != 0
                && IERC721Receiver(to).onERC721Received(msg.sender, from, id, data)
                    != IERC721Receiver.onERC721Received.selector
        ) revert UnsafeRecipient();
    }
}

// The mock exposes the real staking selectors used by the vault. Rewards are
// explicitly funded per account so unit tests control income independently of
// time; the pinned fork below separately verifies live reward accrual.
contract BurrowTestStaking is ERC721Holder {
    BurrowTestToken public immutable token;
    mapping(address => uint256) public nftPower;
    mapping(address => uint256) public claimable;
    mapping(address => address) public claimRecipient;
    mapping(address => mapping(uint256 => address)) public depositor;
    mapping(address => mapping(uint256 => uint256)) private depositedPower;
    bool public overridePower;
    uint256 public powerOverride;
    error NotDepositor();

    constructor(BurrowTestToken t) {
        token = t;
    }

    function setPowerOverride(uint256 p) external {
        overridePower = true;
        powerOverride = p;
    }

    function deposit(address collection, uint256[] calldata tokenIds) external {
        for (uint256 i; i < tokenIds.length; i++) {
            uint256 id = tokenIds[i];
            BurrowTestNFT(collection).safeTransferFrom(msg.sender, address(this), id);
            uint256 p =
                overridePower ? powerOverride : this.basePower(collection, BurrowTestNFT(collection).level(id)) * 1e18;
            nftPower[msg.sender] += p;
            depositedPower[collection][id] = p;
            depositor[collection][id] = msg.sender;
        }
    }

    function withdraw(address collection, uint256[] calldata tokenIds) external {
        for (uint256 i; i < tokenIds.length; i++) {
            uint256 id = tokenIds[i];
            if (depositor[collection][id] != msg.sender) revert NotDepositor();
            nftPower[msg.sender] -= depositedPower[collection][id];
            delete depositor[collection][id];
            BurrowTestNFT(collection).safeTransferFrom(address(this), msg.sender, id);
        }
    }

    function fund(address account, uint256 reward) external {
        token.mint(address(this), reward);
        claimable[account] += reward;
    }

    /// Real staking: claim(account) pays that account's claim recipient; anyone may call.
    function claim(address account) external {
        uint256 amount = claimable[account];
        claimable[account] = 0;
        address to = claimRecipient[account] == address(0) ? account : claimRecipient[account];
        if (amount != 0) token.transfer(to, amount);
    }

    function setClaimRecipient(address recipient) external {
        claimRecipient[msg.sender] = recipient;
    }

    function accountPower(address account) external view returns (uint256) {
        return nftPower[account];
    }

    /// Sepolia: 1000 * 2.2^(level-1), zero for level 0 or above 10.
    function basePower(address, uint8 l) external pure returns (uint256 p) {
        if (l == 0 || l > 10) return 0;
        p = 1000; for (uint256 i = 1; i < l; ++i) p = p * 22 / 10;
    }
}



abstract contract BurrowVaultFixture is BurrowTestBase {
    BurrowTestToken internal token;
    BurrowTestNFT internal nft;
    BurrowTestStaking internal staking;
    BurrowValuer internal valuer;
    BurrowVaultLite internal vault;
    address internal alice;
    address internal bob;
    address internal lender;
    address internal liquidator;
    uint256 internal constant RATE = 1e10;

    function _setup(uint256 rate) internal {
        vm.warp(10 days);
        alice = addr("borrower alice");
        bob = addr("borrower bob");
        lender = addr("lender");
        liquidator = addr("liquidator");
        token = new BurrowTestToken();
        nft = new BurrowTestNFT();
        staking = new BurrowTestStaking(token);
        valuer = new BurrowValuer(address(this), address(nft), address(staking), 1e18, 1e15, 100e18, 6000);
        vault = new BurrowVaultLite(address(token), address(nft), address(staking), address(valuer), rate);
        _fund(lender, 1e30);
        _fund(alice, 1e30);
        _fund(bob, 1e30);
        _fund(liquidator, 1e30);
    }

    function _fund(address who, uint256 amount) internal {
        token.mint(who, amount);
        vm.prank(who);
        token.approve(address(vault), type(uint256).max);
    }

    function _seed(uint256 amount) internal {
        vm.prank(lender);
        vault.deposit(amount, 0);
    }

    function _open(address who, uint256 id, uint8 lev) internal {
        nft.mint(who, id, lev);
        vm.startPrank(who);
        nft.setApprovalForAll(address(vault), true);
        vault.openPosition(ids(id));
        vm.stopPrank();
    }

    function _borrow(address who, uint256 amount) internal {
        vm.prank(who);
        vault.borrow(amount);
    }
}

abstract contract BurrowSepoliaForkFixture is BurrowTestBase {
    address internal constant SQK = address(bytes20(hex"5501e1fa81be1c3f49225fa7668da0245d07db60"));
    address internal constant NFT = address(bytes20(hex"cb98349c134ab983da5bfd80527dfe2552bdb70f"));
    address internal constant STAKING = address(bytes20(hex"4b67b739dfd832f4eac67a7aa3bc244fb74cea4f"));
    address internal constant MANAGER = 0xE03A1074c86CFeDd5C142C4F04F1a1536e203543;
    address internal constant POSITIONS = 0x429ba70129df741B2Ca2a85BC3A2a3328e5c09b4;
    address internal constant PERMIT2 = 0x000000000022D473030F116dDEE9F6B43aC78BA3;

    function _fork() internal {
        string memory url = vm.envOr("SEPOLIA_RPC_URL", string(""));
        if (bytes(url).length == 0) {
            vm.skip(true);
            return;
        }
        vm.createSelectFork(url);   // latest: public RPCs keep no archive state
        assertEq(block.chainid, 11155111, "Sepolia chain");
    }

    function _liveVault() internal returns (BurrowVaultLite v, BurrowValuer valuer) {
        valuer = new BurrowValuer(address(this), NFT, STAKING, 1e18, 0.5e18, 2e18, 6000);
        v = new BurrowVaultLite(SQK, NFT, STAKING, address(valuer), 1e10);
    }
}
