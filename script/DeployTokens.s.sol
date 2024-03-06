pragma solidity 0.8.21;

import "forge-std/Script.sol";
import "forge-std/Test.sol";

import { MockToken } from "../contracts/MockToken.sol";

contract DeployTokens is Script, Test {

     function run() public {
        uint pKey = vm.envUint("DEV_PRIVATE_KEY");

        vm.startBroadcast(pKey);

        MockToken usdc = new MockToken("TEST USDC", "TUSDC", 6);
        MockToken usdt = new MockToken("TEST USDT", "TUSDT", 6);
        MockToken dai = new MockToken("TEST DAI", "TDAI", 18);

        console.log("usdc Address: ", address(usdc));
        console.log("usdt Address: ", address(usdt));
        console.log("dai Address: ", address(dai));

        assertEq(usdc.decimals(), 6);
        assertEq(usdt.decimals(), 6);
        assertEq(dai.decimals(), 18);
        vm.stopBroadcast();
    }
}