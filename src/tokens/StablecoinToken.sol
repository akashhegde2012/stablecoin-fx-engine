// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title StablecoinToken
 *  @notice Base ERC-20 stablecoin with owner-controlled minting.
 *          Each currency (MYR, SGD, IDRX, USDT) inherits from this.
 */
abstract contract StablecoinToken is ERC20, Ownable {
    uint8 private immutable _decimals;

    constructor(string memory name_, string memory symbol_, uint8 decimals_, address owner_)
        ERC20(name_, symbol_)
        Ownable(owner_)
    {
        _decimals = decimals_;
    }

    function decimals() public view override returns (uint8) {
        return _decimals;
    }

    /// @notice Mint tokens. Only callable by the owner (e.g. the deployer / bridge contract).
    function mint(address to, uint256 amount) external onlyOwner {
        _mint(to, amount);
    }

    /// @notice Burn caller's own tokens.
    function burn(uint256 amount) external {
        _burn(msg.sender, amount);
    }
}
