// SPDX-License-Identifier: MIT
/**
 * @title Incentivizer Contract
 */
pragma solidity ^0.8.17;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";


contract LPRewarder is Ownable, ReentrancyGuard {
    IERC20 public GAMELPToken;
    IERC20 public payToken;
    uint256 public totalRewards = 1;
    uint256 public totalClaimedRewards;
    uint256 public startTime;
    uint256 public rewardPerStamp;
    uint256 public numberOfParticipants = 0;
    uint256 public Duration = 604800;
    uint256 public timeLock = 5;
    uint256 public TotalGAMELPSent = 1;
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
        uint256 GAMELPSent;
        uint256 rewardsOwed;
    }
    
    event RewardsUpdated(uint256 totalRewards);
    event RewardAddedByDev(uint256 amount);
    event RewardClaimedByUser(address indexed user, uint256 amount);
    event AddGAMELP(address indexed user, uint256 amount);
    event WithdrawGAMELP(address indexed user, uint256 amount);
    
    constructor(
        address _GAMELPToken,
        address _payToken,
        address _newGuard
    ) {
        GAMELPToken = IERC20(_GAMELPToken);
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

    function addGAMELP(uint256 _amount) public nonReentrant {
        require(!paused, "Contract is paused.");
        require(_amount > 0, "Amount must be greater than zero.");
        require(blacklist[msg.sender] == 0, "Address is blacklisted.");
        require(GAMELPToken.transferFrom(msg.sender, address(this), _amount), "Transfer failed.");
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
        claimData.GAMELPSent += amount;
        TotalGAMELPSent += amount;
        setRewards();
        emit AddGAMELP(msg.sender, _amount);
    }

    /**
    * @dev Allows the user to withdraw their GAMELP tokens
    */
    function withdrawGAMELP() public nonReentrant onlyAfterTimelock {
        require(!paused, "Contract already paused.");
        require(balances[msg.sender] > 0, "No GAMELP tokens to withdraw.");        
        uint256 GAMELPAmount = balances[msg.sender];
        require(GAMELPToken.transfer(msg.sender, GAMELPAmount), "Failed Transfer");  
        
        updateAllClaims();     
         //Delete all allocations of GAMELP
        balances[msg.sender] = 0;
        TotalGAMELPSent -= GAMELPAmount;
        Claim storage claimData = claimRewards[msg.sender];
        claimData.GAMELPSent = 0;

       setRewards();

        if (numberOfParticipants > 0) {
            numberOfParticipants -= 1;
            entryMap[msg.sender] = 0; // reset the user's entry timestamp
        }
        
        emit WithdrawGAMELP(msg.sender, GAMELPAmount);
    }

    /**
    * @dev Adds new rewards to the contract
    * @param _amount The amount of rewards to add
    */
    function addRewards(uint256 _amount) external onlyOwner {
        payToken.transferFrom(msg.sender, address(this), _amount);
        setRewards();
        emit RewardAddedByDev(_amount);
    }

    function setRewards() internal {
        totalRewards = payToken.balanceOf(address(this));
        updateRewardPerStamp();
        emit RewardsUpdated(totalRewards);
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
                uint256 rewardsAccrued = claimData.rewardsOwed + (rewardPerStamp * period * claimData.GAMELPSent);
                claimData.rewardsOwed = rewardsAccrued;
            }
            claimData.eraAtBlock = currentTime;
        }
    }

    function updateRewardPerStamp() internal {
        rewardPerStamp = (totalRewards * divisor) / (TotalGAMELPSent * Duration);
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
        setRewards();
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
            require(GAMELPToken.balanceOf(address(this)) >= TaxTotal, "Not enough Reserves.");
            require(GAMELPToken.transfer(msg.sender, amount), "Transfer failed.");
            TaxTotal -= amount;
        }
        setRewards();
    }

    function setDuration(uint256 _seconds) external onlyOwner {        
        updateAllClaims();
        Duration = _seconds;
        updateRewardPerStamp();
    }

    function setTimeLock(uint256 _seconds) external onlyOwner {
        timeLock = _seconds;
    }

    function stakeTax (uint256 _percent) external onlyOwner {
        tax = _percent;
    }

    function setGAMELPToken(address _GAMELPToken) external onlyOwner {
        GAMELPToken = IERC20(_GAMELPToken);
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