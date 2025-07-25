// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import {ERC1155BarterUtils} from "./ERC1155BarterUtils.sol";
import {IEAS} from "@eas/IEAS.sol";
import {Attestation} from "@eas/Common.sol";
import {ERC20EscrowObligation} from "../obligations/ERC20EscrowObligation.sol";
import {ERC20PaymentObligation} from "../obligations/ERC20PaymentObligation.sol";
import {ERC721EscrowObligation} from "../obligations/ERC721EscrowObligation.sol";
import {ERC721PaymentObligation} from "../obligations/ERC721PaymentObligation.sol";
import {ERC1155EscrowObligation} from "../obligations/ERC1155EscrowObligation.sol";
import {ERC1155PaymentObligation} from "../obligations/ERC1155PaymentObligation.sol";
import {TokenBundleEscrowObligation} from "../obligations/TokenBundleEscrowObligation.sol";
import {TokenBundlePaymentObligation} from "../obligations/TokenBundlePaymentObligation.sol";

contract ERC1155BarterCrossToken is ERC1155BarterUtils {
    ERC20PaymentObligation internal erc20Payment;
    ERC20EscrowObligation internal erc20Escrow;
    ERC721EscrowObligation internal erc721Escrow;
    ERC721PaymentObligation internal erc721Payment;
    TokenBundleEscrowObligation internal bundleEscrow;
    TokenBundlePaymentObligation internal bundlePayment;

    constructor(
        IEAS _eas,
        ERC20EscrowObligation _erc20Escrow,
        ERC20PaymentObligation _erc20Payment,
        ERC721EscrowObligation _erc721Escrow,
        ERC721PaymentObligation _erc721Payment,
        ERC1155EscrowObligation _erc1155Escrow,
        ERC1155PaymentObligation _erc1155Payment,
        TokenBundleEscrowObligation _bundleEscrow,
        TokenBundlePaymentObligation _bundlePayment
    ) ERC1155BarterUtils(_eas, _erc1155Escrow, _erc1155Payment) {
        erc20Escrow = _erc20Escrow;
        erc20Payment = _erc20Payment;
        erc721Escrow = _erc721Escrow;
        erc721Payment = _erc721Payment;
        bundleEscrow = _bundleEscrow;
        bundlePayment = _bundlePayment;
    }

    function buyErc20WithErc1155(
        address bidToken,
        uint256 bidTokenId,
        uint256 bidAmount,
        address askToken,
        uint256 askAmount,
        uint64 expiration
    ) external returns (bytes32) {
        return
            erc1155Escrow.doObligationFor(
                ERC1155EscrowObligation.ObligationData({
                    token: bidToken,
                    tokenId: bidTokenId,
                    amount: bidAmount,
                    arbiter: address(erc20Payment),
                    demand: abi.encode(
                        ERC20PaymentObligation.ObligationData({
                            token: askToken,
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

    function buyErc721WithErc1155(
        address bidToken,
        uint256 bidTokenId,
        uint256 bidAmount,
        address askToken,
        uint256 askTokenId,
        uint64 expiration
    ) external returns (bytes32) {
        return
            erc1155Escrow.doObligationFor(
                ERC1155EscrowObligation.ObligationData({
                    token: bidToken,
                    tokenId: bidTokenId,
                    amount: bidAmount,
                    arbiter: address(erc721Payment),
                    demand: abi.encode(
                        ERC721PaymentObligation.ObligationData({
                            token: askToken,
                            tokenId: askTokenId,
                            payee: msg.sender
                        })
                    )
                }),
                expiration,
                msg.sender,
                msg.sender
            );
    }

    function buyBundleWithErc1155(
        address bidToken,
        uint256 bidTokenId,
        uint256 bidAmount,
        TokenBundlePaymentObligation.ObligationData calldata askData,
        uint64 expiration
    ) external returns (bytes32) {
        return
            erc1155Escrow.doObligationFor(
                ERC1155EscrowObligation.ObligationData({
                    token: bidToken,
                    tokenId: bidTokenId,
                    amount: bidAmount,
                    arbiter: address(bundlePayment),
                    demand: abi.encode(askData)
                }),
                expiration,
                msg.sender,
                msg.sender
            );
    }

    function payErc1155ForErc20(
        bytes32 buyAttestation
    ) external returns (bytes32) {
        Attestation memory bid = eas.getAttestation(buyAttestation);
        ERC20EscrowObligation.ObligationData memory escrowData = abi.decode(
            bid.data,
            (ERC20EscrowObligation.ObligationData)
        );
        ERC1155PaymentObligation.ObligationData memory demand = abi.decode(
            escrowData.demand,
            (ERC1155PaymentObligation.ObligationData)
        );

        bytes32 sellAttestation = erc1155Payment.doObligationFor(
            demand,
            msg.sender,
            msg.sender
        );

        if (!erc20Escrow.collectEscrow(buyAttestation, sellAttestation)) {
            revert CouldntCollectEscrow();
        }

        return sellAttestation;
    }

    function payErc1155ForErc721(
        bytes32 buyAttestation
    ) external returns (bytes32) {
        Attestation memory bid = eas.getAttestation(buyAttestation);
        ERC721EscrowObligation.ObligationData memory escrowData = abi.decode(
            bid.data,
            (ERC721EscrowObligation.ObligationData)
        );
        ERC1155PaymentObligation.ObligationData memory demand = abi.decode(
            escrowData.demand,
            (ERC1155PaymentObligation.ObligationData)
        );

        bytes32 sellAttestation = erc1155Payment.doObligationFor(
            demand,
            msg.sender,
            msg.sender
        );

        if (!erc721Escrow.collectEscrow(buyAttestation, sellAttestation)) {
            revert CouldntCollectEscrow();
        }

        return sellAttestation;
    }

    function payErc1155ForBundle(
        bytes32 buyAttestation
    ) external returns (bytes32) {
        Attestation memory bid = eas.getAttestation(buyAttestation);
        TokenBundleEscrowObligation.ObligationData memory escrowData = abi
            .decode(bid.data, (TokenBundleEscrowObligation.ObligationData));
        ERC1155PaymentObligation.ObligationData memory demand = abi.decode(
            escrowData.demand,
            (ERC1155PaymentObligation.ObligationData)
        );

        bytes32 sellAttestation = erc1155Payment.doObligationFor(
            demand,
            msg.sender,
            msg.sender
        );

        if (!bundleEscrow.collectEscrow(buyAttestation, sellAttestation)) {
            revert CouldntCollectEscrow();
        }

        return sellAttestation;
    }
}