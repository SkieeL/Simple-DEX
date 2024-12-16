// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeCast.sol";

interface ISimpleDEX {
    function addLiquidity(uint256 amountA, uint256 amountB) external;
    function swapAforB(uint256 amountAIn) external;
    function swapBforA(uint256 amountBIn) external;
    function removeLiquidity(uint256 amountA, uint256 amountB) external;
    function getPrice(address _token) external view returns (uint256);
}

contract SimpleDEX is ISimpleDEX {
    IERC20 private tokenA;
    IERC20 private tokenB;
    address private owner;

    event LiquidityAdded(uint256 tokenA, uint256 tokenB);
    event LiquidityRemoved(uint256 tokenA, uint256 tokenB);
    event TokensSwapped(address indexed user, int256 amountA, int256 amountB);

    constructor(address _tokenA, address _tokenB) {
        tokenA = IERC20(_tokenA);
        tokenB = IERC20(_tokenB);
        owner = msg.sender;
    }

    modifier onlyOwner() { 
        require(msg.sender == owner, "Permiso denegado");
        _;
    }

    modifier verifyTokenAFunds(uint256 amount, address user) {
        require(tokenA.balanceOf(user) >= amount, "Fondos insuficientes del TokenA");
        _;
    }

    modifier verifyTokenBFunds(uint256 amount, address user) {
        require(tokenB.balanceOf(user) >= amount, "Fondos insuficientes del TokenB");
        _;
    }

    modifier verifyPoolNotEmpty() {
        uint256 poolA = tokenA.balanceOf(address(this));
        uint256 poolB = tokenB.balanceOf(address(this));

        require(poolA != 0 && poolB != 0, "El DEX no posee liquidez");
        _;
    }

    function addLiquidity(uint256 amountA, uint256 amountB) external 
    onlyOwner 
    verifyTokenAFunds(amountA, msg.sender)
    verifyTokenBFunds(amountB, msg.sender) { 
        require(getPrice(address(tokenA)) * amountA == getPrice(address(tokenB)) * amountB, "Los montos deben ser equivalentes");
        require(tokenA.transferFrom(msg.sender, address(this), amountA), "Error al depositar TokenA");
        require(tokenB.transferFrom(msg.sender, address(this), amountB), "Error al depositar TokenB");

        emit LiquidityAdded(amountA, amountB);
    }

    function swapAforB(uint256 amountAIn) external verifyTokenAFunds(amountAIn, msg.sender) verifyPoolNotEmpty {
        uint256 amountB = getAmountToBuy(tokenA, amountAIn, tokenB);

        require(tokenB.balanceOf(address(this)) >= amountB, "Liquidez insuficiente del TokenB");
        require(tokenA.transferFrom(msg.sender, address(this), amountAIn), "Error al recibir TokenA");
        require(tokenB.transfer(address(this), amountB), "Error al enviar TokenB");

        emit TokensSwapped(msg.sender, SafeCast.toInt256(amountAIn) * -1, SafeCast.toInt256(amountB));
    }

    function swapBforA(uint256 amountBIn) external verifyTokenBFunds(amountBIn, msg.sender) verifyPoolNotEmpty {
        uint256 amountA = getAmountToBuy(tokenB, amountBIn, tokenA);

        require(tokenA.balanceOf(address(this)) >= amountA, "Liquidez insuficiente del TokenA");
        require(tokenB.transferFrom(msg.sender, address(this), amountBIn), "Error al recibir TokenB");
        require(tokenA.transfer(address(this), amountA), "Error al enviar TokenA");

        emit TokensSwapped(msg.sender, SafeCast.toInt256(amountA), SafeCast.toInt256(amountBIn) * -1);
    }

    function removeLiquidity(uint256 amountA, uint256 amountB) external 
    onlyOwner 
    verifyTokenAFunds(amountA, address(this)) 
    verifyTokenBFunds(amountB, address(this)) {
        require(tokenA.transfer(msg.sender, amountA), "Error al retirar TokenA");
        require(tokenB.transfer(msg.sender, amountB), "Error al retirar TokenB");

        emit LiquidityRemoved(amountA, amountB);
    }

    function getPrice(address _token) public view returns (uint256) {
        require(_token != address(tokenA) && _token != address(tokenB), "Address del token invalida");
        
        uint256 poolA = tokenA.balanceOf(address(this));
        uint256 poolB = tokenB.balanceOf(address(this));

        if (poolA == 0 || poolB == 0)
            return 0;

        return (_token == address(tokenA)) ? potency(poolB) / poolA : potency(poolA) / poolB;
    }

    function getAmountToBuy(IERC20 tokenToSell, uint256 amountToSell, IERC20 tokenToBuy) private view returns (uint256) {
        uint256 tokenToSellPool = tokenToSell.balanceOf(address(this));
        uint256 tokenToBuyPool = tokenToBuy.balanceOf(address(this));

        // (X + dX) * (Y - dY) = X * Y
        // dY = Y - (X * Y) / (X + dX) 
        return tokenToBuyPool - (tokenToSellPool * tokenToBuyPool) / (tokenToSellPool + amountToSell);
    }

    function potency(uint256 amount) private pure returns (uint256) {
        return amount * 10 ** 18;
    }
}