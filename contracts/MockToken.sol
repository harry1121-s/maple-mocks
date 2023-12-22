pragma solidity 0.8.21;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
contract MockToken is ERC20, Ownable{
    uint8 decimal;
    constructor(string memory name_, string memory symbol_, uint8 decimals_)
        ERC20(name_, symbol_) Ownable(msg.sender)
    {
        decimal = decimals_;
    }

    function mint(address to, uint256 amount) external{
        _mint(to, amount);
    }

    function burn(address from, uint256 amount) external{
        _burn(from, amount);
    }

    function decimals() public view virtual override returns (uint8) {
        return decimal;
    }
}
