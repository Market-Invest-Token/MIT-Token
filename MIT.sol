// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

interface IUniswapV2Router {
    function factory() external pure returns (address);
    function WETH() external pure returns (address);
}

interface IUniswapV2Factory {
    function createPair(address tokenA, address tokenB) external returns (address);
}

contract MarketInvestToken {
    // =================== INFORMAÇÕES BÁSICAS ===================
    string public constant name = "Market Invest Token";
    string public constant symbol = "MIT";
    uint8 public constant decimals = 18;
    uint256 public totalSupply = 50_000_000_000 * 10**decimals;

    // =================== SALDOS E PERMISSÕES ===================
    mapping(address => uint256) private balances;
    mapping(address => mapping(address => uint256)) private allowances;

    // =================== CONFIGURAÇÕES DE TAXAS ===================
    uint256 public constant transferFee = 30; // 0.3%
    uint256 public constant tradeFee = 50;    // 0.5%
    uint256 public constant burnFee = 20;     // 0.2%
    address public constant feeWallet = 0x77165FaC7BeF09d3D6a4e7f217EE3784D857F8Ef;

    // =================== LIQUIDEZ E DESBLOQUEIO ===================
    address public liquidityPool;
    address public immutable owner;
    uint256 public circulatingSupply;
    uint256 public lockedSupply = 34_000_000_000 * 10**decimals;

    // =================== CONTROLE DO TEMPO DE LIQUIDEZ ===================
    uint256 public cycleStart;
    bool public isLiquidityUnlocked;

    // =================== EVENTOS ===================
    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);
    event TokensUnlocked(uint256 amount);

    // =================== CONSTRUTOR ===================
    constructor() {
        owner = msg.sender;

        // DISTRIBUIÇÃO INICIAL
        _transferNoFee(address(0), msg.sender, 5_000_000_000 * 10**decimals); // Criador
        _transferNoFee(address(0), msg.sender, 1_000_000_000 * 10**decimals); // Investidor
        _transferNoFee(address(0), msg.sender, 10_000_000_000 * 10**decimals); // Liquidez

        circulatingSupply = 16_000_000_000 * 10**decimals;
        cycleStart = block.timestamp;
    }

    // =================== FUNÇÕES PADRÃO ERC20 ===================
    function balanceOf(address account) public view returns (uint256) {
        return balances[account];
    }

    function allowance(address owner_, address spender) public view returns (uint256) {
        return allowances[owner_][spender];
    }

    function approve(address spender, uint256 amount) public returns (bool) {
        allowances[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }

    // TRANSFERÊNCIA PADRÃO COM TAXAS
    function transfer(address to, uint256 amount) public returns (bool) {
        _transfer(msg.sender, to, amount);
        return true;
    }

    // TRANSFERÊNCIA USANDO ALLOWANCE
    function transferFrom(address from, address to, uint256 amount) public returns (bool) {
        require(allowances[from][msg.sender] >= amount, "Allowance exceeded");
        allowances[from][msg.sender] -= amount;
        _transfer(from, to, amount);
        return true;
    }

    // =================== TRANSFERÊNCIA COM LÓGICA DE TAXAS ===================
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
        totalSupply -= burnAmount;

        emit Transfer(from, to, transferAmount);
        emit Transfer(from, feeWallet, feeAmount);
        emit Transfer(from, address(0), burnAmount);

        _tryUnlockMore();
        _checkLiquidityCycle();
    }

    // TRANSFERÊNCIA SEM TAXA (apenas no deploy inicial)
    function _transferNoFee(address from, address to, uint256 amount) private {
        balances[to] += amount;
        emit Transfer(from, to, amount);
    }

    // =================== LIBERAÇÃO AUTOMÁTICA DE TOKENS ===================
    function _tryUnlockMore() private {
        if (lockedSupply == 0) return;

        uint256 expectedInMarket = circulatingSupply;
        uint256 totalHeld = balances[owner] + balances[feeWallet];

        // Verifica se 90% dos tokens circulantes já foram comprados
        if (totalHeld <= expectedInMarket * 10 / 100) {
            uint256 unlockAmount = 3_000_000_000 * 10**decimals;
            if (unlockAmount > lockedSupply) {
                unlockAmount = lockedSupply;
            }

            balances[owner] += unlockAmount;
            circulatingSupply += unlockAmount;
            lockedSupply -= unlockAmount;

            emit TokensUnlocked(unlockAmount);
        }
    }

    // =================== CICLO DE LIQUIDEZ AUTOMÁTICO ===================
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

    // =================== CRIAÇÃO DE PAR NA DEX (EXTERNO) ===================
    function setLiquidityPool(address _lp) external {
        require(msg.sender == owner && liquidityPool == address(0), "Liquidity already set or not authorized");

        liquidityPool = _lp;
    }

    // =================== BLOQUEIO DE MODIFICAÇÕES ===================
    // Nenhuma função que permita alterar taxas, mint, burn, ou ownership
}
