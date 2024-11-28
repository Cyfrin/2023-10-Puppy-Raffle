// SPDX-License-Identifier: MIT
pragma solidity ^0.7.6;
pragma experimental ABIEncoderV2;

import {Test, console} from "forge-std/Test.sol";
import {PuppyRaffle} from "../src/PuppyRaffle.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";

contract PuppyRaffleTest is StdInvariant, Test {
    PuppyRaffle puppyRaffle;
    uint256 entranceFee = 1e18;
    address playerOne = address(1);
    address playerTwo = address(2);
    address playerThree = address(3);
    address playerFour = address(4);
    address playerFive = address(5);
    address playerSix = address(6);
    address feeAddress = address(99);
    uint256 duration = 1 days;

    function setUp() public {
        puppyRaffle = new PuppyRaffle(entranceFee, feeAddress, duration);
    }

    //////////////////////
    /// EnterRaffle    ///
    /////////////////////

    function testCanEnterRaffle() public {
        address[] memory players = new address[](1);
        players[0] = playerOne;
        puppyRaffle.enterRaffle{value: entranceFee}(players);
        assertEq(puppyRaffle.players(0), playerOne);
    }

    function testCantEnterWithoutPaying() public {
        address[] memory players = new address[](1);
        players[0] = playerOne;
        vm.expectRevert("PuppyRaffle: Must send enough to enter raffle");
        puppyRaffle.enterRaffle(players);
    }

    function testCanEnterRaffleMany() public {
        address[] memory players = new address[](2);
        players[0] = playerOne;
        players[1] = playerTwo;
        puppyRaffle.enterRaffle{value: entranceFee * 2}(players);
        assertEq(puppyRaffle.players(0), playerOne);
        assertEq(puppyRaffle.players(1), playerTwo);
    }

    function testCantEnterWithoutPayingMultiple() public {
        address[] memory players = new address[](2);
        players[0] = playerOne;
        players[1] = playerTwo;
        vm.expectRevert("PuppyRaffle: Must send enough to enter raffle");
        puppyRaffle.enterRaffle{value: entranceFee}(players);
    }

    function testCantEnterWithDuplicatePlayers() public {
        address[] memory players = new address[](2);
        players[0] = playerOne;
        players[1] = playerOne;
        vm.expectRevert("PuppyRaffle: Duplicate player");
        puppyRaffle.enterRaffle{value: entranceFee * 2}(players);
    }

    function testCantEnterWithDuplicatePlayersMany() public {
        address[] memory players = new address[](3);
        players[0] = playerOne;
        players[1] = playerTwo;
        players[2] = playerOne;
        vm.expectRevert("PuppyRaffle: Duplicate player");
        puppyRaffle.enterRaffle{value: entranceFee * 3}(players);
    }

    //////////////////////
    /// Refund         ///
    /////////////////////
    modifier playerEntered() {
        address[] memory players = new address[](1);
        players[0] = playerOne;
        puppyRaffle.enterRaffle{value: entranceFee}(players);
        _;
    }

    function testCanGetRefund() public playerEntered {
        uint256 balanceBefore = address(playerOne).balance;
        uint256 indexOfPlayer = puppyRaffle.getActivePlayerIndex(playerOne);

        vm.prank(playerOne);
        puppyRaffle.refund(indexOfPlayer);

        assertEq(address(playerOne).balance, balanceBefore + entranceFee);
    }

    function testGettingRefundRemovesThemFromArray() public playerEntered {
        uint256 indexOfPlayer = puppyRaffle.getActivePlayerIndex(playerOne);

        vm.prank(playerOne);
        puppyRaffle.refund(indexOfPlayer);

        assertEq(puppyRaffle.players(0), address(0));
    }

    function testOnlyPlayerCanRefundThemself() public playerEntered {
        uint256 indexOfPlayer = puppyRaffle.getActivePlayerIndex(playerOne);
        vm.expectRevert("PuppyRaffle: Only the player can refund");
        vm.prank(playerTwo);
        puppyRaffle.refund(indexOfPlayer);
    }

    //////////////////////
    /// getActivePlayerIndex         ///
    /////////////////////
    function testGetActivePlayerIndexManyPlayers() public {
        address[] memory players = new address[](2);
        players[0] = playerOne;
        players[1] = playerTwo;
        puppyRaffle.enterRaffle{value: entranceFee * 2}(players);

        assertEq(puppyRaffle.getActivePlayerIndex(playerOne), 0);
        assertEq(puppyRaffle.getActivePlayerIndex(playerTwo), 1);
    }

    //////////////////////
    /// selectWinner         ///
    /////////////////////
    modifier playersEntered() {
        address[] memory players = new address[](4);
        players[0] = playerOne;
        players[1] = playerTwo;
        players[2] = playerThree;
        players[3] = playerFour;
        puppyRaffle.enterRaffle{value: entranceFee * 4}(players);
        _;
    }

    function testCantSelectWinnerBeforeRaffleEnds() public playersEntered {
        vm.expectRevert("PuppyRaffle: Raffle not over");
        puppyRaffle.selectWinner();
    }

    function testCantSelectWinnerWithFewerThanFourPlayers() public {
        address[] memory players = new address[](3);
        players[0] = playerOne;
        players[1] = playerTwo;
        players[2] = address(3);
        puppyRaffle.enterRaffle{value: entranceFee * 3}(players);

        vm.warp(block.timestamp + duration + 1);
        vm.roll(block.number + 1);

        vm.expectRevert("PuppyRaffle: Need at least 4 players");
        puppyRaffle.selectWinner();
    }

    function testSelectWinner() public playersEntered {
        vm.warp(block.timestamp + duration + 1);
        vm.roll(block.number + 1);

        puppyRaffle.selectWinner();
        assertEq(puppyRaffle.previousWinner(), playerFour);
    }

    function testSelectWinnerGetsPaid() public playersEntered {
        uint256 balanceBefore = address(playerFour).balance;

        vm.warp(block.timestamp + duration + 1);
        vm.roll(block.number + 1);

        uint256 expectedPayout = (((entranceFee * 4) * 80) / 100);

        puppyRaffle.selectWinner();
        assertEq(address(playerFour).balance, balanceBefore + expectedPayout);
    }

    function testSelectWinnerGetsAPuppy() public playersEntered {
        vm.warp(block.timestamp + duration + 1);
        vm.roll(block.number + 1);

        puppyRaffle.selectWinner();
        assertEq(puppyRaffle.balanceOf(playerFour), 1);
    }

    function testPuppyUriIsRight() public playersEntered {
        vm.warp(block.timestamp + duration + 1);
        vm.roll(block.number + 1);

        string
            memory expectedTokenUri = "data:application/json;base64,eyJuYW1lIjoiUHVwcHkgUmFmZmxlIiwgImRlc2NyaXB0aW9uIjoiQW4gYWRvcmFibGUgcHVwcHkhIiwgImF0dHJpYnV0ZXMiOiBbeyJ0cmFpdF90eXBlIjogInJhcml0eSIsICJ2YWx1ZSI6IGNvbW1vbn1dLCAiaW1hZ2UiOiJpcGZzOi8vUW1Tc1lSeDNMcERBYjFHWlFtN3paMUF1SFpqZmJQa0Q2SjdzOXI0MXh1MW1mOCJ9";

        puppyRaffle.selectWinner();
        assertEq(puppyRaffle.tokenURI(0), expectedTokenUri);
    }

    //////////////////////
    /// withdrawFees         ///
    /////////////////////
    function testCantWithdrawFeesIfPlayersActive() public playersEntered {
        vm.expectRevert("PuppyRaffle: There are currently players active!");
        puppyRaffle.withdrawFees();
    }

    function testWithdrawFees() public playersEntered {
        vm.warp(block.timestamp + duration + 1);
        vm.roll(block.number + 1);

        uint256 expectedPrizeAmount = ((entranceFee * 4) * 20) / 100;

        puppyRaffle.selectWinner();
        puppyRaffle.withdrawFees();
        assertEq(address(feeAddress).balance, expectedPrizeAmount);
    }

    function testDenialOfService() public {
        address warmUpAddress = makeAddr("warmUp");

        address[] memory players = new address[](1);
        players[0] = warmUpAddress;
        puppyRaffle.enterRaffle{value: entranceFee}(players);

        uint256 gasStartB = gasleft();
        address[] memory playersB = new address[](1);
        playersB[0] = playerOne;
        puppyRaffle.enterRaffle{value: entranceFee}(playersB);
        uint256 gasCostB = gasStartB - gasleft();

        uint256 gasStartC = gasleft();
        address[] memory playersC = new address[](1);
        playersC[0] = playerTwo;
        puppyRaffle.enterRaffle{value: entranceFee}(playersC);
        uint256 gasCostC = gasStartC - gasleft();

        uint256 gasStartD = gasleft();
        address[] memory playersD = new address[](1);
        playersD[0] = playerThree;
        puppyRaffle.enterRaffle{value: entranceFee}(playersD);
        uint256 gasCostD = gasStartD - gasleft();

        // The gas cost will just keep rising, making it harder and harder for new people to enter!
        assert(gasCostD > gasCostC);
        assert(gasCostC > gasCostB);
    }

    function testRefundedWinnerCantReceiveFunds() public {
        address[] memory newPlayers = new address[](4);
        newPlayers[0] = playerOne;
        newPlayers[1] = playerTwo;
        newPlayers[2] = playerThree;
        newPlayers[3] = playerFour;

        //all four players enter raffle
        puppyRaffle.enterRaffle{value: entranceFee * 4}(newPlayers);

        //Refund all players
        vm.prank(playerOne);
        puppyRaffle.refund(0);

        vm.prank(playerTwo);
        puppyRaffle.refund(1);

        vm.prank(playerThree);
        puppyRaffle.refund(2);

        vm.prank(playerFour);
        puppyRaffle.refund(3);

        vm.warp(block.timestamp + duration + 1);
        vm.roll(block.number + 1);

        vm.expectRevert();
        puppyRaffle.selectWinner();
    }

    function testWinnerCanBeChosenWithLessThanFourActivePlayers() public {
        address[] memory newPlayers = new address[](4);
        newPlayers[0] = playerOne;
        newPlayers[1] = playerTwo;
        newPlayers[2] = playerThree;
        newPlayers[3] = playerFour;

        //all four players enter raffle
        puppyRaffle.enterRaffle{value: entranceFee * 4}(newPlayers);

        //Refund all players
        vm.prank(playerOne);
        puppyRaffle.refund(0);

        vm.prank(playerTwo);
        puppyRaffle.refund(1);

        vm.prank(playerThree);
        puppyRaffle.refund(2);

        vm.warp(block.timestamp + duration + 1);
        vm.roll(block.number + 1);

        vm.expectRevert("PuppyRaffle: Failed to send prize pool to winner");
        puppyRaffle.selectWinner();
    }

    function testPrizePoolAndRaffleFeesIncorrectlyCalculatedAfterRefunds()
        public
    {
        address[] memory newPlayers = new address[](6);
        newPlayers[0] = playerOne;
        newPlayers[1] = playerTwo;
        newPlayers[2] = playerThree;
        newPlayers[3] = playerFour;
        newPlayers[4] = playerFive;
        newPlayers[5] = playerSix;

        //all four players enter raffle
        puppyRaffle.enterRaffle{value: entranceFee * 6}(newPlayers);

        //Refund first player
        vm.prank(playerOne);
        puppyRaffle.refund(0);

        vm.warp(block.timestamp + duration + 1);
        vm.roll(block.number + 1);

        puppyRaffle.selectWinner();
        assert(address(puppyRaffle).balance != (5 * entranceFee) / 20);
    }

    function testPrizePoolAndRaffleFeesCorrectlyCalculatedAfterRefunds()
        public
    {
        address[] memory newPlayers = new address[](6);
        newPlayers[0] = playerOne;
        newPlayers[1] = playerTwo;
        newPlayers[2] = playerThree;
        newPlayers[3] = playerFour;
        newPlayers[4] = playerFive;
        newPlayers[5] = playerSix;

        //all four players enter raffle
        puppyRaffle.enterRaffle{value: entranceFee * 6}(newPlayers);

        //Refund first player
        vm.prank(playerOne);
        puppyRaffle.refund(0);

        vm.warp(block.timestamp + duration + 1);
        vm.roll(block.number + 1);

        console.log(
            "Contract value before winner: ",
            address(puppyRaffle).balance
        );
        puppyRaffle.selectWinner();
        console.log(
            "Contract value before winner: ",
            address(puppyRaffle).balance
        );
    }

    function testCanEntryFeeBeManipulatedWithIntegerUnderflowAttack() public {
        PuppyRaffle overflowPuppyRaffle;
        uint256 overflowEntranceFee = type(uint256).max / 2 + 1;
        overflowPuppyRaffle = new PuppyRaffle(
            overflowEntranceFee,
            feeAddress,
            duration
        );
        address[] memory players = new address[](2);
        players[0] = playerOne;
        players[1] = playerTwo;

        overflowPuppyRaffle.enterRaffle{value: 0}(players);
    }

    function testDivisionPrecisionLoss() public {
        PuppyRaffle divisionPrecisionPuppyRaffle;
        uint256 divisionPrecisionEntranceFee = 145678976567;
        divisionPrecisionPuppyRaffle = new PuppyRaffle(
            divisionPrecisionEntranceFee,
            feeAddress,
            duration
        );
        address[] memory players = new address[](4);
        players[0] = playerOne;
        players[1] = playerTwo;
        players[2] = playerThree;
        players[3] = playerFour;
        divisionPrecisionPuppyRaffle.enterRaffle{
            value: divisionPrecisionEntranceFee * 4
        }(players);

        vm.warp(block.timestamp + duration + 1);
        vm.roll(block.number + 1);

        divisionPrecisionPuppyRaffle.selectWinner();
        uint256 totalFeesAfterWinnerSelected = divisionPrecisionPuppyRaffle
            .totalFees();

        uint256 prizepool = address(playerFour).balance;

        console.log("Total amount of funds collected: ", entranceFee * 4);
        console.log(
            "Total of prize pool and fees from first raffle: ",
            totalFeesAfterWinnerSelected + prizepool
        );
        assert(entranceFee * 4 != totalFeesAfterWinnerSelected + prizepool);
    }

    function testWinnersCanBeSelectedWhenRaffleIsStillActive()
        public
        playersEntered
    {
        uint256 start = 1;
        vm.warp(duration + 1);

        assert(block.timestamp == start + duration);
        puppyRaffle.selectWinner();
    }

    function testTypecastingInFeeCalculation() public {
        PuppyRaffle typecastingPuppyRaffle;
        //should create error when 20% of total entranceFee exceeds uint64 max
        uint256 typecastingPuppyRaffleEntryFee = (type(uint64).max) / 2 + 1;
        typecastingPuppyRaffle = new PuppyRaffle(
            typecastingPuppyRaffleEntryFee,
            feeAddress,
            duration
        );
        address[] memory players = new address[](10);
        players[0] = playerOne;
        players[1] = playerTwo;
        players[2] = playerThree;
        players[3] = playerFour;
        players[4] = playerFive;
        players[5] = playerSix;
        players[6] = address(7);
        players[7] = address(8);
        players[8] = address(9);
        players[9] = address(10);
        typecastingPuppyRaffle.enterRaffle{
            value: typecastingPuppyRaffleEntryFee * 10
        }(players);

        vm.warp(block.timestamp + duration + 1);
        vm.roll(block.number + 1);

        typecastingPuppyRaffle.selectWinner();

        uint256 totalAmountCollected = 10 * typecastingPuppyRaffleEntryFee;
        uint256 fee = (totalAmountCollected * 20) / 100;
        uint256 totalFees = uint64(fee);
        assert(totalFees != fee);
    }

    function testIntegerOverflowUnderflow() public {
        uint256 OverflowUnderflowEntranceFee = (type(uint256).max) / 2 + 1;
        uint256 playersLength = 2;
        uint256 totalAmountCollected = playersLength *
            OverflowUnderflowEntranceFee;

        assert(OverflowUnderflowEntranceFee > totalAmountCollected);
    }
}
