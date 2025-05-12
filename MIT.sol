// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

interface IUniswapV2Router {
    function factory() external pure returns (address);
    function WETH() external pure returns (address);
}

interface IUniswapV2Factory {
    function createPair(address tokenA, address tokenB) external returns (address);
}

interface IERC20 {
    function totalSupply() external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
    function transfer(address to, uint256 amount) external returns (bool);
    function allowance(address owner, address spender) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);
}

contract MarketInvestToken is IERC20 {
    string private constant _name = "Market Invest Token";
    string private constant _symbol = "MIT";
    uint8 private constant _decimals = 18;
    uint256 private _totalSupply = 50_000_000_000 * 10**_decimals;

    mapping(address => uint256) private balances;
    mapping(address => mapping(address => uint256)) private allowances;

    uint256 public constant transferFee = 30;
    uint256 public constant tradeFee = 50;
    uint256 public constant burnFee = 5; // 0.05%
    address public constant feeWallet = 0x77165FaC7BeF09d3D6a4e7f217EE3784D857F8Ef;

    address public liquidityPool;
    address public immutable owner;
    uint256 public circulatingSupply;
    uint256 public lockedSupply = 34_000_000_000 * 10**_decimals;

    uint256 public cycleStart;
    bool public isLiquidityUnlocked;

    constructor() {
        owner = msg.sender;

        _transferNoFee(address(0), msg.sender, 5_000_000_000 * 10**_decimals);
        _transferNoFee(address(0), msg.sender, 1_000_000_000 * 10**_decimals);
        _transferNoFee(address(0), msg.sender, 10_000_000_000 * 10**_decimals);

        circulatingSupply = 16_000_000_000 * 10**_decimals;
        cycleStart = block.timestamp;
    }

    function name() public pure returns (string memory) {
        return _name;
    }

    function symbol() public pure returns (string memory) {
        return _symbol;
    }

    function decimals() public pure returns (uint8) {
        return _decimals;
    }

    function totalSupply() public view override returns (uint256) {
        return _totalSupply;
    }

    function balanceOf(address account) public view override returns (uint256) {
        return balances[account];
    }

    function allowance(address owner_, address spender) public view override returns (uint256) {
        return allowances[owner_][spender];
    }

    function approve(address spender, uint256 amount) public override returns (bool) {
        allowances[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }

    function transfer(address to, uint256 amount) public override returns (bool) {
        _transfer(msg.sender, to, amount);
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) public override returns (bool) {
        require(allowances[from][msg.sender] >= amount, "Allowance exceeded");
        allowances[from][msg.sender] -= amount;
        _transfer(from, to, amount);
        return true;
    }

    function _transfer(address from, address to, uint256 amount) private {
        require(balances[from] >= amount, "Saldo insuficiente");

        bool isTrade = (from == liquidityPool || to == liquidityPool);
        uint256 fee = isTrade ? tradeFee : transferFee;

        uint256 feeAmount = (amount * fee) / 10000;
        uint256 burnAmount = (amount * burnFee) / 10000;
        uint256 transferAmount = amount - feeAmount - burnAmount;

        balances[from] -= amount;
        balances[to] += transferAmount;
        balances[feeWallet] += feeAmount;
        _totalSupply -= burnAmount;

        emit Transfer(from, to, transferAmount);
        emit Transfer(from, feeWallet, feeAmount);
        emit Transfer(from, address(0), burnAmount);

        _tryUnlockMore();
        _checkLiquidityCycle();
    }

    function _transferNoFee(address from, address to, uint256 amount) private {
        balances[to] += amount;
        emit Transfer(from, to, amount);
    }

    function _tryUnlockMore() private {
        if (lockedSupply == 0) return;

        uint256 expectedInMarket = circulatingSupply;
        uint256 totalHeld = balances[owner] + balances[feeWallet];

        if (totalHeld <= expectedInMarket * 10 / 100) {
            uint256 unlockAmount = 3_000_000_000 * 10**_decimals;
            if (unlockAmount > lockedSupply) {
                unlockAmount = lockedSupply;
            }

            balances[owner] += unlockAmount;
            circulatingSupply += unlockAmount;
            lockedSupply -= unlockAmount;

            emit Transfer(address(0), owner, unlockAmount);
        }
    }

    function _checkLiquidityCycle() private {
        uint256 elapsed = block.timestamp - cycleStart;

        if (elapsed >= 28 days) {
            cycleStart = block.timestamp;
            isLiquidityUnlocked = false;
        } else if (elapsed >= 21 days) {
            isLiquidityUnlocked = true;
        }
    }

    function isLiquidityOpen() public view returns (bool) {
        return isLiquidityUnlocked;
    }

    function setLiquidityPool(address _lp) external {
        require(msg.sender == owner && liquidityPool == address(0), "Liquidity already set or not authorized");
        liquidityPool = _lp;
    }
}
