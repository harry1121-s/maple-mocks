pragma solidity 0.8.21;

import { Test, console } from "forge-std/Test.sol";
import { Pool } from "../contracts/Pool.sol";
import { myToken } from "../contracts/MyToken.sol";

contract testPool is Test {

    address public owner = vm.addr(123);
    address public user1 = vm.addr(456);
    address public user2 = vm.addr(789);

    Pool public pool;
    myToken public token;


    function setUp() public {

        vm.startPrank(owner);
        token = new myToken("TEST USDC", "TUSDC");
        pool = new Pool(address(token), "TUSDC CASH POOL", "TSUDC_CP");
        vm.stopPrank();

    }

    function test_deployment() external {
        assertEq(token.name(), "TEST USDC");
        assertEq(token.symbol(), "TUSDC");
        assertEq(pool.name(), "TUSDC CASH POOL");
        assertEq(pool.symbol(), "TSUDC_CP");
        assertEq(token.decimals(), 6);
    }

    function test_deposit() external {
        vm.prank(owner);
        token.mint(user1, 1e6*1e6);
        assertEq(token.balanceOf(user1), 1e6*1e6);

        vm.startPrank(user1);
        token.approve(address(pool), 1e12);
        pool.deposit(1e12, user1);
        vm.stopPrank();

        assertEq(token.balanceOf(address(pool)), 1e12);
        assertEq(pool.balanceOf(user1), 1e12);

        vm.warp(block.timestamp + 365 days);
        console.log(pool.totalAssets());
    }

    function test_multiple_deposits() external {

        vm.prank(owner);
        token.mint(user1, 2e6*1e6);
        assertEq(token.balanceOf(user1), 2e6*1e6);

        vm.startPrank(user1);
        token.approve(address(pool), 2e12);
        pool.deposit(1e12, user1);
        vm.stopPrank();

        assertEq(token.balanceOf(address(pool)), 1e12);
        assertEq(pool.balanceOf(user1), 1e12);

        vm.warp(block.timestamp + 365 days);

        console.log(pool.totalAssets());
        vm.startPrank(user1);
        pool.deposit(1e12, user1);
        vm.stopPrank();

        assertEq(token.balanceOf(address(pool)), 2e12);


    }

    function test_request_redeem() external {
        vm.prank(owner);
        token.mint(user1, 2e6*1e6);
        assertEq(token.balanceOf(user1), 2e6*1e6);

        vm.startPrank(user1);
        token.approve(address(pool), 2e12);
        pool.deposit(1e12, user1);
        vm.stopPrank();
        
        assertEq(pool.balanceOf(user1), 1e12);
        assertEq(pool.balanceOf(address(pool)), 0);

        vm.startPrank(user1);
        pool.approve(address(pool), 1e12);
        pool.requestRedeem(1e12, user1);

        assertEq(pool.balanceOf(user1), 0);
        assertEq(pool.balanceOf(address(pool)), 1e12);
        console.log(pool.getCurrentCycleId());
        console.log(pool.exitCycleId(user1));
        console.log(pool.lockedShares(user1));
        console.log(block.timestamp, pool.getWindowStart(pool.exitCycleId(user1)));
    }

    function test_redeem_fail() external {
        vm.prank(owner);
        token.mint(user1, 1e6*1e6);
        assertEq(token.balanceOf(user1), 1e6*1e6);

        vm.startPrank(user1);
        token.approve(address(pool), 1e12);
        pool.deposit(1e12, user1); //deposit 
        vm.stopPrank();

        vm.startPrank(user1);
        pool.approve(address(pool), 1e12);
        pool.requestRedeem(1e12, user1); //request redeem 

        vm.startPrank(user1);
        vm.expectRevert("WM:PE:NOT_IN_WINDOW");
        pool.redeem(1e12, user1, user1);
        vm.stopPrank();

        (uint256 windowStart, uint256 windowStop) = pool.getWindowAtId(pool.exitCycleId(user1));

        vm.warp(windowStop + 1);

        vm.startPrank(user1);
        vm.expectRevert("WM:PE:NOT_IN_WINDOW");
        pool.redeem(1e12, user1, user1);
        vm.stopPrank();

    }

    function test_redeem_pass() external {
        vm.prank(owner);
        token.mint(user1, 1e6*1e6);
        assertEq(token.balanceOf(user1), 1e6*1e6);

        vm.startPrank(user1);
        token.approve(address(pool), 1e12);
        pool.deposit(1e12, user1); //deposit 
        vm.stopPrank();

        vm.startPrank(user1);
        pool.approve(address(pool), 1e12);
        pool.requestRedeem(1e12, user1); //request redeem 

        (uint256 windowStart, uint256 windowStop) = pool.getWindowAtId(pool.exitCycleId(user1));

        vm.warp(windowStart + 10);

        vm.startPrank(user1);
        pool.redeem(1e12, user1, user1);
        vm.stopPrank();
    }
}