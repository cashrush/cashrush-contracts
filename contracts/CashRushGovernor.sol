// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "@openzeppelin/contracts/governance/Governor.sol";
import "@openzeppelin/contracts/governance/extensions/GovernorSettings.sol";
import "@openzeppelin/contracts/governance/extensions/GovernorCountingSimple.sol";
import "@openzeppelin/contracts/governance/extensions/GovernorVotes.sol";

contract CashRushGovernor is
    Governor,
    GovernorSettings,
    GovernorCountingSimple,
    GovernorVotes
{
    constructor(
        IVotes _token
    )
        Governor("CashRushGovernor")
        GovernorSettings(0, 50400, 1)
        GovernorVotes(_token)
    {
        /**
         * Voting Delay - 0 blocks
         * Voting Period - 1 week = 7*24*60*60/12 = 50400 blocks
         * Proposal Threshold # - 1 NFTs
         * Quorum # - 50 NFTs
         */
    }

    function quorum(
        uint256 blockNumber
    ) public pure override returns (uint256) {
        return 50;
    }

    // The following functions are overrides required by Solidity.
    function votingDelay()
        public
        view
        override(IGovernor, GovernorSettings)
        returns (uint256)
    {
        return super.votingDelay();
    }

    function votingPeriod()
        public
        view
        override(IGovernor, GovernorSettings)
        returns (uint256)
    {
        return super.votingPeriod();
    }

    function proposalThreshold()
        public
        view
        override(Governor, GovernorSettings)
        returns (uint256)
    {
        return super.proposalThreshold();
    }
}
