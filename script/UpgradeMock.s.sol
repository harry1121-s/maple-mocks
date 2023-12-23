pragma solidity 0.8.21;

import "forge-std/Script.sol";
import { Test, console } from "forge-std/Test.sol";
import {
    TransparentUpgradeableProxy,
    ITransparentUpgradeableProxy
} from "../contracts/upgradeable/TransparentUpgradeableProxy.sol";
import { ProxyAdmin } from "../contracts/upgradeable/ProxyAdmin.sol";
import { Pool } from "../contracts/Pool.sol";

contract UpgradeMock is Script, Test {
    Pool poolV2;
    ProxyAdmin proxyAdmin;

     function run() public {
        uint pKey = vm.envUint("DEV_PRIVATE_KEY");
        vm.startBroadcast(pKey);
        proxyAdmin = ProxyAdmin(0xee56dDA84d536533119d7757d7b7eC49b924aCA2);
        poolV2 = new Pool();
        bytes memory data = abi.encodeCall(poolV2.initialize,(2));
        proxyAdmin.upgradeAndCall(ITransparentUpgradeableProxy(0x5F837a7aA34f0c26daFC17A3e230f6D5EA9B43b2), address(poolV2), data);
        assertEq(Pool(0x5F837a7aA34f0c26daFC17A3e230f6D5EA9B43b2).ver(), 2);
        vm.stopBroadcast();
    }
}