// SPDX-License-Identifier: MIT

pragma solidity 0.8.21;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
/**
 * @dev Modified Interface of the ERC20 standard as defined in the EIP.
 */

interface IERC20Helper is IERC20 {
    function mint(address _user, uint256 _amount) external;
    function burn(address _user, uint256 _amount) external;
    function decimals() external view returns (uint256);
}
