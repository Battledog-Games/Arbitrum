// SPDX-License-Identifier: MIT
/**
 * @title Incentivizer Contract
 */
pragma solidity ^0.8.17;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";


contract Harvester is Ownable, ReentrancyGuard {
    IERC20 public AIGAMEToken;
    IERC20 public payToken;
    uint256 public totalRewards = 1;
    uint256 public totalClaimedRewards; 
    uint256 public startTime;
    uint256 public rewardPerStamp;
    uint256 public numberOfParticipants = 0;
    uint256 private _startTime;
    uint256 private _duration;
    uint256 public Duration = duration();
    uint256 public timeLock = 3 days;
    uint256 public TotalAIGAMESent = 1;
    uint256 public tax = 0;
    uint256 public TaxTotal = 0;
    uint256 private divisor = 100 ether;
    address private guard; 
    bool public paused = false; 

    mapping(address => uint256) public balances;
    mapping(address => Claim) public claimRewards;
    mapping(address => uint256) public entryMap;
    mapping(address => uint256) public UserClaims;
    mapping(address => uint256) public blacklist;
    mapping(address => uint256) public Claimants;

    address[] public participants;

    struct Claim {
        uint256 eraAtBlock;
        uint256 AIGAMESent;
        uint256 rewardsOwed;
    }
    
    event RewardAddedByDev(uint256 amount);
    event RewardClaimedByUser(address indexed user, uint256 amount);
    event AddAIGAME(address indexed user, uint256 amount);
    event WithdrawAIGAME(address indexed user, uint256 amount);
    
    constructor(
        address _AIGAMEToken,
        address _payToken,
        address _newGuard
    ) {
        AIGAMEToken = IERC20(_AIGAMEToken);
        payToken = IERC20(_payToken);
        guard = _newGuard;
        startTime = block.timestamp;
    }

    modifier onlyGuard() {
        require(msg.sender == guard, "Not authorized.");
        _;
    }

    modifier onlyAfterTimelock() {             
        require(entryMap[msg.sender] + timeLock < block.timestamp, "Timelocked.");
        _;
    }

    modifier onlyClaimant() {             
        require(UserClaims[msg.sender] + timeLock < block.timestamp, "Timelocked.");
        _;
    }

    function addAIGAME(uint256 _amount) public nonReentrant {
        require(!paused, "Contract is paused.");
        require(_amount > 0, "Amount must be greater than zero.");
        require(blacklist[msg.sender] == 0, "Address is blacklisted.");
        require(AIGAMEToken.transferFrom(msg.sender, address(this), _amount), "Transfer failed.");
        Claim storage claimData = claimRewards[msg.sender];
        uint256 toll = (_amount * tax)/100;
        uint256 amount = _amount - toll;
        TaxTotal += toll;
        uint256 currentBalance = balances[msg.sender];
        uint256 newBalance = currentBalance + amount;
        balances[msg.sender] = newBalance;
        entryMap[msg.sender] = block.timestamp; // record the user's entry timestamp

        if (currentBalance == 0) {
            numberOfParticipants += 1;
            participants.push(msg.sender);
        } else {
            updateAllClaims();
        }
    
        claimData.eraAtBlock = block.timestamp;
        claimData.AIGAMESent += amount;
        TotalAIGAMESent += amount;
        updateRewardPerStamp();
        emit AddAIGAME(msg.sender, _amount);
    }

    /**
    * @dev Allows the user to withdraw their AIGAME tokens
    */
    function withdrawAIGAME() public nonReentrant onlyAfterTimelock {
        require(!paused, "Contract already paused.");
        require(balances[msg.sender] > 0, "No AIGAME tokens to withdraw.");        
        uint256 AIGAMEAmount = balances[msg.sender];
        require(AIGAMEToken.transfer(msg.sender, AIGAMEAmount), "Failed Transfer");  
        
        updateAllClaims();     
         //Delete all allocations of AIGAME
        balances[msg.sender] = 0;
        TotalAIGAMESent -= AIGAMEAmount;
        Claim storage claimData = claimRewards[msg.sender];
        claimData.AIGAMESent = 0;

        updateRewardPerStamp();

        if (numberOfParticipants > 0) {
            numberOfParticipants -= 1;
            entryMap[msg.sender] = 0; // reset the user's entry timestamp
        }
        
        emit WithdrawAIGAME(msg.sender, AIGAMEAmount);
    }

    /**
    * @dev Adds new rewards to the contract
    * @param _amount The amount of rewards to add
    */
    function addRewards(uint256 _amount) external onlyOwner {
        payToken.transferFrom(msg.sender, address(this), _amount);
        totalRewards += _amount;
        updateRewardPerStamp();
        emit RewardAddedByDev(_amount);
    }

    function updateAllClaims() internal {
        uint256 numOfParticipants = participants.length;
        for (uint i = 0; i < numOfParticipants; i++) {
            address participant = participants[i];
            Claim storage claimData = claimRewards[participant];
            uint256 currentTime = block.timestamp;
            uint256 period = block.timestamp - claimData.eraAtBlock;
            
            if (blacklist[participant] == 1) {
                claimData.rewardsOwed = 0;
            } else {
                uint256 rewardsAccrued = claimData.rewardsOwed + (rewardPerStamp * period * claimData.AIGAMESent);
                claimData.rewardsOwed = rewardsAccrued;
            }
            claimData.eraAtBlock = currentTime;
        }
    }

    function updateRewardPerStamp() internal {
        rewardPerStamp = (totalRewards * divisor) / (TotalAIGAMESent * Duration);
    }

    function claim() public nonReentrant onlyClaimant {  
        require(!paused, "Contract already paused.");         
        require(blacklist[msg.sender] == 0, "Address is blacklisted.");        
        updateAllClaims();          
        require(claimRewards[msg.sender].rewardsOwed > 0, "No rewards.");
        Claim storage claimData = claimRewards[msg.sender];
        uint256 rewards = claimData.rewardsOwed / divisor;
        require(payToken.transfer(msg.sender, rewards), "Transfer failed.");        
        claimData.rewardsOwed = 0;
        // Update the total rewards claimed by the user
        Claimants[msg.sender] += rewards;
        totalClaimedRewards += rewards;
        totalRewards -= rewards;
        updateRewardPerStamp(); 
        UserClaims[msg.sender] = block.timestamp; // record the user's claim timestamp       
        emit RewardClaimedByUser(msg.sender, rewards);
    }

    function withdraw(uint256 _binary, uint256 amount) external onlyOwner {
        require(amount > 0, "Amount must be greater than zero.");
        if (_binary > 1) {
            require(payToken.balanceOf(address(this)) >= amount, "Not Enough Reserves.");
            require(payToken.transfer(msg.sender, amount), "Transfer failed.");
        } else {
            require(amount <= TaxTotal, "Max Exceeded.");
            require(AIGAMEToken.balanceOf(address(this)) >= TaxTotal, "Not enough Reserves.");
            require(AIGAMEToken.transfer(msg.sender, amount), "Transfer failed.");
            TaxTotal -= amount;
        }
        totalRewards -= amount;
        updateRewardPerStamp();
    }

    function duration() public view returns (uint256) {
        if (block.timestamp < _startTime + _duration) {
            return _startTime + _duration - block.timestamp;
        } else {
            return 1;
        }
    }

    function setDuration(uint256 _seconds) public {
        _startTime = block.timestamp;
        _duration = _seconds;
    }

    function setTimeLock(uint256 _seconds) external onlyOwner {
        timeLock = _seconds;
    }

    function stakeTax (uint256 _percent) external onlyOwner {
        tax = _percent;
    }

    function setAIGAMEToken(address _AIGAMEToken) external onlyOwner {
        AIGAMEToken = IERC20(_AIGAMEToken);
    }

    function setPayToken(address _payToken) external onlyOwner {
        payToken = IERC20(_payToken);
    }

    function addToBlacklist(address[] calldata _addresses) external onlyOwner {
        for (uint256 i = 0; i < _addresses.length; i++) {
            blacklist[_addresses[i]] = 1;
        }
    }

    function removeFromBlacklist(address[] calldata _addresses) external onlyOwner {
        for (uint256 i = 0; i < _addresses.length; i++) {
            blacklist[_addresses[i]] = 0;
        }
    }

    event Pause();
    function pause() public onlyGuard {
        require(msg.sender == owner(), "Only Deployer.");
        require(!paused, "Contract already paused.");
        paused = true;
        emit Pause();
    }

    event Unpause();
    function unpause() public onlyGuard {
        require(msg.sender == owner(), "Only Deployer.");
        require(paused, "Contract not paused.");
        paused = false;
        emit Unpause();
    }

    function setGuard (address _newGuard) external onlyGuard {
        guard = _newGuard;
    }
}
