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
    uint64 public ver;
    function initialize(uint64 version_) external reinitializer(version_){
        ver = version_;
    }
    // function initialize(
    //     address asset_,
    //     string memory name_,
    //     string memory symbol_
    // ) external initializer
    // {   
    //     __ERC20_init(name_, symbol_);

    //     require((asset   = asset_)   != address(0), "P:C:ZERO_ASSET");
    //     liquidityCap = 1e9*1e6;
    //     decimal = ERC20Upgradeable(asset).decimals();
    //     latestConfigId = 2;
    //     cycleConfigs[latestConfigId] = CycleConfig({
    //         initialCycleId:   _uint64(24),
    //         initialCycleTime: _uint64(block.timestamp),
    //         cycleDuration:    _uint64(120), //change to 2 mins
    //         windowDuration:   _uint64(60) //change to 1 mins
    //     });

    //     emit ConfigurationUpdated({
    //         configId_:         latestConfigId,
    //         initialCycleId_:   _uint64(24),
    //         initialCycleTime_: _uint64(block.timestamp),
    //         cycleDuration_:    _uint64(120),
    //         windowDuration_:   _uint64(60)
    //     });

    //     interest = 158_548_961;
    //     _locked = 1;

    // }

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

        uint256 exitCycleId_  = exitCycleId[owner_];
        uint256 lockedShares_ = lockedShares[owner_];

        require(lockedShares_ == 0 || block.timestamp >= getWindowStart(exitCycleId_), "WM:AS:WITHDRAWAL_PENDING");

        // Remove all existing shares from the current cycle.
        totalCycleShares[exitCycleId_] -= lockedShares_;

        lockedShares_ += shares_;

        require(lockedShares_ != 0, "WM:AS:NO_OP");

        // Move all shares (including any new ones) to the new cycle.
        exitCycleId_ = getCurrentCycleId() + 2;

        totalCycleShares[exitCycleId_] += lockedShares_;

        exitCycleId[owner_]  = exitCycleId_;
        lockedShares[owner_] = lockedShares_;

    }

    function getWindowAtId(uint256 cycleId_) public view returns (uint256 windowStart_, uint256 windowEnd_) {
        CycleConfig memory config_ = getConfigAtId(cycleId_);

        windowStart_ = config_.initialCycleTime + (cycleId_ - config_.initialCycleId) * config_.cycleDuration;
        windowEnd_   = windowStart_ + config_.windowDuration;
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


     function processExit(uint256 requestedShares_, address owner_)
        internal returns (uint256 redeemableShares_, uint256 resultingAssets_)
    {

        uint256 exitCycleId_  = exitCycleId[owner_];
        uint256 lockedShares_ = lockedShares[owner_];

        require(lockedShares_ != 0, "WM:PE:NO_REQUEST");

        require(requestedShares_ == lockedShares_, "WM:PE:INVALID_SHARES");

        bool partialLiquidity_;

        ( uint256 windowStart_, uint256 windowEnd_ ) = getWindowAtId(exitCycleId_);

        require(block.timestamp >= windowStart_ && block.timestamp <  windowEnd_, "WM:PE:NOT_IN_WINDOW");

        ( redeemableShares_, resultingAssets_, partialLiquidity_ ) = getRedeemableAmounts(lockedShares_, owner_);

        // Transfer redeemable shares to be burned in the pool, re-lock remaining shares.
        // require(ERC20Helper.transfer(pool, owner_, redeemableShares_), "WM:PE:TRANSFER_FAIL");

        // Reduce totalCurrentShares by the shares that were used in the old cycle.
        totalCycleShares[exitCycleId_] -= lockedShares_;

        // Reduce the locked shares by the total amount transferred back to the LP.
        lockedShares_ -= redeemableShares_;

        // If there are any remaining shares, move them to the next cycle.
        // In case of partial liquidity move shares only one cycle forward (instead of two).
        if (lockedShares_ != 0) {
            exitCycleId_ = getCurrentCycleId() + (partialLiquidity_ ? 1 : 2);
            totalCycleShares[exitCycleId_] += lockedShares_;
        } else {
            exitCycleId_ = 0;
        }

        // Update the locked shares and cycle for the account, setting to zero if no shares are remaining.
        lockedShares[owner_] = lockedShares_;
        exitCycleId[owner_]  = exitCycleId_;

    }

    modifier nonReentrant() {
        require(_locked == 1, "P:LOCKED");

        _locked = 2;

        _;

        _locked = 1;
    }

    // /**************************************************************************************************************************************/
    // /*** LP Functions                                                                                                                   ***/
    // /**************************************************************************************************************************************/

    function deposit(uint256 assets_, address receiver_) external nonReentrant returns (uint256 shares_) {
        
        startTime = block.timestamp;
        _mint(shares_ = previewDeposit(assets_), assets_, receiver_, msg.sender);
    }

    function redeem(uint256 shares_, address receiver_, address owner_)
        external nonReentrant returns (uint256 assets_)
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
