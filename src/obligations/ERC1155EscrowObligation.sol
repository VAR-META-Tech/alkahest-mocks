// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import {Attestation} from "@eas/Common.sol";
import {IEAS, AttestationRequest, AttestationRequestData, RevocationRequest, RevocationRequestData} from "@eas/IEAS.sol";
import {ISchemaRegistry} from "@eas/ISchemaRegistry.sol";
import {IERC1155} from "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import {ERC1155Holder} from "@openzeppelin/contracts/token/ERC1155/utils/ERC1155Holder.sol";
import {BaseObligation} from "../BaseObligation.sol";
import {IArbiter} from "../IArbiter.sol";
import {ArbiterUtils} from "../ArbiterUtils.sol";

contract ERC1155EscrowObligation is BaseObligation, IArbiter, ERC1155Holder {
    using ArbiterUtils for Attestation;

    struct ObligationData {
        address arbiter;
        bytes demand;
        address token;
        uint256 tokenId;
        uint256 amount;
    }

    event EscrowMade(bytes32 indexed payment, address indexed buyer);
    event EscrowClaimed(
        bytes32 indexed payment,
        bytes32 indexed fulfillment,
        address indexed fulfiller
    );

    error InvalidEscrow();
    error InvalidEscrowAttestation();
    error InvalidFulfillment();
    error UnauthorizedCall();
    error ERC1155TransferFailed(
        address token,
        address from,
        address to,
        uint256 tokenId,
        uint256 amount
    );
    error AttestationNotFound(bytes32 attestationId);
    error AttestationCreateFailed();
    error RevocationFailed(bytes32 attestationId);

    constructor(
        IEAS _eas,
        ISchemaRegistry _schemaRegistry
    )
        BaseObligation(
            _eas,
            _schemaRegistry,
            "address arbiter, bytes demand, address token, uint256 tokenId, uint256 amount",
            true
        )
    {}

    function doObligationFor(
        ObligationData calldata data,
        uint64 expirationTime,
        address payer,
        address recipient
    ) public returns (bytes32 uid_) {
        // Try ERC1155 token transfer with error handling
        try
            IERC1155(data.token).safeTransferFrom(
                payer,
                address(this),
                data.tokenId,
                data.amount,
                ""
            )
        {
            // Transfer succeeded
        } catch {
            revert ERC1155TransferFailed(
                data.token,
                payer,
                address(this),
                data.tokenId,
                data.amount
            );
        }

        // Create attestation with try/catch for potential EAS failures
        try
            eas.attest(
                AttestationRequest({
                    schema: ATTESTATION_SCHEMA,
                    data: AttestationRequestData({
                        recipient: recipient,
                        expirationTime: expirationTime,
                        revocable: true,
                        refUID: bytes32(0),
                        data: abi.encode(data),
                        value: 0
                    })
                })
            )
        returns (bytes32 uid) {
            uid_ = uid;
            emit EscrowMade(uid_, recipient);
        } catch {
            // The revert will automatically revert all state changes including token transfers
            revert AttestationCreateFailed();
        }
    }

    function doObligation(
        ObligationData calldata data,
        uint64 expirationTime
    ) public returns (bytes32 uid_) {
        return doObligationFor(data, expirationTime, msg.sender, msg.sender);
    }

    function collectEscrow(
        bytes32 _payment,
        bytes32 _fulfillment
    ) public returns (bool) {
        Attestation memory payment;
        Attestation memory fulfillment;

        // Get payment attestation with error handling
        try eas.getAttestation(_payment) returns (Attestation memory result) {
            payment = result;
        } catch {
            revert AttestationNotFound(_payment);
        }

        // Get fulfillment attestation with error handling
        try eas.getAttestation(_fulfillment) returns (
            Attestation memory result
        ) {
            fulfillment = result;
        } catch {
            revert AttestationNotFound(_fulfillment);
        }

        if (!payment._checkIntrinsic()) revert InvalidEscrowAttestation();

        ObligationData memory paymentData = abi.decode(
            payment.data,
            (ObligationData)
        );

        if (
            !IArbiter(paymentData.arbiter).checkObligation(
                fulfillment,
                paymentData.demand,
                payment.uid
            )
        ) revert InvalidFulfillment();

        // Revoke attestation with error handling
        try
            eas.revoke(
                RevocationRequest({
                    schema: ATTESTATION_SCHEMA,
                    data: RevocationRequestData({uid: _payment, value: 0})
                })
            )
        {} catch {
            revert RevocationFailed(_payment);
        }

        // Transfer ERC1155 token with error handling
        try
            IERC1155(paymentData.token).safeTransferFrom(
                address(this),
                fulfillment.recipient,
                paymentData.tokenId,
                paymentData.amount,
                ""
            )
        {} catch {
            revert ERC1155TransferFailed(
                paymentData.token,
                address(this),
                fulfillment.recipient,
                paymentData.tokenId,
                paymentData.amount
            );
        }

        emit EscrowClaimed(_payment, _fulfillment, fulfillment.recipient);
        return true;
    }

    function reclaimExpired(bytes32 uid) public returns (bool) {
        Attestation memory attestation;

        // Get attestation with error handling
        try eas.getAttestation(uid) returns (Attestation memory result) {
            attestation = result;
        } catch {
            revert AttestationNotFound(uid);
        }

        if (block.timestamp < attestation.expirationTime)
            revert UnauthorizedCall();

        ObligationData memory data = abi.decode(
            attestation.data,
            (ObligationData)
        );

        // Transfer ERC1155 token with error handling
        try
            IERC1155(data.token).safeTransferFrom(
                address(this),
                attestation.recipient,
                data.tokenId,
                data.amount,
                ""
            )
        {} catch {
            revert ERC1155TransferFailed(
                data.token,
                address(this),
                attestation.recipient,
                data.tokenId,
                data.amount
            );
        }

        return true;
    }

    function checkObligation(
        Attestation memory obligation,
        bytes memory demand,
        bytes32 /* counteroffer */
    ) public view override returns (bool) {
        if (!obligation._checkIntrinsic(ATTESTATION_SCHEMA)) return false;

        ObligationData memory payment = abi.decode(
            obligation.data,
            (ObligationData)
        );
        ObligationData memory demandData = abi.decode(demand, (ObligationData));

        return
            payment.token == demandData.token &&
            payment.tokenId == demandData.tokenId &&
            payment.amount >= demandData.amount &&
            payment.arbiter == demandData.arbiter &&
            keccak256(payment.demand) == keccak256(demandData.demand);
    }

    function getObligationData(
        bytes32 uid
    ) public view returns (ObligationData memory) {
        Attestation memory attestation = eas.getAttestation(uid);
        if (attestation.schema != ATTESTATION_SCHEMA)
            revert InvalidEscrowAttestation();
        return abi.decode(attestation.data, (ObligationData));
    }

    function decodeObligationData(
        bytes calldata data
    ) public pure returns (ObligationData memory) {
        return abi.decode(data, (ObligationData));
    }
}
