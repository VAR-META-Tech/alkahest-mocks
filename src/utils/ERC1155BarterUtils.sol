// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import {Attestation} from "@eas/Common.sol";
import {IEAS} from "@eas/IEAS.sol";
import {ERC1155EscrowObligation} from "../obligations/ERC1155EscrowObligation.sol";
import {ERC1155PaymentObligation} from "../obligations/ERC1155PaymentObligation.sol";
import {IERC1155} from "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";

contract ERC1155BarterUtils {
    IEAS internal eas;
    ERC1155EscrowObligation internal erc1155Escrow;
    ERC1155PaymentObligation internal erc1155Payment;

    error CouldntCollectEscrow();

    constructor(
        IEAS _eas,
        ERC1155EscrowObligation _erc1155Escrow,
        ERC1155PaymentObligation _erc1155Payment
    ) {
        eas = _eas;
        erc1155Escrow = _erc1155Escrow;
        erc1155Payment = _erc1155Payment;
    }

    function _buyErc1155ForErc1155(
        address bidToken,
        uint256 bidTokenId,
        uint256 bidAmount,
        address askToken,
        uint256 askId,
        uint256 askAmount,
        uint64 expiration
    ) internal returns (bytes32) {
        return
            erc1155Escrow.doObligationFor(
                ERC1155EscrowObligation.ObligationData({
                    token: bidToken,
                    tokenId: bidTokenId,
                    amount: bidAmount,
                    arbiter: address(erc1155Payment),
                    demand: abi.encode(
                        ERC1155PaymentObligation.ObligationData({
                            token: askToken,
                            tokenId: askId,
                            amount: askAmount,
                            payee: msg.sender
                        })
                    )
                }),
                expiration,
                msg.sender,
                msg.sender
            );
    }

    function _payErc1155ForErc1155(
        bytes32 buyAttestation,
        ERC1155PaymentObligation.ObligationData memory demand
    ) internal returns (bytes32) {
        bytes32 sellAttestation = erc1155Payment.doObligationFor(
            demand,
            msg.sender,
            msg.sender
        );

        if (!erc1155Escrow.collectEscrow(buyAttestation, sellAttestation)) {
            revert CouldntCollectEscrow();
        }

        return sellAttestation;
    }

    function buyErc1155ForErc1155(
        address bidToken,
        uint256 bidTokenId,
        uint256 bidAmount,
        address askToken,
        uint256 askId,
        uint256 askAmount,
        uint64 expiration
    ) external returns (bytes32) {
        return
            _buyErc1155ForErc1155(
                bidToken,
                bidTokenId,
                bidAmount,
                askToken,
                askId,
                askAmount,
                expiration
            );
    }

    function payErc1155ForErc1155(
        bytes32 buyAttestation
    ) external returns (bytes32) {
        Attestation memory bid = eas.getAttestation(buyAttestation);
        ERC1155EscrowObligation.ObligationData memory escrowData = abi.decode(
            bid.data,
            (ERC1155EscrowObligation.ObligationData)
        );
        ERC1155PaymentObligation.ObligationData memory demand = abi.decode(
            escrowData.demand,
            (ERC1155PaymentObligation.ObligationData)
        );

        return _payErc1155ForErc1155(buyAttestation, demand);
    }
}
