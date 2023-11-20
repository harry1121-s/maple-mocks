install:
	@mkdir modules && \
	cd modules && \
	git submodule add https://github.com/foundry-rs/forge-std.git && \
	git submodule add https://github.com/OpenZeppelin/openzeppelin-contracts.git && \
	git submodule add https://github.com/nealthy-labs/nSTBL_V1_ACLManager.git && \
	cd ..

update:
	cd modules && \
	git submodule update --remote nstbl-acl-manager && \
	cd ..


build:
	@forge build --sizes

test:
	@forge test

debug: 
	@forge test -vvvvv

testToken:
	@forge test --match-path ./tests/unit/Token.t.sol

testLoanManager:
	@forge test --match-path ./tests/unit/LoanManager.t.sol -vvv --gas-report

clean:
	@forge clean && \
	rm -rf coverage && \
	rm lcov.info

git:
	@git add .
	git commit -m "$m"
	git push

coverage:
	@forge coverage --report lcov && genhtml lcov.info --branch-coverage --output-dir coverage

slither:
	@solc-select use 0.8.21 && \
	slither . 

.PHONY: install build test debug clean git coverage slither
