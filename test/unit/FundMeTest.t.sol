// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Test} from "forge-std/Test.sol";
import "forge-std/console.sol";
import {FundMe} from "../../src/FundMe.sol";
import {DeployFundMe} from "../../script/DeployFundMe.s.sol";

contract FundMeTest is Test {
    FundMe fundMe;

    address USER = makeAddr("user");
    uint256 constant SEND_VALUE = 0.1 ether; // 0.1 ETH
    uint256 constant STARTING_BALANCE = 10 ether; // 10 ETH
    uint256 constant GAS_PRICE = 1; // 1 Gwei for gas price

    function setUp() external {
        //fundMe = new FundMe(0x694AA1769357215DE4FAC081bf1f309aDC325306);
        DeployFundMe deployFundMe = new DeployFundMe();
        fundMe = deployFundMe.run();
        vm.deal(USER, STARTING_BALANCE); // Give USER 10 ETH
    }

    function testMinimumDollarIsFive() public view {
        assertEq(fundMe.MINIMUM_USD(), 5 * 10 ** 18, "Minimum USD should be 5");
    }

    function testOwnerIsMsgSender() public view {
        assertEq(fundMe.getOwner(), msg.sender, "Owner should be the message sender");
    }

    function testPriceFeedVersionIsAccurate() public view {
        uint256 version = fundMe.getVersion();
        assertEq(version, 4, "Price feed version should be 4");
    }

    function testFundFailswithoutEnoughETH() public {
        vm.expectRevert();
        fundMe.fund(); // Sending 1 ETH, which is less than the minimum of 5 USD
    }

    function testFundUpdatesFundedDataStructure() public {
        vm.prank(USER);
        fundMe.fund{value: SEND_VALUE}(); // Sending more than 5 USD worth of ETH
        uint256 amountFunded = fundMe.getAddressToAmountFunded(USER);
        assertEq(amountFunded, SEND_VALUE);
    }

    function testAddsFunderToArrayOfFunders() public {
        vm.prank(USER);
        fundMe.fund{value: SEND_VALUE}(); // Sending more than 5 USD worth of ETH
        address funder = fundMe.getFunder(0); // Get the first funder
        assertEq(funder, USER, "Funder should be the user who sent the funds");
    }

    modifier funded() {
        vm.prank(USER);
        fundMe.fund{value: SEND_VALUE}(); // USER funds the contract
        _;
    }

    function testOnlyOwnerCanWithdraw() public funded {
        vm.prank(USER);
        vm.expectRevert();
        fundMe.withdraw(); // USER tries to withdraw, should fail
    }

    function testWithDrawWithASingleFunder() public funded {
        uint256 startingOwnerBalance = fundMe.getOwner().balance;
        uint256 startingFundMeBalance = address(fundMe).balance;

        // uint256 gasStart = gasleft();
        //vm.txGasPrice(GAS_PRICE);
        vm.prank(msg.sender);
        fundMe.withdraw(); // Owner withdraws funds

        // uint256 gasEnd = gasleft();
        // uint256 gasUsed = (gasStart - gasEnd) * GAS_PRICE;
        // console.log(gasUsed);

        uint256 endingOwnerBalance = fundMe.getOwner().balance;
        uint256 endingFundMeBalance = address(fundMe).balance;

        assertEq(endingFundMeBalance, 0, "FundMe balance should be 0 after withdrawal");
        assertEq(
            startingFundMeBalance + startingOwnerBalance,
            endingOwnerBalance,
            "User balance should be increased by FundMe balance"
        );
    }

    function testWithdrawWithMultipleFunders() public funded {
        uint160 numberOfFunders = 10;
        uint160 startingFunderIndex = 1; // Start from 1 to avoid USER funding themselves

        for (uint160 i = startingFunderIndex; i < numberOfFunders; i++) {
            // address funder = makeAddr(string(abi.encodePacked("funder", i)));
            // vm.deal(funder, SEND_VALUE);
            // vm.prank(funder);
            hoax(address(i), SEND_VALUE);
            fundMe.fund{value: SEND_VALUE}();
        }

        uint256 startingOwnerBalance = fundMe.getOwner().balance;
        uint256 startingFundMeBalance = address(fundMe).balance;

        vm.startPrank(fundMe.getOwner());
        fundMe.withdraw(); // Owner withdraws funds
        vm.stopPrank();

        assert(address(fundMe).balance == 0);
        assert(startingFundMeBalance + startingOwnerBalance == fundMe.getOwner().balance);
    }

    function testWithdrawWithMultipleFundersCheaper() public funded {
        uint160 numberOfFunders = 10;
        uint160 startingFunderIndex = 1; // Start from 1 to avoid USER funding themselves

        for (uint160 i = startingFunderIndex; i < numberOfFunders; i++) {
            // address funder = makeAddr(string(abi.encodePacked("funder", i)));
            // vm.deal(funder, SEND_VALUE);
            // vm.prank(funder);
            hoax(address(i), SEND_VALUE);
            fundMe.fund{value: SEND_VALUE}();
        }

        uint256 startingOwnerBalance = fundMe.getOwner().balance;
        uint256 startingFundMeBalance = address(fundMe).balance;

        vm.startPrank(fundMe.getOwner());
        fundMe.cheaperWithdraw(); // Owner withdraws funds
        vm.stopPrank();

        assert(address(fundMe).balance == 0);
        assert(startingFundMeBalance + startingOwnerBalance == fundMe.getOwner().balance);
    }
}
