pragma solidity 0.8.21;

import "forge-std/Script.sol";
import "forge-std/Test.sol";

import { MockToken } from "../contracts/MockToken.sol";

contract MintTokens is Script, Test {

    address receiver = address(0xCD72000B6e490D20565311f6CFEB1F84Bc475A9d);
    function run() public {
        uint pKey = vm.envUint("DEV_PRIVATE_KEY");

        vm.startBroadcast(pKey);

        MockToken usdc = MockToken(0xC6497dD3891707C8D27097f5d753881C35491D85);
        MockToken usdt = MockToken(0xEcFd9c649bbf2C7B19bcE4157e57AF579254A1c2);
        MockToken dai = MockToken(0xa1818fAF5D6bB6aD2614CfF4a6b346eda31B77c4);

        console.log("usdc Address: ", address(usdc));
        console.log("usdt Address: ", address(usdt));
        console.log("dai Address: ", address(dai));

        assertEq(usdc.decimals(), 6);
        assertEq(usdt.decimals(), 6);
        assertEq(dai.decimals(), 18);

        usdc.mint(receiver, 1e6*1e6);
        usdt.mint(receiver, 1e6*1e6);
        dai.mint(receiver, 1e6*1e18);

        assertEq(usdc.balanceOf(receiver), 1e12);
        assertEq(usdt.balanceOf(receiver), 1e12);
        assertEq(dai.balanceOf(receiver), 1e24);
        vm.stopBroadcast();
    }
}

