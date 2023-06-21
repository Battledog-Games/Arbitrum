// SPDX-License-Identifier: MIT

pragma solidity ^0.8.17;

import "@openzeppelin/contracts/access/Ownable.sol";
import "abdk-libraries-solidity/ABDKMath64x64.sol";

// Interface for the Staker contract
interface IStaker {
    function balances(address _staker) external view returns (uint256);
    function participants(uint256 _index) external view returns (address);
    function numberOfParticipants() external view returns (uint256);
}

contract farmSnapshot is Ownable {
    using ABDKMath64x64 for uint256;

    address public GAMEharvester;
    uint256 public activeFarmersLength;
    uint256 public allFarmersBalance;

    mapping(address => bool) public ActiveFarmers;
    mapping(address => uint256) public Records;
    address[] public farmers;

    constructor(
        address GAMEharvester_
    ) {
        GAMEharvester = GAMEharvester_;
    }

    function snapShot() external onlyOwner {
        IStaker staker = IStaker(GAMEharvester);
        uint256 numberOfParticipants = staker.numberOfParticipants(); 

        for (uint256 i = 0; i < numberOfParticipants; i++) {
            address participant = staker.participants(i);
            uint256 balance = staker.balances(participant);

            if (balance > 0) {
                ActiveFarmers[participant] = true;
                farmers.push(participant);
                Records[participant] = balance;
                allFarmersBalance += balance;
                ++activeFarmersLength;
            }
        }
    }
}
