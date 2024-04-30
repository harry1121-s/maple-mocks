// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.21;

import { ERC20Upgradeable } from "@openzeppelin-upgradeable/contracts/token/ERC20/ERC20Upgradeable.sol";
import { Initializable } from "@openzeppelin-upgradeable/contracts/proxy/utils/Initializable.sol";
import { IERC20, IPool }    from "./interfaces/IPool.sol";
import { IERC20Helper } from "./interfaces/IERC20Helper.sol";


/*

    ██████╗  ██████╗  ██████╗ ██╗
    ██╔══██╗██╔═══██╗██╔═══██╗██║
    ██████╔╝██║   ██║██║   ██║██║
    ██╔═══╝ ██║   ██║██║   ██║██║
    ██║     ╚██████╔╝╚██████╔╝███████╗
    ╚═╝      ╚═════╝  ╚═════╝ ╚══════╝

*/

contract Pool is Initializable, ERC20Upgradeable {

    event ConfigurationUpdated(
        uint256 indexed configId_,
        uint64 initialCycleId_,
        uint64 initialCycleTime_,
        uint64 cycleDuration_,
        uint64 windowDuration_
    );

    struct CycleConfig {
        uint64 initialCycleId;    // Identifier of the first withdrawal cycle using this configuration.
        uint64 initialCycleTime;  // Timestamp of the first withdrawal cycle using this configuration.
        uint64 cycleDuration;     // Duration of the withdrawal cycle.
        uint64 windowDuration;    // Duration of the withdrawal window.
    }
    uint256 public liquidityCap;
    uint256 public depositAmount;
    uint256 public latestConfigId;
    mapping(address => uint256) public exitCycleId;
    mapping(address => uint256) public lockedShares;
    mapping(uint256 => CycleConfig) public cycleConfigs;
    mapping(uint256 => uint256) public totalCycleShares;




    uint256 public immutable BOOTSTRAP_MINT;

    uint8 public decimal;
    address public asset;    // Underlying ERC-20 asset handled by the ERC-4626 contract.
    // address public manager;  // Address of the contract that manages administrative functionality.
    uint256 startTime;
    uint256 interest;
    uint256 private _locked;  // Used when checking for reentrancy.
    
    struct WithdrawalRequest {
        address owner;
        uint256 shares;
    }
    struct Queue {
        uint128 nextRequestId;  // Identifier of the next request that will be processed.
        uint128 lastRequestId;  // Identifier of the last created request.
        mapping(uint128 => WithdrawalRequest) requests;  // Maps withdrawal requests to their positions in the queue.
    }


    uint256 public totalShares;  // Total amount of shares pending redemption.

    Queue public queue;

    mapping(address => bool) public isManualWithdrawal;  // Defines which users use automated withdrawals (false by default).

    mapping(address => uint128) public requestIds;  // Maps users to their withdrawal requests identifiers.

    mapping(address => uint256) public manualSharesAvailable;  // Shares available to withdraw for a given manual owner.

    uint256 public vers;
    modifier nonReentrant() {
        require(_locked == 1, "P:LOCKED");

        _locked = 2;

        _;

        _locked = 1;
    }
    function initialize() external initializer
    {   
        vers = 2;

    }

    function decimals() public view virtual override returns (uint8) {
        return decimal;
    }

    /**************************************************************************************************************************************/
    /*** Withdrawal manager functions                                                                                                                      ***/
    /**************************************************************************************************************************************/
    function getWindowStart(uint256 cycleId_) public view returns (uint256 windowStart_) {
        CycleConfig memory config_ = getConfigAtId(cycleId_);

        windowStart_ = config_.initialCycleTime + (cycleId_ - config_.initialCycleId) * config_.cycleDuration;
    }

     function getConfigAtId(uint256 cycleId_) public view returns (CycleConfig memory config_) {
        uint256 configId_ = latestConfigId;

        if (configId_ == 0) return cycleConfigs[configId_];

        while (cycleId_ < cycleConfigs[configId_].initialCycleId) {
            --configId_;
        }

        config_ = cycleConfigs[configId_];
    }

    function getCurrentConfig() public view returns (CycleConfig memory config_) {
        uint256 configId_ = latestConfigId;

        while (block.timestamp < cycleConfigs[configId_].initialCycleTime) {
            --configId_;
        }

        config_ = cycleConfigs[configId_];
    }

     function getCurrentCycleId() public view returns (uint256 cycleId_) {
        CycleConfig memory config_ = getCurrentConfig();
        cycleId_ = config_.initialCycleId + (block.timestamp - config_.initialCycleTime) / config_.cycleDuration;
    }

    //not required
    function setExitConfig(uint256 cycleDuration_, uint256 windowDuration_) external {
        // require(msg.sender == poolDelegate(),      "WM:SEC:NOT_AUTHORIZED");
        require(windowDuration_ != 0,              "WM:SEC:ZERO_WINDOW");
        require(windowDuration_ <= cycleDuration_, "WM:SEC:WINDOW_OOB");

        // The new config will take effect only after the current cycle and two additional ones elapse.
        // This is done in order to to prevent overlaps between the current and new withdrawal cycles.
        uint256 currentCycleId_   = getCurrentCycleId();
        uint256 initialCycleId_   = currentCycleId_ + 3;
        uint256 initialCycleTime_ = getWindowStart(currentCycleId_);
        uint256 latestConfigId_   = latestConfigId;

        // This isn't the most optimal way to do this, since the internal function `getConfigAt` iterates through configs.
        // But this function should only be called by the pool delegate and not often, and, at most, we need to iterate through 3 cycles.
        for (uint256 i = currentCycleId_; i < initialCycleId_; i++) {
            CycleConfig memory config = getConfigAtId(i);

            initialCycleTime_ += config.cycleDuration;
        }

        // If the new config takes effect on the same cycle as the latest config, overwrite it. Otherwise create a new config.
        if (initialCycleId_ != cycleConfigs[latestConfigId_].initialCycleId) {
            latestConfigId_ = ++latestConfigId;
        }

        cycleConfigs[latestConfigId_] = CycleConfig({
            initialCycleId:   _uint64(0),
            initialCycleTime: _uint64(initialCycleTime_),
            cycleDuration:    _uint64(cycleDuration_),
            windowDuration:   _uint64(windowDuration_)
        });

        emit ConfigurationUpdated({
            configId_:         latestConfigId_,
            initialCycleId_:   _uint64(initialCycleId_),
            initialCycleTime_: _uint64(initialCycleTime_),
            cycleDuration_:    _uint64(cycleDuration_),
            windowDuration_:   _uint64(windowDuration_)
        });
    }

    function addShares(uint256 shares_, address owner_) internal {

        require(shares_ > 0,             "WM:AS:ZERO_SHARES");
        require(requestIds[owner_] == 0, "WM:AS:IN_QUEUE");

        uint128 lastRequestId_ = ++queue.lastRequestId;

        queue.requests[lastRequestId_] = WithdrawalRequest(owner_, shares_);

        requestIds[owner_] = lastRequestId_;

        // Increase the number of shares locked.
        totalShares += shares_;

        require(transferFrom(msg.sender, address(this), shares_), "WM:AS:FAILED_TRANSFER");

    }

    
    function getRedeemableAmounts(uint256 lockedShares_, address owner_)
        public view returns (uint256 redeemableShares_, uint256 resultingAssets_, bool partialLiquidity_)
    {
        // IPoolManagerLike poolManager_ = IPoolManagerLike(poolManager);
       
        redeemableShares_ = lockedShares_;
        partialLiquidity_ = false;
        // uint256 interest = totalAssets()-depositAmount;
        resultingAssets_ = totalAssets();
    }


    function processRedemptions(uint256 maxSharesToProcess_) external nonReentrant {
        require(maxSharesToProcess_ > 0, "WM:PR:ZERO_SHARES");

        ( uint256 redeemableShares_, ) = _calculateRedemption(maxSharesToProcess_);

        // Revert if there are insufficient assets to redeem all shares.
        require(maxSharesToProcess_ == redeemableShares_, "WM:PR:LOW_LIQUIDITY");

        uint128 nextRequestId_ = queue.nextRequestId;
        uint128 lastRequestId_ = queue.lastRequestId;

        // Iterate through the loop and process as many requests as possible.
        // Stop iterating when there are no more shares to process or if you have reached the end of the queue.
        while (maxSharesToProcess_ > 0 && nextRequestId_ <= lastRequestId_) {
            ( uint256 sharesProcessed_, bool isProcessed_ ) = _processRequest(nextRequestId_, maxSharesToProcess_);

            // If the request has not been processed keep it at the start of the queue.
            // This request will be next in line to be processed on the next call.
            if (!isProcessed_) break;

            maxSharesToProcess_ -= sharesProcessed_;

            ++nextRequestId_;
        }

        // Adjust the new start of the queue.
        queue.nextRequestId = nextRequestId_;
    }
    function processExit(
        uint256 shares_,
        address owner_
    )
        public returns (
            uint256 redeemableShares_,
            uint256 resultingAssets_
        )
    {
        ( redeemableShares_, resultingAssets_ ) = owner_ == address(this)
            ? _calculateRedemption(shares_)
            : _processManualExit(shares_, owner_);
    }

    function _calculateRedemption(uint256 sharesToRedeem_) internal view returns (uint256 redeemableShares_, uint256 resultingAssets_) {

        uint256 totalSupply_           = totalSupply();
        uint256 totalAssetsWithLosses_ = totalAssets();
        uint256 availableLiquidity_    = IERC20(asset).balanceOf(address(this));
        uint256 requiredLiquidity_     = totalAssetsWithLosses_ * sharesToRedeem_ / totalSupply_;

        bool partialLiquidity_ = availableLiquidity_ < requiredLiquidity_;

        redeemableShares_ = partialLiquidity_ ? sharesToRedeem_ * availableLiquidity_ / requiredLiquidity_ : sharesToRedeem_;
        resultingAssets_  = totalAssetsWithLosses_ * redeemableShares_  / totalSupply_;
    }

    function _processManualExit(
        uint256 shares_,
        address owner_
    )
        internal returns (
            uint256 redeemableShares_,
            uint256 resultingAssets_
        )
    {
        require(shares_ > 0,                              "WM:PE:NO_SHARES");
        require(shares_ <= manualSharesAvailable[owner_], "WM:PE:TOO_MANY_SHARES");

        ( redeemableShares_ , resultingAssets_ ) = _calculateRedemption(shares_);

        require(shares_ == redeemableShares_, "WM:PE:NOT_ENOUGH_LIQUIDITY");

        manualSharesAvailable[owner_] -= redeemableShares_;


        // Unlock the reserved shares.
        totalShares -= redeemableShares_;

        require(transfer(owner_, redeemableShares_), "WM:PE:TRANSFER_FAIL");
    }

    function _min(uint256 a_, uint256 b_) internal pure returns (uint256 min_) {
        min_ = a_ < b_ ? a_ : b_;
    }

    function _processRequest(
        uint128 requestId_,
        uint256 maximumSharesToProcess_
    )
        internal returns (
            uint256 processedShares_,
            bool    isProcessed_
        )
    {
        WithdrawalRequest memory request_ = queue.requests[requestId_];

        // If the request has already been cancelled, skip it.
        if (request_.owner == address(0)) return (0, true);

        // Process only up to the maximum amount of shares.
        uint256 sharesToProcess_ = _min(request_.shares, maximumSharesToProcess_);

        // Calculate how many shares can actually be redeemed.
        uint256 resultingAssets_;

        ( processedShares_, resultingAssets_ ) = _calculateRedemption(sharesToProcess_);

        // If there are no remaining shares, request has been fully processed.
        isProcessed_ = (request_.shares - processedShares_) == 0;


        // If the request has been fully processed, remove it from the queue.
        if (isProcessed_) {
            // _removeRequest(request_.owner, requestId_);
        } else {
            // Update the withdrawal request.
            queue.requests[requestId_].shares = request_.shares - processedShares_;

        }

        // If the owner opts for manual redemption, increase the account's available shares.
        if (isManualWithdrawal[request_.owner]) {
            manualSharesAvailable[request_.owner] += processedShares_;

        } else {
            // Otherwise, just adjust totalShares and perform the redeem.
            totalShares -= processedShares_;

            redeem(processedShares_, request_.owner, address(this));
        }
    }

   

    // /**************************************************************************************************************************************/
    // /*** LP Functions                                                                                                                   ***/
    // /**************************************************************************************************************************************/

    function deposit(uint256 assets_, address receiver_) external nonReentrant returns (uint256 shares_) {
        
        startTime = block.timestamp;
        _mint(shares_ = previewDeposit(assets_), assets_, receiver_, msg.sender);
    }

    function redeem(uint256 shares_, address receiver_, address owner_)
        public nonReentrant returns (uint256 assets_)
    {
        uint256 redeemableShares_;
        require(owner_ == msg.sender, "PM:PR:NOT_OWNER");

        // ( redeemableShares_, assets_ ) = IPoolManagerLike(manager).processRedeem(shares_, owner_, msg.sender);
        ( redeemableShares_, assets_ ) = processExit(shares_, owner_);
        _burn(redeemableShares_, assets_, receiver_, owner_, msg.sender);
    }

    function requestRedeem(uint256 shares_, address owner_)
        external nonReentrant returns (uint256 escrowedShares_)
    {
        // emit RedemptionRequested(
        //     owner_,
        //     shares_,
        escrowedShares_ = _requestRedeem(shares_, owner_);
        // );
    }

   function removeShares(uint256 shares_, address owner_)
        external nonReentrant returns (uint256 sharesReturned_)
    {

        sharesReturned_ = _removeShares(shares_, owner_);
    }

    function requests(uint256 reqId_) external view returns (address user_, uint256 shares_) {
        user_ = msg.sender;
        shares_ = lockedShares[msg.sender];
    }

    // /**************************************************************************************************************************************/
    // /*** Internal Functions                                                                                                             ***/
    // /**************************************************************************************************************************************/

    function _removeShares(uint256 shares_, address owner_) internal returns(uint256 sharesRemoved_) {
        uint256 exitCycleId_  = exitCycleId[owner_];
        uint256 lockedShares_ = lockedShares[owner_];

        require(block.timestamp >= getWindowStart(exitCycleId_), "WM:RS:WITHDRAWAL_PENDING");
        require(shares_ != 0 && shares_ <= lockedShares_,        "WM:RS:SHARES_OOB");

        // Remove shares from old the cycle.
        totalCycleShares[exitCycleId_] -= lockedShares_;

        // Calculate remaining shares and new cycle (if applicable).
        lockedShares_ -= shares_;
        exitCycleId_   = lockedShares_ != 0 ? getCurrentCycleId() + 2 : 0;

        // Add shares to new cycle (if applicable).
        if (lockedShares_ != 0) {
            totalCycleShares[exitCycleId_] += lockedShares_;
        }

        // Update the withdrawal request.
        exitCycleId[owner_]  = exitCycleId_;
        lockedShares[owner_] = lockedShares_;

        sharesRemoved_ = shares_;

        _transfer(address(this), owner_, shares_);
    }
    function _burn(uint256 shares_, uint256 assets_, address receiver_, address owner_, address caller_) internal {
        require(receiver_ != address(0), "P:B:ZERO_RECEIVER");

        if (shares_ == 0) return;

        // if (caller_ != owner_) {
        //     _decreaseAllowance(owner_, caller_, shares_);
        // }
        _burn(address(this), shares_);

        // emit Withdraw(caller_, receiver_, owner_, assets_, shares_);
        IERC20Helper(asset).mint(address(this), assets_- depositAmount);
        ERC20Upgradeable(asset).transfer(receiver_, assets_);
        depositAmount = 0;
        // require(ERC20Helper.transfer(asset, receiver_, assets_), "P:B:TRANSFER");
    }

    function _divRoundUp(uint256 numerator_, uint256 divisor_) internal pure returns (uint256 result_) {
        result_ = (numerator_ + divisor_ - 1) / divisor_;
    }

    function _mint(uint256 shares_, uint256 assets_, address receiver_, address caller_) internal {
        require(receiver_ != address(0), "P:M:ZERO_RECEIVER");
        require(shares_   != uint256(0), "P:M:ZERO_SHARES");
        require(assets_   != uint256(0), "P:M:ZERO_ASSETS");

        _mint(receiver_, shares_);

        // emit Deposit(caller_, receiver_, assets_, shares_);

        ERC20Upgradeable(asset).transferFrom(caller_, address(this), assets_);
        depositAmount += assets_;

    }

    function _requestRedeem(uint256 shares_, address owner_) internal returns (uint256 escrowShares_) {
        address destination_;

        ( escrowShares_, destination_ ) = (shares_, address(this));

    
        if (escrowShares_ != 0 && destination_ != address(0)) {
            _transfer(owner_, destination_, escrowShares_);
        }

        addShares(escrowShares_, owner_);
     
    }

    function convertToAssets(uint256 shares_) public view returns (uint256 assets_) {
        uint256 totalSupply_ = totalSupply();

        assets_ = totalSupply_ == 0 ? shares_ : (shares_ * totalAssets()) / totalSupply_;
    }

    function convertToExitAssets(uint256 shares_) public view returns (uint256 assets_) {
        uint256 totalSupply_ = totalSupply();

        assets_ = totalSupply_ == 0 ? shares_ : shares_ * totalAssets() / totalSupply_;
    }

    function convertToShares(uint256 assets_) public view returns (uint256 shares_) {
        uint256 totalSupply_ = totalSupply();

        shares_ = totalSupply_ == 0 ? assets_ : (assets_ * totalSupply_) / totalAssets();
    }

    function convertToExitShares(uint256 amount_) public view returns (uint256 shares_) {
        shares_ = _divRoundUp(amount_ * totalSupply(), totalAssets());
    }

    function previewDeposit(uint256 assets_) public view returns (uint256 shares_) {
        // As per https://eips.ethereum.org/EIPS/eip-4626#security-considerations,
        // it should round DOWN if it’s calculating the amount of shares to issue to a user, given an amount of assets provided.
        shares_ = convertToShares(assets_);
    }


    function totalAssets() public view returns (uint256 totalAssets_) {
        totalAssets_ = depositAmount;
        totalAssets_ += ((totalAssets_ * (block.timestamp - startTime) * interest) / 1e17);

    }

    function _uint64(uint256 input_) internal pure returns (uint64 output_) {
        require(input_ <= type(uint64).max, "WM:UINT64_CAST_OOB");
        output_ = uint64(input_);
    }

}
