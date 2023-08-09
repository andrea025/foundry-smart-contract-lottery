// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

import {Script, console} from "forge-std/Script.sol";
import {VRFCoordinatorV2Mock} from "@chainlink/contracts/src/v0.8/mocks/VRFCoordinatorV2Mock.sol";
import {DevOpsTools} from "@foundry-devops/DevOpsTools.sol";
import {LinkToken} from "test/mocks/LinkToken.sol";
import {HelperConfig} from "./HelperConfig.s.sol";

contract CreateSubscription is Script {
    function createSubscription(address vrfCoordinator, uint256 deployerKey) public returns (uint64) {
        console.log("Creating subscription on ChainId:", block.chainid);
        vm.startBroadcast(deployerKey);
        uint64 subscriptionId = VRFCoordinatorV2Mock(vrfCoordinator).createSubscription();
        vm.stopBroadcast();
        console.log("Your subscription ID is:", subscriptionId);
        console.log("Please update subscriptionId in HelperConfig.s.sol");
        return subscriptionId;
    }

    function createSubscriptionUsingConfig() public returns (uint64) {
        HelperConfig helperConfig = new HelperConfig();
        (, , address vrfCoordinator, , , , , uint256 deployerKey) = helperConfig.activeNetworkConfig();
        return createSubscription(vrfCoordinator, deployerKey);
    }

    function run() external returns (uint64) {
        return createSubscriptionUsingConfig();
    }
}

contract FundSubscription is Script {
    uint96 public constant FUND_AMOUNT = 3 ether;

    function fundSubscription(address vrfCoordinator, uint64 subscriptionId, address link, uint256 deployerKey) public {
        console.log("Funding subscription:", subscriptionId);
        console.log("Using vrfCoordinator:", vrfCoordinator);
        console.log("On ChainId:", block.chainid);

        if (block.chainid == 31337) {
            vm.startBroadcast(deployerKey);
            VRFCoordinatorV2Mock(vrfCoordinator).fundSubscription(subscriptionId, FUND_AMOUNT);
            vm.stopBroadcast();
        } else {
            vm.startBroadcast(deployerKey);
            LinkToken(link).transferAndCall(vrfCoordinator, FUND_AMOUNT, abi.encode(subscriptionId));
            vm.stopBroadcast();
        }
    }

    function fundSubscriptionUsingConfig() public {
        HelperConfig helperConfig = new HelperConfig();
        (, , address vrfCoordinator, , uint64 subscriptionId, , address link, uint256 deployerKey) = helperConfig.activeNetworkConfig();
        fundSubscription(vrfCoordinator, subscriptionId, link, deployerKey);
    }

    function run() external {
        fundSubscriptionUsingConfig();
    }
}


contract AddConsumer is Script {
    function addConsumer(address vrfCoordinator, uint256 deployerKey, uint64 subscriptionId, address raffle) public {
        console.log("Adding consumer contract:", raffle);
        console.log("Using vrfCoordinator:", vrfCoordinator);
        console.log("On ChainId:", block.chainid);

        vm.startBroadcast(deployerKey);
        VRFCoordinatorV2Mock(vrfCoordinator).addConsumer(subscriptionId, raffle);
        vm.stopBroadcast();
    }

    function addConsumerUsingConfig(address raffle) public {
        HelperConfig helperConfig = new HelperConfig();
        (, , address vrfCoordinator, , uint64 subscriptionId, , , uint256 deployerKey) = helperConfig.activeNetworkConfig();
        return addConsumer(vrfCoordinator, deployerKey, subscriptionId, raffle);
    }

    function run() external {
        address raffle = DevOpsTools.get_most_recent_deployment("Raffle", block.chainid);
        addConsumerUsingConfig(raffle);
    }
}
