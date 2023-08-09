// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

import {Test, console} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {VRFCoordinatorV2Mock} from "@chainlink/contracts/src/v0.8/mocks/VRFCoordinatorV2Mock.sol";
import {DeployRaffle} from "script/DeployRaffle.s.sol";
import {HelperConfig} from "script/HelperConfig.s.sol";
import {Raffle} from "src/Raffle.sol";


contract RaffleTest is Test {

    Raffle public raffle;
    HelperConfig public helperConfig;

    uint256 public entranceFee;
    uint256 public interval;
    address public vrfCoordinator;
    bytes32 public gasLane;
    uint64 public subscriptionId;
    uint32 public callbackGasLimit;
    address public link;

    address public player = makeAddr("player");
    uint256 public constant STARTING_PLAYER_BALANCE = 10 ether;

    /** Events */
    event EnteredRaffle(address indexed player);

    modifier raffleEnteredAndTimePassed() {
        vm.prank(player);
        raffle.enterRaffle{value: entranceFee}();
        vm.warp(block.timestamp + interval + 1);
        vm.roll(block.number + 1);
        _;
    }

    modifier skipWhenFork() {
        if (block.chainid != 31337) // Anvil local chainid
            return;
        _;
    }

    function setUp() public {
        DeployRaffle deployRaffle = new DeployRaffle();
        (raffle, helperConfig) = deployRaffle.run();
        (
            entranceFee,
            interval,
            vrfCoordinator,
            gasLane,
            subscriptionId,
            callbackGasLimit,
            link,

        ) = helperConfig.activeNetworkConfig();
        vm.deal(player, STARTING_PLAYER_BALANCE);
    }

    function test_RaffleInitializesInOpenState() public view {
        assert(raffle.getRaffleState() == Raffle.RaffleState.OPEN);
    }

    ////////////////////////
    // enterRaffle        //
    ////////////////////////
    function test_RevertsWhen_NotEnoughEthSent() public {
        vm.prank(player);
        vm.expectRevert(Raffle.Raffle__NotEnoughEthSent.selector);
        raffle.enterRaffle();
    }

    function test_RecordsPlayerWhenEnter() public {
        vm.prank(player);
        raffle.enterRaffle{value: entranceFee}();
        address playerRecorded = raffle.getPlayer(0);
        assertEq(player, playerRecorded);
    }

    function test_EmitsEventOnEntrance() public {
        vm.prank(player);
        vm.expectEmit(true, false, false, false, address(raffle));
        emit Raffle.EnteredRaffle(player);
        raffle.enterRaffle{value: entranceFee}();
    }

    function test_RevertWhen_RaffleIsCalculating() public raffleEnteredAndTimePassed {
        raffle.performUpkeep("");
        vm.expectRevert(Raffle.Raffle__RaffleNotOpen.selector);
        vm.prank(player);
        raffle.enterRaffle{value: entranceFee}();
    }

    ////////////////////////
    // checkUpkeep        //
    ////////////////////////
    function test_ChekUpkeepReturnsFalseIfHasNoBalance() public {
        // Arrange
        vm.warp(block.timestamp + interval + 1);
        vm.roll(block.number + 1);
        // Act
        (bool upkeepNeeded, ) = raffle.checkUpkeep("");
        // Assert   
        assertEq(upkeepNeeded, false);
    }

    function test_CheckUpkeepReturnsFalseIfRaffleCalculating() public raffleEnteredAndTimePassed {
        // Arrange
        raffle.performUpkeep("");
        Raffle.RaffleState raffleState = raffle.getRaffleState();

        // Act
        (bool upkeepNeeded, ) = raffle.checkUpkeep("");

        // Assert
        assert(raffleState == Raffle.RaffleState.CALCULATING);
        assertEq(upkeepNeeded, false);
    }

    function test_CheckUpkeepReturnsFalseIfEnoughTimeHasntPassed() public {
        vm.prank(player);
        raffle.enterRaffle{value: entranceFee}();
        vm.warp(block.timestamp + interval - 1);
        vm.roll(block.number + 1);

        // Act
        (bool upkeepNeeded, ) = raffle.checkUpkeep("");

        // Assert
        assertEq(upkeepNeeded, false);
    }

    function test_CheckUpkeepReturnsTrueWithCorrectParameters() public raffleEnteredAndTimePassed {
        // Act
        (bool upkeepNeeded, ) = raffle.checkUpkeep("");

        // Assert
        assertEq(upkeepNeeded, true);
    }

    ////////////////////////
    // performUpkeep      //
    ////////////////////////
    function test_PerformUpkeepCanOnlyRunIfCheckUpkeepIsTrue() public raffleEnteredAndTimePassed {
        // Act / Assert
        raffle.performUpkeep("");
        // there is no "expectNotRevert" in foundry, so if this test does not revert it automatically passes
    }

    function test_RevertWhen_PerformUpkeepIfCheckUpkeepIsFalse() public {
        // Arrange
        uint256 currentBalance = 0;
        uint256 numPlayers = 0;
        uint256 raffleState = 0;

        // Act / Assert
        vm.expectRevert(abi.encodeWithSelector(Raffle.Raffle__UpkeepNotNeeded.selector, currentBalance, numPlayers, raffleState));
        raffle.performUpkeep("");
    }

    function test_PerformUpkeepUpdatesRaffleStateAndEmitsRequestId() public raffleEnteredAndTimePassed {
        // Act
        vm.recordLogs();
        raffle.performUpkeep(""); // emit requestId
        Vm.Log[] memory entries = vm.getRecordedLogs();
        // the topic at index 0 is the entire event
        bytes32 requestId = entries[1].topics[1];

        Raffle.RaffleState raffleState = raffle.getRaffleState();

        // Assert
        assertGt(uint256(requestId), 0);
        assertEq(uint256(raffleState), 1); // CALCULATING
    }

    ////////////////////////
    // fulfillRandomWords //
    ////////////////////////
    function test_FulfillRandomWordsCanOnlyBeCalledAfterPerformUpkeep(uint256 randomRequestId) public skipWhenFork raffleEnteredAndTimePassed {
        // Arrange
        vm.expectRevert("nonexistent request");
        VRFCoordinatorV2Mock(vrfCoordinator).fulfillRandomWords(randomRequestId, address(raffle));

    }

    function test_FulfillRandomWordsPicksAWinnerResetsAndSendsMoney() public skipWhenFork raffleEnteredAndTimePassed {
        // Arrange
        uint8 additionalEntrance = 5;
        uint8 startingIndex = 1;
        for (uint8 i = startingIndex; i <= additionalEntrance; i++) {
            address newPlayer = address(uint160(i));
            hoax(newPlayer, STARTING_PLAYER_BALANCE);
            raffle.enterRaffle{value: entranceFee}();
        }
        uint256 prize = entranceFee * (additionalEntrance + 1);

        // Act
        vm.recordLogs();
        raffle.performUpkeep(""); // emit requestId
        Vm.Log[] memory entries = vm.getRecordedLogs();
        bytes32 requestId = entries[1].topics[1];
        
        uint256 previousTimeStamp = raffle.getLastTimeStamp();

        VRFCoordinatorV2Mock(vrfCoordinator).fulfillRandomWords(uint256(requestId), address(raffle));
    
        // Assert
        assertEq(uint8(raffle.getRaffleState()), 0); // OPEN
        assertNotEq(raffle.getRecentWinner(), address(0));
        assertEq(raffle.getPlayersLength(), 0);
        assertLt(previousTimeStamp, raffle.getLastTimeStamp());
        assertEq(raffle.getRecentWinner().balance, prize + STARTING_PLAYER_BALANCE - entranceFee);
    }
}
