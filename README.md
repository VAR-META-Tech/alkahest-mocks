## Alkahest

Alkahest is a library and ecosystem for peer-to-peer exchange.

Statements represent obligations within a peer-to-peer agreement, while validators represent conditions under which statements are considered valid. 

These compose with each other to eventually enable trading anything for anything else, with flexible per-deal assurance guarantees.

Learn more at [Alkahest Docs](https://alkahest.coophive.network).

## Contracts

Base contracts: 
- [IArbiter](https://github.com/CoopHive/alkahest-mocks/blob/main/src/it1_bytes_arbiters/IArbiter.sol)
- [BaseObligation](https://github.com/CoopHive/alkahest-mocks/blob/main/src/it1_bytes_arbiters/BaseObligation.sol)
- [IValidator](https://github.com/CoopHive/alkahest-mocks/blob/main/src/it1_bytes_arbiters/IValidator.sol)



Implementations:

- Statements:
    - [ERC20EscrowObligation](https://github.com/CoopHive/alkahest-mocks/blob/main/src/it1_bytes_arbiters/ERC20EscrowObligation.sol)
    - [StringResultObligation](https://github.com/CoopHive/alkahest-mocks/blob/main/src/it1_bytes_arbiters/StringResultObligation.sol)
- Validators:
    - [ERC20PaymentFulfillmentValidator](https://github.com/CoopHive/alkahest-mocks/blob/main/src/it1_bytes_arbiters/ERC20PaymentFulfillmentValidator.sol)
    - [OptimisticStringValidator](https://github.com/CoopHive/alkahest-mocks/blob/main/src/it1_bytes_arbiters/OptimisticStringValidator.sol)

## Demo
Example workflows
- Buying string uppercasing for ERC20 tokens, with optimistic mediation: [tokens for strings](https://github.com/CoopHive/alkahest-mocks/blob/main/test/TokensForStrings.t.sol)
- Exchanging ERC20 tokens for other ERC20 tokens: [tokens for tokens](https://github.com/CoopHive/alkahest-mocks/blob/main/test/TokensForTokens.t.sol)

run tests: 
1. set `RPC_URL_MAINNET` env variable to any Ethereum mainnet RPC url - e.g. Alchemy, Infura, etc.
2. `forge test`