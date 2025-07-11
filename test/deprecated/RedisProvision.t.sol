// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import "forge-std/Test.sol";
import {RedisProvisionObligation} from "@src/obligations/example/RedisProvisionObligation.sol";
import {IEAS, AttestationRequest, AttestationRequestData, RevocationRequest, RevocationRequestData} from "@eas/IEAS.sol";
import {Attestation} from "@eas/Common.sol";
import {ISchemaRegistry} from "@eas/ISchemaRegistry.sol";
import {EASDeployer} from "@test/utils/EASDeployer.sol";

contract RedisProvisionObligationTest is Test {
    RedisProvisionObligation public provisionObligation;
    IEAS public eas;
    ISchemaRegistry public schemaRegistry;

    address public alice = address(0x1);
    address public bob = address(0x2);

    function setUp() public {
        // Fork Ethereum mainnet to test in a real environment
        EASDeployer easDeployer = new EASDeployer();
        (eas, schemaRegistry) = easDeployer.deployEAS();

        // Set the actual EAS and Schema Registry addresses

        // Deploy RedisProvisionObligation contract
        provisionObligation = new RedisProvisionObligation(eas, schemaRegistry);
    }

    function testAliceCanMakeNewProvisionStatement() public {
        vm.startPrank(alice);

        // Create a new provision obligation for Redis
        RedisProvisionObligation.ObligationData memory obligationData = RedisProvisionObligation
            .ObligationData({
                user: alice,
                capacity: 1024 * 1024 * 1024, // 1 GB
                egress: 500 * 1024 * 1024, // 500 MB
                cpus: 2,
                serverName: "us-east-1",
                url: "redis://example.com:6379"
            });
        uint64 expiration = uint64(block.timestamp + 30 days);

        bytes32 obligationUID = provisionObligation.doObligation(
            obligationData,
            expiration
        );

        // Retrieve the attestation and verify it matches the input data
        Attestation memory attestation = eas.getAttestation(obligationUID);
        RedisProvisionObligation.ObligationData memory retrievedData = abi
            .decode(attestation.data, (RedisProvisionObligation.ObligationData));

        assertEq(retrievedData.user, obligationData.user, "User should match");
        assertEq(
            retrievedData.capacity,
            obligationData.capacity,
            "Capacity should match"
        );
        assertEq(
            retrievedData.egress,
            obligationData.egress,
            "Egress should match"
        );
        assertEq(
            retrievedData.cpus,
            obligationData.cpus,
            "Ingress should match"
        );
        assertEq(
            attestation.expirationTime,
            expiration,
            "Expiration should match"
        );
        assertEq(retrievedData.url, obligationData.url, "URL should match");

        vm.stopPrank();
    }

    function testAliceCanUpdateProvisionStatement() public {
        vm.startPrank(alice);

        // Create initial provision obligation
        RedisProvisionObligation.ObligationData memory obligationData = RedisProvisionObligation
            .ObligationData({
                user: alice,
                capacity: 1024 * 1024 * 1024, // 1 GB
                egress: 500 * 1024 * 1024, // 500 MB
                cpus: 2,
                serverName: "us-east-1",
                url: "redis://example.com:6379"
            });
        uint64 expiration = uint64(block.timestamp + 30 days);

        bytes32 initialUID = provisionObligation.doObligation(
            obligationData,
            expiration
        );

        // Update the provision obligation (increase capacity and expiration)
        RedisProvisionObligation.ChangeData memory changeData = RedisProvisionObligation
            .ChangeData({
                addedCapacity: 512 * 1024 * 1024, // Add 512 MB
                addedEgress: 100 * 1024 * 1024, // Add 100 MB
                addedCpus: 2,
                addedDuration: uint64(15 days), // Extend by 15 days
                newServerName: "",
                newUrl: "" // No change to URL
            });

        bytes32 updatedUID = provisionObligation.reviseStatement(
            initialUID,
            changeData
        );

        // Retrieve the updated attestation
        Attestation memory originalAttestation = eas.getAttestation(initialUID);
        Attestation memory updatedAttestation = eas.getAttestation(updatedUID);
        RedisProvisionObligation.ObligationData memory updatedData = abi.decode(
            updatedAttestation.data,
            (RedisProvisionObligation.ObligationData)
        );

        // Check that the updates were applied
        assertEq(
            updatedData.capacity,
            obligationData.capacity + changeData.addedCapacity,
            "Capacity should be updated"
        );
        assertEq(
            updatedData.egress,
            obligationData.egress + changeData.addedEgress,
            "Egress should be updated"
        );
        assertEq(
            updatedData.cpus,
            obligationData.cpus + changeData.addedCpus,
            "CPUs should be updated"
        );
        assertEq(
            updatedAttestation.expirationTime,
            originalAttestation.expirationTime + changeData.addedDuration,
            "Expiration should be updated"
        );
        assertEq(
            updatedData.serverName,
            obligationData.serverName,
            "Server name should remain the same"
        );
        assertEq(
            updatedData.url,
            obligationData.url,
            "URL should remain the same"
        );

        vm.stopPrank();
    }

    function testAliceCanUpdateIndividualParams() public {
        vm.startPrank(alice);

        // Create initial provision obligation
        RedisProvisionObligation.ObligationData memory obligationData = RedisProvisionObligation
            .ObligationData({
                user: alice,
                capacity: 1024 * 1024 * 1024, // 1 GB
                egress: 500 * 1024 * 1024, // 500 MB
                cpus: 2,
                serverName: "us-east-1",
                url: "redis://example.com:6379"
            });

        uint64 expiration = uint64(block.timestamp + 30 days);
        bytes32 initialUID = provisionObligation.doObligation(
            obligationData,
            expiration
        );

        // Update only the capacity
        RedisProvisionObligation.ChangeData memory changeCapacity = RedisProvisionObligation
            .ChangeData({
                addedCapacity: 512 * 1024 * 1024, // Add 512 MB
                addedEgress: 0,
                addedCpus: 0,
                addedDuration: 0,
                newUrl: "",
                newServerName: ""
            });

        bytes32 updatedUID1 = provisionObligation.reviseStatement(
            initialUID,
            changeCapacity
        );

        // Update only the expiration
        RedisProvisionObligation.ChangeData memory changeExpiration = RedisProvisionObligation
            .ChangeData({
                addedCapacity: 0,
                addedEgress: 0,
                addedCpus: 0,
                addedDuration: uint64(15 days), // Extend by 15 days
                newUrl: "",
                newServerName: ""
            });

        bytes32 updatedUID2 = provisionObligation.reviseStatement(
            updatedUID1,
            changeExpiration
        );

        // Update only the URL
        RedisProvisionObligation.ChangeData
            memory changeUrl = RedisProvisionObligation.ChangeData({
                addedCapacity: 0,
                addedEgress: 0,
                addedCpus: 0,
                addedDuration: 0,
                newUrl: "redis://newexample.com:6379",
                newServerName: ""
            });

        bytes32 updatedUID3 = provisionObligation.reviseStatement(
            updatedUID2,
            changeUrl
        );

        Attestation memory originalAttestation = eas.getAttestation(initialUID);
        Attestation memory updatedAttestation = eas.getAttestation(updatedUID3);
        RedisProvisionObligation.ObligationData memory updatedData = abi.decode(
            updatedAttestation.data,
            (RedisProvisionObligation.ObligationData)
        );

        // Check that the updates were applied
        assertEq(
            updatedData.capacity,
            obligationData.capacity + changeCapacity.addedCapacity,
            "Capacity should be updated"
        );
        assertEq(
            updatedAttestation.expirationTime,
            originalAttestation.expirationTime + changeExpiration.addedDuration,
            "Expiration should be updated"
        );
        assertEq(updatedData.url, changeUrl.newUrl, "URL should be updated");

        vm.stopPrank();
    }

    function testBobCannotUpdateAlicesProvisionStatement() public {
        vm.startPrank(alice);

        // Alice creates a provision obligation
        RedisProvisionObligation.ObligationData memory obligationData = RedisProvisionObligation
            .ObligationData({
                user: alice,
                capacity: 1024 * 1024 * 1024, // 1 GB
                egress: 500 * 1024 * 1024, // 500 MB
                cpus: 2,
                serverName: "us-east-1",
                url: "redis://example.com:6379"
            });
        uint64 expiration = uint64(block.timestamp + 30 days);

        bytes32 aliceUID = provisionObligation.doObligation(
            obligationData,
            expiration
        );
        vm.stopPrank();

        // Bob tries to update Alice's provision obligation
        RedisProvisionObligation.ChangeData memory changeData = RedisProvisionObligation
            .ChangeData({
                addedCapacity: 512 * 1024 * 1024, // Attempt to add 512 MB
                addedEgress: 0,
                addedCpus: 0,
                addedDuration: 0,
                newUrl: "",
                newServerName: ""
            });

        vm.expectRevert(abi.encodeWithSignature("UnauthorizedCall()"));
        provisionObligation.reviseStatement(aliceUID, changeData);

        vm.stopPrank();
    }
}
