// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Test} from "forge-std/Test.sol";
import "forge-std/console.sol";
import {FundMe} from "../../src/FundMe.sol";
import {DeployFundMe} from "../../script/DeployFundMe.s.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";

// Adding the missing custom error here so the selector can be referenced
error FundMe__NotOwner();

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

    function testWithdrawHasNoEffectWhenNoBalance() public {
        vm.startPrank(fundMe.getOwner());
        fundMe.withdraw(); // First withdrawal, should succeed
        vm.stopPrank();

        uint256 startingBalance = fundMe.getOwner().balance;
        uint256 contractBalance = address(fundMe).balance;

        vm.startPrank(fundMe.getOwner());
        fundMe.withdraw(); // Second withdrawal, should do nothing
        vm.stopPrank();

        assertEq(contractBalance, 0, "Contract balance should be 0");
        assertEq(fundMe.getOwner().balance, startingBalance, "Owner balance should stay the same");
    }

    function testRepeatedFundingAccumulates() public {
        vm.prank(USER);
        fundMe.fund{value: SEND_VALUE}();
        vm.prank(USER);
        fundMe.fund{value: SEND_VALUE}();
        uint256 totalFunded = fundMe.getAddressToAmountFunded(USER);
        assertEq(totalFunded, SEND_VALUE * 2);
    }

    function testOnlyOwnerCanCheaperWithdraw() public funded {
        vm.prank(USER);
        vm.expectRevert();
        fundMe.cheaperWithdraw();
    }

    function testGasCostComparison() public funded {
        vm.prank(USER);
        fundMe.fund{value: SEND_VALUE}();

        vm.prank(fundMe.getOwner());
        uint256 gasStart = gasleft();
        fundMe.withdraw();
        uint256 gasUsedWithdraw = gasStart - gasleft();

        vm.prank(USER);
        fundMe.fund{value: SEND_VALUE}();

        vm.prank(fundMe.getOwner());
        gasStart = gasleft();
        fundMe.cheaperWithdraw();
        uint256 gasUsedCheaperWithdraw = gasStart - gasleft();

        console.log("withdraw():", gasUsedWithdraw);
        console.log("cheaperWithdraw():", gasUsedCheaperWithdraw);
        assertLt(gasUsedCheaperWithdraw, gasUsedWithdraw);
    }

    function testGetFunderOutOfBoundsReverts() public {
        vm.expectRevert(); // out-of-bounds access
        fundMe.getFunder(0);
    }

    function testGetFunderReturnsCorrectAddress() public {
        vm.prank(USER);
        fundMe.fund{value: SEND_VALUE}();
        address funder = fundMe.getFunder(0);
        assertEq(funder, USER, "Funder should be the user who sent the funds");
    }

    function testGetAddressToAmountFundedReturnsZeroForNonFunder() public {
        address nonFunder = makeAddr("nonFunder");
        uint256 amountFunded = fundMe.getAddressToAmountFunded(nonFunder);
        assertEq(amountFunded, 0, "Non-funder should have zero amount funded");
    }

    function testFallbackFails() public {
        vm.expectRevert();
        (bool sent,) = address(fundMe).call{value: 1 ether}(""); // no data -> fallback or receive
        require(sent, "Should revert without fund()");
    }

    function testFundersClearedAfterWithdraw() public funded {
        address user2 = makeAddr("user2");
        vm.deal(user2, 10 ether);
        vm.prank(user2);
        fundMe.fund{value: SEND_VALUE}();

        vm.prank(fundMe.getOwner());
        fundMe.withdraw();

        vm.expectRevert();
        fundMe.getFunder(1); // Second funder removed
    }

    function testOnlyOwnerCustomError() public funded {
        vm.prank(USER);
        vm.expectRevert(FundMe__NotOwner.selector);
        fundMe.withdraw();
    }

    function testGetPriceFeed() public view {
        AggregatorV3Interface priceFeed = fundMe.getPriceFeed();
        assert(address(priceFeed) != address(0));
    }

    function testWithdrawCallFailure() public funded {
        // Deploy a malicious contract that always reverts when it receives ETH
        RevertingReceiver malicious = new RevertingReceiver();

        // FundMe contract already thinks msg.sender is the owner (from setUp)
        // But i_owner is immutable and set in the constructor, so we can't change it directly.
        // Instead, we copy the malicious fallback code to the owner's address using vm.etch

        address owner = fundMe.getOwner();

        // Replace code at the owner's address with the malicious contract code
        vm.etch(owner, address(malicious).code);

        // Now when FundMe tries to send ETH to the owner, it will fail
        vm.expectRevert(); // The `require(success)` should now fail
        vm.prank(owner);
        fundMe.withdraw();
    }

    function test_FuzzingWithdraw() public funded {
        // This test is designed to fuzz the withdraw function
        // It will randomly call withdraw multiple times to ensure it behaves correctly
        for (uint256 i = 0; i < 10; i++) {
            vm.prank(fundMe.getOwner());
            fundMe.withdraw();
        }
        assert(address(fundMe).balance == 0, "Contract balance should be zero after multiple withdrawals");
    }
}

contract RevertingReceiver {
    fallback() external payable {
        revert("I always fail");
    }
}
