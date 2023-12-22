// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.21;

import { ERC20 }       from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
// import { ERC20Helper } from "../modules/erc20-helper/src/ERC20Helper.sol";
import { Test, console } from "forge-std/Test.sol";
import { IPoolManagerLike } from "./interfaces/Interfaces.sol";
import { IERC20, IPool }    from "./interfaces/IPool.sol";

/*

    ██████╗  ██████╗  ██████╗ ██╗
    ██╔══██╗██╔═══██╗██╔═══██╗██║
    ██████╔╝██║   ██║██║   ██║██║
    ██╔═══╝ ██║   ██║██║   ██║██║
    ██║     ╚██████╔╝╚██████╔╝███████╗
    ╚═╝      ╚═════╝  ╚═════╝ ╚══════╝

*/

contract Pool is ERC20 {

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

    uint256 public depositAmount;
    uint256 public latestConfigId = 2;
    mapping(address => uint256) public exitCycleId;
    mapping(address => uint256) public lockedShares;
    mapping(uint256 => CycleConfig) public cycleConfigs;
    mapping(uint256 => uint256) public totalCycleShares;




    uint256 public immutable BOOTSTRAP_MINT;

    address public asset;    // Underlying ERC-20 asset handled by the ERC-4626 contract.
    // address public manager;  // Address of the contract that manages administrative functionality.
    uint256 startTime;
    uint256 interest = 158_548_961;
    uint256 private _locked = 1;  // Used when checking for reentrancy.

    constructor(
        // address manager_,
        address asset_,
        // address destination_,
        // uint256 bootstrapMint_,
        // uint256 initialSupply_,
        string memory name_,
        string memory symbol_
    )
        ERC20(name_, symbol_)
    {
        // require((manager = manager_) != address(0), "P:C:ZERO_MANAGER");
        require((asset   = asset_)   != address(0), "P:C:ZERO_ASSET");
        cycleConfigs[latestConfigId] = CycleConfig({
            initialCycleId:   _uint64(24),
            initialCycleTime: _uint64(1683831600),
            cycleDuration:    _uint64(86400),
            windowDuration:   _uint64(54000)
        });

        emit ConfigurationUpdated({
            configId_:         latestConfigId,
            initialCycleId_:   _uint64(24),
            initialCycleTime_: _uint64(1683831600),
            cycleDuration_:    _uint64(86400),
            windowDuration_:   _uint64(54000)
        });
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

        // ERC20(address(this)).transferFrom(msg.sender, address(this), shares_);

        // _emitUpdate(owner_, lockedShares_, exitCycleId_);
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

        // Calculate how much liquidity is available, and how much is required to allow redemption of shares.
        uint256 availableLiquidity_      = ERC20(asset).balanceOf(address(this));
        uint256 totalAssetsWithLosses_   = totalAssets();
        uint256 totalSupply_             = totalSupply();
        uint256 totalRequestedLiquidity_ = totalCycleShares[exitCycleId[owner_]] * totalAssetsWithLosses_ / totalSupply_;

        partialLiquidity_ = availableLiquidity_ < totalRequestedLiquidity_;

        // Calculate maximum redeemable shares while maintaining a pro-rata distribution.
        redeemableShares_ =
            partialLiquidity_
                ? lockedShares_ * availableLiquidity_ / totalRequestedLiquidity_
                : lockedShares_;

        resultingAssets_ = redeemableShares_ * totalAssetsWithLosses_ / totalSupply_;
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

        // _emitProcess(owner_, redeemableShares_, resultingAssets_);
        // _emitUpdate(owner_, lockedShares_, exitCycleId_);
    }

    /**************************************************************************************************************************************/
    /*** Modifiers                                                                                                                      ***/
    /**************************************************************************************************************************************/

    // modifier checkCall(bytes32 functionId_) {
    //     ( bool success_, string memory errorMessage_ ) = IPoolManagerLike(manager).canCall(functionId_, msg.sender, msg.data[4:]);

    //     require(success_, errorMessage_);

    //     _;
    // }

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
        if(totalSupply() == 0){
            startTime = block.timestamp;
        }
        _mint(shares_ = previewDeposit(assets_), assets_, receiver_, msg.sender);
    }

    // function mint(uint256 shares_, address receiver_) external override nonReentrant checkCall("P:mint") returns (uint256 assets_) {
    //     _mint(shares_, assets_ = previewMint(shares_), receiver_, msg.sender);
    // }

    function redeem(uint256 shares_, address receiver_, address owner_)
        external nonReentrant returns (uint256 assets_)
    {
        uint256 redeemableShares_;
        require(owner_ == msg.sender, "PM:PR:NOT_OWNER");

        // ( redeemableShares_, assets_ ) = IPoolManagerLike(manager).processRedeem(shares_, owner_, msg.sender);
        ( redeemableShares_, assets_ ) = processExit(shares_, owner_);
        console.log("BURN se phle");
        _burn(redeemableShares_, assets_, receiver_, owner_, msg.sender);
        depositAmount -= assets_;
    }

    // function withdraw(uint256 assets_, address receiver_, address owner_)
    //     external override nonReentrant checkCall("P:withdraw") returns (uint256 shares_)
    // {
    //     ( shares_, assets_ ) = IPoolManagerLike(manager).processWithdraw(assets_, owner_, msg.sender);
    //     _burn(shares_, assets_, receiver_, owner_, msg.sender);
    // }

    // /**************************************************************************************************************************************/
    // /*** Withdrawal Request Functions                                                                                                   ***/
    // /**************************************************************************************************************************************/

    // function removeShares(uint256 shares_, address owner_)
    //     external override nonReentrant checkCall("P:removeShares") returns (uint256 sharesReturned_)
    // {
    //     if (msg.sender != owner_) _decreaseAllowance(owner_, msg.sender, shares_);

    //     emit SharesRemoved(
    //         owner_,
    //         sharesReturned_ = IPoolManagerLike(manager).removeShares(shares_, owner_)
    //     );
    // }

    function requestRedeem(uint256 shares_, address owner_)
        external nonReentrant returns (uint256 escrowedShares_)
    {
        // emit RedemptionRequested(
        //     owner_,
        //     shares_,
        escrowedShares_ = _requestRedeem(shares_, owner_);
        // );
    }

    // function requestWithdraw(uint256 assets_, address owner_)
    //     external override nonReentrant checkCall("P:requestWithdraw") returns (uint256 escrowedShares_)
    // {
    //     emit WithdrawRequested(
    //         owner_,
    //         assets_,
    //         escrowedShares_ = _requestWithdraw(assets_, owner_)
    //     );
    // }

    // /**************************************************************************************************************************************/
    // /*** Internal Functions                                                                                                             ***/
    // /**************************************************************************************************************************************/

    function _burn(uint256 shares_, uint256 assets_, address receiver_, address owner_, address caller_) internal {
        require(receiver_ != address(0), "P:B:ZERO_RECEIVER");

        if (shares_ == 0) return;

        // if (caller_ != owner_) {
        //     _decreaseAllowance(owner_, caller_, shares_);
        // }
        console.log("BURN fat rha h");
        _burn(address(this), shares_);

        // emit Withdraw(caller_, receiver_, owner_, assets_, shares_);
        console.log("YHN tk chal gya");
        ERC20(asset).transfer(receiver_, assets_);
        console.log("YHN tk bhi chal gya");
        // require(ERC20Helper.transfer(asset, receiver_, assets_), "P:B:TRANSFER");
    }

    // function _divRoundUp(uint256 numerator_, uint256 divisor_) internal pure returns (uint256 result_) {
    //     result_ = (numerator_ + divisor_ - 1) / divisor_;
    // }

    function _mint(uint256 shares_, uint256 assets_, address receiver_, address caller_) internal {
        require(receiver_ != address(0), "P:M:ZERO_RECEIVER");
        require(shares_   != uint256(0), "P:M:ZERO_SHARES");
        require(assets_   != uint256(0), "P:M:ZERO_ASSETS");

        _mint(receiver_, shares_);

        // emit Deposit(caller_, receiver_, assets_, shares_);

        ERC20(asset).transferFrom(caller_, address(this), assets_);
        depositAmount += assets_;

    }

    function _requestRedeem(uint256 shares_, address owner_) internal returns (uint256 escrowShares_) {
        address destination_;

        ( escrowShares_, destination_ ) = (shares_, address(this));

        // if (msg.sender != owner_) {
        //     _decreaseAllowance(owner_, msg.sender, escrowShares_);
        // }

        if (escrowShares_ != 0 && destination_ != address(0)) {
            _transfer(owner_, destination_, escrowShares_);
        }
        addShares(escrowShares_, owner_);

        // IPoolManagerLike(manager).requestRedeem(escrowShares_, owner_, msg.sender);
    }

    // function _requestWithdraw(uint256 assets_, address owner_) internal returns (uint256 escrowShares_) {
    //     address destination_;

    //     ( escrowShares_, destination_ ) = IPoolManagerLike(manager).getEscrowParams(owner_, convertToExitShares(assets_));

    //     if (msg.sender != owner_) {
    //         _decreaseAllowance(owner_, msg.sender, escrowShares_);
    //     }

    //     if (escrowShares_ != 0 && destination_ != address(0)) {
    //         _transfer(owner_, destination_, escrowShares_);
    //     }

    //     IPoolManagerLike(manager).requestWithdraw(escrowShares_, assets_, owner_, msg.sender);
    // }

    // /**************************************************************************************************************************************/
    // /*** External View Functions                                                                                                        ***/
    // /**************************************************************************************************************************************/

    // function balanceOfAssets(address account_) external view override returns (uint256 balanceOfAssets_) {
    //     balanceOfAssets_ = convertToAssets(balanceOf[account_]);
    // }

    // function maxDeposit(address receiver_) external view override returns (uint256 maxAssets_) {
    //     maxAssets_ = IPoolManagerLike(manager).maxDeposit(receiver_);
    // }

    // function maxMint(address receiver_) external view override returns (uint256 maxShares_) {
    //     maxShares_ = IPoolManagerLike(manager).maxMint(receiver_);
    // }

    // function maxRedeem(address owner_) external view override returns (uint256 maxShares_) {
    //     maxShares_ = IPoolManagerLike(manager).maxRedeem(owner_);
    // }

    // function maxWithdraw(address owner_) external view override returns (uint256 maxAssets_) {
    //     maxAssets_ = IPoolManagerLike(manager).maxWithdraw(owner_);
    // }

    // function previewRedeem(uint256 shares_) external view override returns (uint256 assets_) {
    //     assets_ = IPoolManagerLike(manager).previewRedeem(msg.sender, shares_);
    // }

    // function previewWithdraw(uint256 assets_) external view override returns (uint256 shares_) {
    //     shares_ = IPoolManagerLike(manager).previewWithdraw(msg.sender, assets_);
    // }

    // /**************************************************************************************************************************************/
    // /*** Public View Functions                                                                                                          ***/
    // /**************************************************************************************************************************************/

    // function convertToAssets(uint256 shares_) public view override returns (uint256 assets_) {
    //     uint256 totalSupply_ = totalSupply;

    //     assets_ = totalSupply_ == 0 ? shares_ : (shares_ * totalAssets()) / totalSupply_;
    // }

    // function convertToExitAssets(uint256 shares_) public view override returns (uint256 assets_) {
    //     uint256 totalSupply_ = totalSupply;

    //     assets_ = totalSupply_ == 0 ? shares_ : shares_ * (totalAssets() - unrealizedLosses()) / totalSupply_;
    // }

    function convertToShares(uint256 assets_) public view returns (uint256 shares_) {
        uint256 totalSupply_ = totalSupply();

        shares_ = totalSupply_ == 0 ? assets_ : (assets_ * totalSupply_) / totalAssets();
    }

    // function convertToExitShares(uint256 amount_) public view override returns (uint256 shares_) {
    //     shares_ = _divRoundUp(amount_ * totalSupply, totalAssets() - unrealizedLosses());
    // }

    function previewDeposit(uint256 assets_) public view returns (uint256 shares_) {
        // As per https://eips.ethereum.org/EIPS/eip-4626#security-considerations,
        // it should round DOWN if it’s calculating the amount of shares to issue to a user, given an amount of assets provided.
        shares_ = convertToShares(assets_);
    }

    // function previewMint(uint256 shares_) public view override returns (uint256 assets_) {
    //     uint256 totalSupply_ = totalSupply;

    //     // As per https://eips.ethereum.org/EIPS/eip-4626#security-considerations,
    //     // it should round UP if it’s calculating the amount of assets a user must provide, to be issued a given amount of shares.
    //     assets_ = totalSupply_ == 0 ? shares_ : _divRoundUp(shares_ * totalAssets(), totalSupply_);
    // }

    function totalAssets() public view returns (uint256 totalAssets_) {
        totalAssets_ = depositAmount;
        totalAssets_ += ((totalAssets_ * (block.timestamp - startTime) * interest) / 1e17);

    }

    // function unrealizedLosses() public view override returns (uint256 unrealizedLosses_) {
    //     unrealizedLosses_ = IPoolManagerLike(manager).unrealizedLosses();
    // }

    function _uint64(uint256 input_) internal pure returns (uint64 output_) {
        require(input_ <= type(uint64).max, "WM:UINT64_CAST_OOB");
        output_ = uint64(input_);
    }

}
