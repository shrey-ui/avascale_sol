// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";

import "./libraries/Decimals.sol";
import "./interfaces/IOracle.sol";

contract AvascaleStaking is Ownable {
    using SafeERC20 for IERC20;
    using SafeMath for uint256;

    /*************
     ** Structs **
     *************/

    // Info of each user.
    struct UserInfo {
        uint256 amount; // How many LP tokens the user has provided.
        uint256 rewardDebt; // Reward debt. See explanation below.
        //
        // We do some fancy math here. Basically, any point in time, the amount of AVASCALEs
        // entitled to a user but is pending to be distributed is:
        //
        //   pending reward = (user.amount * pool.accAvascalePerShare) - user.rewardDebt
        //
        // Whenever a user deposits or withdraws LP tokens to a pool. Here's what happens:
        //   1. The pool's `accAvascalePerShare` (and `lastRewardBlock`) gets updated.
        //   2. User receives the pending reward sent to his/her address.
        //   3. User's `amount` gets updated.
        //   4. User's `rewardDebt` gets updated.
    }

    // Info of each pool.
    struct PoolInfo {
        IERC20 lpToken; // Address of LP token contract.
        uint256 allocPoint; // How many allocation points assigned to this pool. AVASCALEs to distribute per block.
        uint256 lastRewardBlock; // Last block number that AVASCALEs distribution occurs.
        uint256 accAvascalePerShare; // Accumulated AVASCALEs per share, times 1e12. See below.
    }

    /*************
     ** Storage **
     *************/

    // The Avascale TOKEN!
    IERC20 public avascale;
    // Avascale ONE LP Pool
    IERC20 public lp;
    // Avascale USD Oracle
    IOracle public oracle;

    // Avascale tokens distributed per block.
    uint256 public avascalePerBlock = 0;
    // Bonus muliplier for early avascale stakers.
    uint256 public constant BONUS_MULTIPLIER = 1;

    // Info of each pool.
    PoolInfo[] public poolInfo;
    // Info of each user that stakes LP tokens.
    mapping(uint256 => mapping(address => UserInfo)) public userInfo;
    // Total allocation points. Must be the sum of all allocation points in all pools.
    uint256 public totalAllocPoint = 0;
    // The block number when AVASCALE mining starts.
    uint256 public startBlock;
    // % Avascale rewards per year for holders
    uint256 public rewardsBP = 1500; // 15 %
    // Blocks per year in wei
    uint256 public blocksPerYear; // 15 %

    /************
     ** Events **
     ************/

    event Deposit(address indexed user, uint256 indexed pid, uint256 amount);
    event Withdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event EmergencyWithdraw(
        address indexed user,
        uint256 indexed pid,
        uint256 amount
    );

    /*****************
     ** Constructor **
     *****************/

    constructor(
        IERC20 _avascale,
        IERC20 _lp,
        IOracle _oracle,
        uint256 _blocksPerYear,
        uint256 _startBlock
    ) {
        avascale = _avascale;
        lp = _lp;
        oracle = _oracle;
        blocksPerYear = _blocksPerYear;
        startBlock = _startBlock;
        add(100, _lp, true);
    }

    /*************
     ** Ownable **
     *************/

    function removeAvascaleReserves(uint256 _amount) external onlyOwner {
        uint256 _avascaleBalance = avascale.balanceOf(address(this));

        if (_amount > _avascaleBalance) {
            avascale.transfer(owner(), _avascaleBalance);
        } else {
            avascale.transfer(owner(), _amount);
        }
    }

    function setAvascaleOracle(IOracle _newAvascaleOracle) external onlyOwner {
        oracle = _newAvascaleOracle;
    }

    function updateRewardsBP(uint256 _rewardsBP) external onlyOwner {
        rewardsBP = _rewardsBP;
        avascalePerBlock = getOptimalEmissionRate();
    }

    function updateBlocksPerYear(uint256 _blocksPerYear) external onlyOwner {
        blocksPerYear = _blocksPerYear;
        avascalePerBlock = getOptimalEmissionRate();
    }

    // Update the given pool's AVASCALE allocation point and deposit fee. Can only be called by the owner.
    function set(
        uint256 _pid,
        uint256 _allocPoint,
        bool _withUpdate
    ) public onlyOwner {
        if (_withUpdate) {
            massUpdatePools();
        }
        totalAllocPoint = totalAllocPoint.sub(poolInfo[_pid].allocPoint).add(
            _allocPoint
        );
        poolInfo[_pid].allocPoint = _allocPoint;
    }

    /************
     ** Public **
     ************/

    function getUsdDeposited() public view returns (uint256) {
        uint256 _lpSupply = lp.totalSupply();
        uint256 _lpDeposited = lp.balanceOf(address(this));
        uint256 _avascaleInLp = avascale.balanceOf(address(lp));

        uint256 _avascaleUsdPrice = Decimals.formatFromToDecimals(
            8,
            18,
            oracle.getPrice()
        );

        uint256 _avascalePerLp = Decimals.divWithPrecision(
            _avascaleInLp,
            _lpSupply,
            18
        );
        uint256 _avascaleInPool = Decimals.formatFromToDecimals(
            36,
            18,
            _lpDeposited * _avascalePerLp
        );
        uint256 _usdDeposited = Decimals.formatFromToDecimals(
            36,
            18,
            _avascaleInPool * _avascaleUsdPrice * 2
        );
        return _usdDeposited;
    }

    function getOptimalEmissionRate() public view returns (uint256) {
        uint256 _usdDeposited = getUsdDeposited();
        uint256 _usdNeeded = (_usdDeposited * rewardsBP) / 10000;
        uint256 _avascaleUsdPrice = Decimals.formatFromToDecimals(
            8,
            18,
            oracle.getPrice()
        );
        uint256 _avascaleNeededPerYear = Decimals.divWithPrecision(
            _usdNeeded,
            _avascaleUsdPrice,
            18
        );

        uint256 _avascaleNeededPerBlock = Decimals.divWithPrecision(
            _avascaleNeededPerYear,
            blocksPerYear,
            18
        );

        return _avascaleNeededPerBlock;
    }

    // Return reward multiplier over the given _from to _to block.
    function getMultiplier(uint256 _from, uint256 _to)
        public
        pure
        returns (uint256)
    {
        return _to.sub(_from).mul(BONUS_MULTIPLIER);
    }

    // Update reward variables for all pools. Be careful of gas spending!
    function massUpdatePools() public {
        uint256 length = poolInfo.length;
        for (uint256 pid = 0; pid < length; ++pid) {
            updatePool(pid);
        }
    }

    // Update reward variables of the given pool to be up-to-date.
    function updatePool(uint256 _pid) public {
        PoolInfo storage pool = poolInfo[_pid];

        avascalePerBlock = getOptimalEmissionRate();
        if (block.number <= pool.lastRewardBlock) {
            return;
        }
        uint256 lpSupply = pool.lpToken.balanceOf(address(this));
        if (lpSupply == 0 || pool.allocPoint == 0) {
            pool.lastRewardBlock = block.number;
            return;
        }
        uint256 multiplier = getMultiplier(pool.lastRewardBlock, block.number);
        uint256 avascaleReward = multiplier
            .mul(avascalePerBlock)
            .mul(pool.allocPoint)
            .div(totalAllocPoint);
        /// @dev doesn't need mint
        pool.accAvascalePerShare = pool.accAvascalePerShare.add(
            avascaleReward.mul(1e12).div(lpSupply)
        );
        pool.lastRewardBlock = block.number;
    }

    // Deposit LP tokens to MasterChef for AVASCALE allocation.
    function deposit(uint256 _pid, uint256 _amount) public {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        updatePool(_pid);
        if (user.amount > 0) {
            uint256 pending = user
                .amount
                .mul(pool.accAvascalePerShare)
                .div(1e12)
                .sub(user.rewardDebt);
            if (pending > 0) {
                safeAvascaleTransfer(msg.sender, pending);
            }
        }
        if (_amount > 0) {
            pool.lpToken.safeTransferFrom(
                address(msg.sender),
                address(this),
                _amount
            );

            user.amount = user.amount.add(_amount);
        }
        user.rewardDebt = user.amount.mul(pool.accAvascalePerShare).div(1e12);
        emit Deposit(msg.sender, _pid, _amount);
    }

    // Withdraw LP tokens from MasterChef.
    function withdraw(uint256 _pid, uint256 _amount) public {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        require(user.amount >= _amount, "withdraw: not good");
        updatePool(_pid);
        uint256 pending = user.amount.mul(pool.accAvascalePerShare).div(1e12).sub(
            user.rewardDebt
        );
        if (pending > 0) {
            safeAvascaleTransfer(msg.sender, pending);
        }
        if (_amount > 0) {
            user.amount = user.amount.sub(_amount);
            pool.lpToken.safeTransfer(address(msg.sender), _amount);
        }
        user.rewardDebt = user.amount.mul(pool.accAvascalePerShare).div(1e12);
        emit Withdraw(msg.sender, _pid, _amount);
    }

    // Withdraw without caring about rewards. EMERGENCY ONLY.
    function emergencyWithdraw(uint256 _pid) public {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        uint256 amount = user.amount;
        user.amount = 0;
        user.rewardDebt = 0;
        pool.lpToken.safeTransfer(address(msg.sender), amount);
        emit EmergencyWithdraw(msg.sender, _pid, amount);
    }

    /**************
     ** External **
     **************/

    function poolLength() external view returns (uint256) {
        return poolInfo.length;
    }

    // View function to see pending AVASCALEs on frontend.
    function pendingAvascale(uint256 _pid, address _user)
        external
        view
        returns (uint256)
    {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_user];
        uint256 accAvascalePerShare = pool.accAvascalePerShare;
        uint256 lpSupply = pool.lpToken.balanceOf(address(this));
        if (block.number > pool.lastRewardBlock && lpSupply != 0) {
            uint256 multiplier = getMultiplier(
                pool.lastRewardBlock,
                block.number
            );
            uint256 avascaleReward = multiplier
                .mul(avascalePerBlock)
                .mul(pool.allocPoint)
                .div(totalAllocPoint);
            accAvascalePerShare = accAvascalePerShare.add(
                avascaleReward.mul(1e12).div(lpSupply)
            );
        }
        return user.amount.mul(accAvascalePerShare).div(1e12).sub(user.rewardDebt);
    }

    function getAvascalePerBlock() external view returns (uint256) {
        return avascalePerBlock;
    }

    /**************
     ** Internal **
     **************/

    // Safe avascale transfer function, just in case if rounding error causes pool to not have enough AVASCALEs.
    function safeAvascaleTransfer(address _to, uint256 _amount) internal {
        uint256 avascaleBal = avascale.balanceOf(address(this));
        if (_amount > avascaleBal) {
            avascale.transfer(_to, avascaleBal);
        } else {
            avascale.transfer(_to, _amount);
        }
    }

    /*************
     ** Private **
     *************/

    // Add a new lp to the pool
    // XXX This masterchef only supports one pool
    function add(
        uint256 _allocPoint,
        IERC20 _lpToken,
        bool _withUpdate
    ) private {
        require(poolInfo.length < 1, "MasterChef: length >= 1");
        if (_withUpdate) {
            massUpdatePools();
        }
        uint256 lastRewardBlock = block.number > startBlock
            ? block.number
            : startBlock;
        totalAllocPoint = totalAllocPoint.add(_allocPoint);
        poolInfo.push(
            PoolInfo({
                lpToken: _lpToken,
                allocPoint: _allocPoint,
                lastRewardBlock: lastRewardBlock,
                accAvascalePerShare: 0
            })
        );
    }
}
