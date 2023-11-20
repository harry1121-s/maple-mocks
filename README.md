# nSTBL Loan Manager

## Overview
This repository contains the core contracts of the nSTBL V1 protocol that are responsible for interacting with Maple finance USDC cash pool.

| Contract | Description |
| -------- | ------- |
| [`LoanManager`](https://github.com/nealthy-labs/nSTBL_V1_LoanManager/blob/main/contracts/LoanManager.sol) | Contains the logic for the Loan Manager |
| [`ILoanManager`](https://github.com/nealthy-labs/nSTBL_V1_LoanManager/blob/main/contracts/ILoanManager.sol) | The interface for the Loan Manager contract |

## Dependencies/Inheritance
Contracts in this repo inherit and import code from:
- [`openzeppelin-contracts`](https://github.com/OpenZeppelin/openzeppelin-contracts)
- [`nstbl-acl-manager`](https://github.com/LayerZero-Labs/solidity-examples.git)

## Setup
Run the command ```forge install``` before running any of the make commands. 

## Commands
To make it easier to perform some tasks within the repo, a few commands are available through a makefile:

### Build Commands
| Command | Action |
|---|---|
| `make test` | Run all tests |
| `make debug` | Run all tests with debug traces |
| `make testUnit` | Run unit tests |
| `make testInvariant` | Run stateful fuzz tests with a depth of 15 |
| `make clean` | Delete cached files |
| `make coverage` | Generate coverage report under coverage directory |
| `make slither` | Run static analyzer |

## Testing
1. [`BaseTest.t.sol`](https://github.com/nealthy-labs/nSTBL_V1_nSTBLToken/blob/main/tests/BaseTest.t.sol) contains the deployment setup for the Token and ACLManager.
2. [`Token.t.sol`](https://github.com/nealthy-labs/nSTBL_V1_nSTBLToken/blob/main/tests/BaseTest.t.sol) contains the unit tests for the Token contract.
3. [`Invariant`](https://github.com/nealthy-labs/nSTBL_V1_nSTBLToken/blob/main/tests/Invariant) contains the stateful fuzz tests 

## About Nealthy
[Nealthy](https://www.nealthy.com) is a VARA regulated crypto asset management company. Nealthy provides on-chain index products for KYC/KYB individuals and institutions to invest in.