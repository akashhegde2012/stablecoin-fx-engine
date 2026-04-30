// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title LPToken
 *     @notice ERC-20 token representing a liquidity provider's share in an FXPool.
 *          Minted on deposit and burned on withdrawal.  The owner is always the
 *          associated FXPool; no other address can mint or burn.
 *
 *          Naming convention:  "Wrapped MYR" / symbol "wMYR" for the MYR pool,
 *          "Wrapped SGD" / "wSGD" for the SGD pool, etc.
 */
contract LPToken is ERC20, Ownable {
    constructor(string memory name_, string memory symbol_, address pool_) ERC20(name_, symbol_) Ownable(pool_) {}

    /// @notice Mint `amount` LP tokens to `to`. Only the owning pool can call this.
    function mint(address to, uint256 amount) external onlyOwner {
        _mint(to, amount);
    }

    /// @notice Burn `amount` LP tokens from `from`. Only the owning pool can call this.
    function burn(address from, uint256 amount) external onlyOwner {
        _burn(from, amount);
    }
}
