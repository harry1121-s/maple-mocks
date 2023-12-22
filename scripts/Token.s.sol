pragma solidity 0.8.21;

import "forge-std/Script.sol";

import { myToken } from "../contracts/MyToken.sol";

contract TokenScript is Script {
    function setUp() public {}

    // function run() public {
    //     uint pKey = vm.envUint("DEV_PRIVATE_KEY");
    //     address account = vm.addr(pKey);
    //     console.log("Account: ", account);

    //     vm.startBroadcast(pKey);

    //     myToken token = new myToken("DEVNET TEST", "DTEST");
    //     token.mint(account,2e18);
    //     token.burn(account,1e18);
    //     vm.stopBroadcast();
    // }

     function run() public {
        uint pKey = vm.envUint("DEV_PRIVATE_KEY");
        address account = vm.addr(pKey);
        console.log("Account: ", account);

        vm.startBroadcast(pKey);

        myToken token = myToken(address(0xefc3635CCc710A04B49b6E2A85Ff3714f029A314));
        console.log("TOKEN balance: ", token.balanceOf(account));
        console.log("TOKEN name: ", token.name());

        vm.stopBroadcast();
    }
}