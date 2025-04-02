// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/**
 * @title KlausBet
 * @dev Main contract for the Klaus Bet platform
 */
contract KlausBet is Ownable, ReentrancyGuard {
    // BASE token
    IERC20 public immutable baseToken;
    
    // Platform fee percentage (5%)
    uint256 public platformFeePercentage = 5;
    
    // Fee collector address
    address public feeCollector;
    
    // Reference to Team A and Team B vaults
    BettingVault public immutable teamAVault;
    BettingVault public immutable teamBVault;
    
    // Event data structure
    struct EventData {
        string eventName;
        string teamA;
        string teamB;
        uint256 openingTime;
        uint256 closingTime;
        uint256 oddsTeamA;
        uint256 oddsTeamB;
        bool eventConcluded;
        bool eventCancelled;
        // 0 = Pending, 1 = Team A Won, 2 = Team B Won, 3 = Draw, 4 = Cancelled
        uint8 outcome;
    }
    
    // Mapping from event ID to event data
    mapping(uint256 => EventData) public events;
    
    // Total events counter
    uint256 public totalEvents;
    
    // Events
    event EventCreated(
        uint256 indexed eventId,
        string eventName,
        string teamA,
        string teamB,
        uint256 openingTime,
        uint256 closingTime,
        uint256 oddsTeamA,
        uint256 oddsTeamB
    );
    
    event EventResultSet(
        uint256 indexed eventId,
        uint8 outcome
    );
    
    event EventCancelled(
        uint256 indexed eventId
    );
    
    event PlatformFeeUpdated(
        uint256 newFeePercentage
    );
    
    event FeeCollectorUpdated(
        address newFeeCollector
    );
    
    /**
     * @dev Constructor initializes the main contract and deploys vault contracts
     * @param _baseToken Address of the BASE token
     * @param _feeCollector Address to collect platform fees
     */
    constructor(address _baseToken, address _feeCollector) Ownable(msg.sender) {
        require(_baseToken != address(0), "Invalid token address");
        require(_feeCollector != address(0), "Invalid fee collector address");
        
        baseToken = IERC20(_baseToken);
        feeCollector = _feeCollector;
        
        // Deploy Team A and Team B vaults
        teamAVault = new BettingVault(_baseToken, address(this));
        teamBVault = new BettingVault(_baseToken, address(this));
    }
    
    /**
     * @dev Create a new betting event
     * @param _eventName Name of the sporting event
     * @param _teamA Name of Team A
     * @param _teamB Name of Team B
     * @param _openingTime Time when betting opens
     * @param _closingTime Time when betting closes
     * @param _oddsTeamA Moneyline odds for Team A (e.g., 200 means $100 bet yields $200 profit)
     * @param _oddsTeamB Moneyline odds for Team B
     */
    function createEvent(
        string memory _eventName,
        string memory _teamA,
        string memory _teamB,
        uint256 _openingTime,
        uint256 _closingTime,
        uint256 _oddsTeamA,
        uint256 _oddsTeamB
    ) external onlyOwner {
        require(_openingTime > block.timestamp, "Opening time must be in the future");
        require(_closingTime > _openingTime, "Closing time must be after opening time");
        require(_oddsTeamA > 0 && _oddsTeamB > 0, "Odds must be greater than 0");
        
        uint256 eventId = totalEvents++;
        
        events[eventId] = EventData({
            eventName: _eventName,
            teamA: _teamA,
            teamB: _teamB,
            openingTime: _openingTime,
            closingTime: _closingTime,
            oddsTeamA: _oddsTeamA,
            oddsTeamB: _oddsTeamB,
            eventConcluded: false,
            eventCancelled: false,
            outcome: 0 // Pending
        });
        
        emit EventCreated(
            eventId,
            _eventName,
            _teamA,
            _teamB,
            _openingTime,
            _closingTime,
            _oddsTeamA,
            _oddsTeamB
        );
    }
    
    /**
     * @dev Place a bet on Team A for a specific event
     * @param _eventId ID of the event
     * @param _amount Amount to bet in BASE tokens
     */
    function betOnTeamA(uint256 _eventId, uint256 _amount) external nonReentrant {
        EventData storage eventData = _validateBet(_eventId, _amount);
        
        // Transfer tokens to the Team A vault
        require(baseToken.transferFrom(msg.sender, address(teamAVault), _amount), "Token transfer failed");
        
        // Record the bet in the Team A vault
        teamAVault.recordBet(_eventId, msg.sender, _amount, eventData.oddsTeamA, eventData.oddsTeamB);
        
        // Try to match bets
        _matchBets(_eventId);
    }
    
    /**
     * @dev Place a bet on Team B for a specific event
     * @param _eventId ID of the event
     * @param _amount Amount to bet in BASE tokens
     */
    function betOnTeamB(uint256 _eventId, uint256 _amount) external nonReentrant {
        EventData storage eventData = _validateBet(_eventId, _amount);
        
        // Transfer tokens to the Team B vault
        require(baseToken.transferFrom(msg.sender, address(teamBVault), _amount), "Token transfer failed");
        
        // Record the bet in the Team B vault
        teamBVault.recordBet(_eventId, msg.sender, _amount, eventData.oddsTeamB, eventData.oddsTeamA);
        
        // Try to match bets
        _matchBets(_eventId);
    }
    
    /**
     * @dev Set the outcome of an event
     * @param _eventId ID of the event
     * @param _outcome Result of the event (1 = Team A won, 2 = Team B won, 3 = Draw, 4 = Cancelled)
     */
    function setEventOutcome(uint256 _eventId, uint8 _outcome) external onlyOwner {
        require(_eventId < totalEvents, "Event does not exist");
        require(_outcome > 0 && _outcome <= 4, "Invalid outcome");
        
        EventData storage eventData = events[_eventId];
        
        require(block.timestamp >= eventData.closingTime, "Event not closed yet");
        require(!eventData.eventConcluded && !eventData.eventCancelled, "Event already concluded or cancelled");
        
        eventData.outcome = _outcome;
        
        if (_outcome == 4) { // Cancelled
            eventData.eventCancelled = true;
            emit EventCancelled(_eventId);
        } else {
            eventData.eventConcluded = true;
        }
        
        emit EventResultSet(_eventId, _outcome);
    }
    
    /**
     * @dev Claim winnings for a specific event
     * @param _eventId ID of the event
     */
    function claimWinnings(uint256 _eventId) external nonReentrant {
        require(_eventId < totalEvents, "Event does not exist");
        
        EventData storage eventData = events[_eventId];
        require(eventData.eventConcluded || eventData.eventCancelled, "Event not concluded yet");
        
        uint256 winnings = 0;
        
        if (eventData.eventCancelled || eventData.outcome == 3) { // Cancelled or Draw
            // Claim original bets from both vaults
            uint256 teamAAmount = teamAVault.claimMatchedBets(_eventId, msg.sender);
            uint256 teamBAmount = teamBVault.claimMatchedBets(_eventId, msg.sender);
            
            winnings = teamAAmount + teamBAmount;
        } else if (eventData.outcome == 1) { // Team A Won
            // Claim original bet from Team A vault
            uint256 originalBet = teamAVault.claimMatchedBets(_eventId, msg.sender);
            
            // Calculate proportional winnings from Team B vault based on original bet
            if (originalBet > 0) {
                uint256 totalMatchedA = teamAVault.getTotalMatchedAmount(_eventId);
                if (totalMatchedA > 0) {
                    uint256 proportion = (originalBet * 1e18) / totalMatchedA;
                    
                    uint256 totalMatchedB = teamBVault.getTotalMatchedAmount(_eventId);
                    uint256 rawWinnings = (totalMatchedB * proportion) / 1e18;
                    
                    // Apply platform fee
                    uint256 fee = (rawWinnings * platformFeePercentage) / 100;
                    uint256 winningsFromB = rawWinnings - fee;
                    
                    // Transfer winnings from Team B vault
                    teamBVault.transferWinnings(_eventId, msg.sender, winningsFromB);
                    
                    winnings = originalBet + winningsFromB;
                    
                    // Transfer fee to fee collector
                    if (fee > 0) {
                        teamBVault.transferWinnings(_eventId, feeCollector, fee);
                    }
                } else {
                    winnings = originalBet;
                }
            }
        } else if (eventData.outcome == 2) { // Team B Won
            // Claim original bet from Team B vault
            uint256 originalBet = teamBVault.claimMatchedBets(_eventId, msg.sender);
            
            // Calculate proportional winnings from Team A vault based on original bet
            if (originalBet > 0) {
                uint256 totalMatchedB = teamBVault.getTotalMatchedAmount(_eventId);
                if (totalMatchedB > 0) {
                    uint256 proportion = (originalBet * 1e18) / totalMatchedB;
                    
                    uint256 totalMatchedA = teamAVault.getTotalMatchedAmount(_eventId);
                    uint256 rawWinnings = (totalMatchedA * proportion) / 1e18;
                    
                    // Apply platform fee
                    uint256 fee = (rawWinnings * platformFeePercentage) / 100;
                    uint256 winningsFromA = rawWinnings - fee;
                    
                    // Transfer winnings from Team A vault
                    teamAVault.transferWinnings(_eventId, msg.sender, winningsFromA);
                    
                    winnings = originalBet + winningsFromA;
                    
                    // Transfer fee to fee collector
                    if (fee > 0) {
                        teamAVault.transferWinnings(_eventId, feeCollector, fee);
                    }
                } else {
                    winnings = originalBet;
                }
            }
        }
        
        require(winnings > 0, "No winnings to claim");
    }
    
    /**
     * @dev Claim unmatched bets for a specific event
     * @param _eventId ID of the event
     */
    function claimUnmatchedBets(uint256 _eventId) external nonReentrant {
        require(_eventId < totalEvents, "Event does not exist");
        
        EventData storage eventData = events[_eventId];
        require(block.timestamp >= eventData.closingTime || eventData.eventCancelled, "Event not closed yet");
        
        // Claim unmatched bets from both vaults
        uint256 unmatchedA = teamAVault.claimUnmatchedBets(_eventId, msg.sender);
        uint256 unmatchedB = teamBVault.claimUnmatchedBets(_eventId, msg.sender);
        
        uint256 totalUnmatched = unmatchedA + unmatchedB;
        require(totalUnmatched > 0, "No unmatched bets to claim");
    }
    
    /**
     * @dev Match bets for a specific event
     * @param _eventId ID of the event
     */
    function _matchBets(uint256 _eventId) internal {
        // Get unmatched bets from both vaults
        (uint256 unmatchedAmountA, uint256 requiredB) = teamAVault.getUnmatchedAmount(_eventId);
        (uint256 unmatchedAmountB, uint256 requiredA) = teamBVault.getUnmatchedAmount(_eventId);
        
        if (unmatchedAmountA > 0 && unmatchedAmountB > 0) {
            if (requiredB <= unmatchedAmountB) {
                // Team A bets can be fully matched
                teamAVault.matchBets(_eventId, unmatchedAmountA);
                teamBVault.matchBets(_eventId, requiredB);
            } else if (requiredA <= unmatchedAmountA) {
                // Team B bets can be fully matched
                teamBVault.matchBets(_eventId, unmatchedAmountB);
                teamAVault.matchBets(_eventId, requiredA);
            } else {
                // Partial matching based on available amounts
                uint256 maxMatchableA = (unmatchedAmountB * teamAVault.getOddsForEvent(_eventId)) / teamBVault.getOddsForEvent(_eventId);
                if (maxMatchableA > 0 && maxMatchableA <= unmatchedAmountA) {
                    teamAVault.matchBets(_eventId, maxMatchableA);
                    teamBVault.matchBets(_eventId, unmatchedAmountB);
                } else {
                    uint256 maxMatchableB = (unmatchedAmountA * teamBVault.getOddsForEvent(_eventId)) / teamAVault.getOddsForEvent(_eventId);
                    if (maxMatchableB > 0 && maxMatchableB <= unmatchedAmountB) {
                        teamBVault.matchBets(_eventId, maxMatchableB);
                        teamAVault.matchBets(_eventId, unmatchedAmountA);
                    }
                }
            }
        }
    }
    
    /**
     * @dev Validate bet parameters and return event data
     * @param _eventId ID of the event
     * @param _amount Amount to bet
     * @return Event data
     */
    function _validateBet(uint256 _eventId, uint256 _amount) internal view returns (EventData storage) {
        require(_eventId < totalEvents, "Event does not exist");
        require(_amount > 0, "Bet amount must be greater than 0");
        
        EventData storage eventData = events[_eventId];
        
        require(block.timestamp >= eventData.openingTime, "Betting not open yet");
        require(block.timestamp < eventData.closingTime, "Betting period closed");
        require(!eventData.eventCancelled, "Event has been cancelled");
        
        return eventData;
    }
    
    /**
     * @dev Update the platform fee percentage
     * @param _newFeePercentage New fee percentage (e.g., 5 for 5%)
     */
    function updatePlatformFee(uint256 _newFeePercentage) external onlyOwner {
        require(_newFeePercentage <= 10, "Fee cannot exceed 10%");
        platformFeePercentage = _newFeePercentage;
        
        emit PlatformFeeUpdated(_newFeePercentage);
    }
    
    /**
     * @dev Update the fee collector address
     * @param _newFeeCollector New address to collect fees
     */
    function updateFeeCollector(address _newFeeCollector) external onlyOwner {
        require(_newFeeCollector != address(0), "Invalid fee collector address");
        feeCollector = _newFeeCollector;
        
        emit FeeCollectorUpdated(_newFeeCollector);
    }
    
    /**
     * @dev Get event information
     * @param _eventId ID of the event
     * @return eventName Name of the event
     * @return teamA Name of Team A
     * @return teamB Name of Team B
     * @return openingTime Time when betting opens
     * @return closingTime Time when betting closes
     * @return oddsTeamA Odds for Team A
     * @return oddsTeamB Odds for Team B
     * @return eventConcluded Whether the event has concluded
     * @return eventCancelled Whether the event has been cancelled
     * @return outcome Outcome of the event
     */
    function getEventInfo(uint256 _eventId) external view returns (
        string memory eventName,
        string memory teamA,
        string memory teamB,
        uint256 openingTime,
        uint256 closingTime,
        uint256 oddsTeamA,
        uint256 oddsTeamB,
        bool eventConcluded,
        bool eventCancelled,
        uint8 outcome
    ) {
        require(_eventId < totalEvents, "Event does not exist");
        
        EventData storage eventData = events[_eventId];
        
        return (
            eventData.eventName,
            eventData.teamA,
            eventData.teamB,
            eventData.openingTime,
            eventData.closingTime,
            eventData.oddsTeamA,
            eventData.oddsTeamB,
            eventData.eventConcluded,
            eventData.eventCancelled,
            eventData.outcome
        );
    }
    
    /**
     * @dev Get user's bets for a specific event
     * @param _eventId ID of the event
     * @param _bettor Address of the bettor
     * @return teamAAmount Total amount bet on Team A
     * @return teamBAmount Total amount bet on Team B
     * @return teamAMatched Matched amount on Team A
     * @return teamBMatched Matched amount on Team B
     */
    function getUserBets(uint256 _eventId, address _bettor) external view returns (
        uint256 teamAAmount,
        uint256 teamBAmount,
        uint256 teamAMatched,
        uint256 teamBMatched
    ) {
        require(_eventId < totalEvents, "Event does not exist");
        
        (teamAAmount, teamAMatched) = teamAVault.getUserBetInfo(_eventId, _bettor);
        (teamBAmount, teamBMatched) = teamBVault.getUserBetInfo(_eventId, _bettor);
         
        return (teamAAmount, teamBAmount, teamAMatched, teamBMatched);
    }
    
    /**
     * @dev Get total betting statistics for an event
     * @param _eventId ID of the event
     * @return totalBetsA Total amount bet on Team A
     * @return totalBetsB Total amount bet on Team B
     * @return matchedBetsA Total matched amount on Team A
     * @return matchedBetsB Total matched amount on Team B
     */
    function getEventStats(uint256 _eventId) external view returns (
        uint256 totalBetsA,
        uint256 totalBetsB,
        uint256 matchedBetsA,
        uint256 matchedBetsB
    ) {
        require(_eventId < totalEvents, "Event does not exist");
        
        totalBetsA = teamAVault.getTotalAmount(_eventId);
        totalBetsB = teamBVault.getTotalAmount(_eventId);
        matchedBetsA = teamAVault.getTotalMatchedAmount(_eventId);
        matchedBetsB = teamBVault.getTotalMatchedAmount(_eventId);
        
        return (totalBetsA, totalBetsB, matchedBetsA, matchedBetsB);
    }

    /**
     * @dev Get current timestamp
     * @return timestamp Current block timestamp
     */
    function currentTimestamp() external view returns (
        uint256 timestamp
    ) {
        return block.timestamp;
    }
}

/**
 * @title BettingVault
 * @dev Contract for storing and managing bets for either Team A or Team B across multiple events
 */
contract BettingVault is ReentrancyGuard {
    // BASE token
    IERC20 public immutable baseToken;
    
    // Reference to main contract
    address public immutable mainContract;
    
    // Bet data structure
    struct Bet {
        address bettor;
        uint256 amount;
        bool matched;
        bool claimed;
    }
    
    // Event data structure
    struct EventBets {
        Bet[] bets;
        uint256 totalAmount;
        uint256 totalMatchedAmount;
        uint256 unmatchedIndex;
        uint256 odds;
        uint256 opposingOdds;
    }
    
    // Mapping from event ID to event bets
    mapping(uint256 => EventBets) public eventBets;
    
    // Events
    event BetRecorded(
        uint256 indexed eventId,
        address indexed bettor,
        uint256 amount,
        uint256 betIndex
    );
    
    event BetsMatched(
        uint256 indexed eventId,
        uint256 amount
    );
    
    event UnmatchedBetsClaimed(
        uint256 indexed eventId,
        address indexed bettor,
        uint256 amount
    );
    
    event MatchedBetsClaimed(
        uint256 indexed eventId,
        address indexed bettor,
        uint256 amount
    );
    
    event WinningsTransferred(
        uint256 indexed eventId,
        address indexed recipient,
        uint256 amount
    );
    
    /**
     * @dev Modifier to ensure only the main contract can call certain functions
     */
    modifier onlyMainContract() {
        require(msg.sender == mainContract, "Only main contract can call this function");
        _;
    }
    
    /**
     * @dev Constructor initializes the vault contract
     * @param _baseToken Address of the BASE token
     * @param _mainContract Address of the main contract
     */
    constructor(address _baseToken, address _mainContract) {
        require(_baseToken != address(0), "Invalid token address");
        require(_mainContract != address(0), "Invalid main contract address");
        
        baseToken = IERC20(_baseToken);
        mainContract = _mainContract;
    }
    
    /**
     * @dev Record a new bet for a specific event
     * @param _eventId ID of the event
     * @param _bettor Address of the bettor
     * @param _amount Amount of the bet
     * @param _odds Odds for this side
     * @param _opposingOdds Odds for the opposing side
     * @return Index of the bet
     */
    function recordBet(
        uint256 _eventId,
        address _bettor,
        uint256 _amount,
        uint256 _odds,
        uint256 _opposingOdds
    ) external onlyMainContract returns (uint256) {
        EventBets storage evBets = eventBets[_eventId];
        
        // Initialize event odds if this is the first bet
        if (evBets.bets.length == 0) {
            evBets.odds = _odds;
            evBets.opposingOdds = _opposingOdds;
        }
        
        // Add bet to the event
        uint256 betIndex = evBets.bets.length;
        evBets.bets.push(Bet({
            bettor: _bettor,
            amount: _amount,
            matched: false,
            claimed: false
        }));
        
        // Update total amount
        evBets.totalAmount += _amount;
        
        emit BetRecorded(_eventId, _bettor, _amount, betIndex);
        
        return betIndex;
    }
    
    /**
     * @dev Match bets for a specific event
     * @param _eventId ID of the event
     * @param _amount Amount to match
     */
    function matchBets(uint256 _eventId, uint256 _amount) external onlyMainContract {
        EventBets storage evBets = eventBets[_eventId];
        require(_amount > 0 && _amount <= evBets.totalAmount - evBets.totalMatchedAmount, "Invalid match amount");
        
        uint256 remainingToMatch = _amount;
        
        // Match bets in chronological order
        while (remainingToMatch > 0 && evBets.unmatchedIndex < evBets.bets.length) {
            Bet storage bet = evBets.bets[evBets.unmatchedIndex];
            
            if (bet.matched || bet.claimed) {
                evBets.unmatchedIndex++;
                continue;
            }
            
            uint256 unmatchedAmount = bet.amount;
            
            if (unmatchedAmount <= remainingToMatch) {
                // Fully match this bet
                bet.matched = true;
                remainingToMatch -= unmatchedAmount;
                evBets.unmatchedIndex++;
            } else {
                // Partially match this bet - create a new bet entry for the matched portion
                bet.amount = unmatchedAmount - remainingToMatch;
                
                // Add a new matched bet for the matched portion
                evBets.bets.push(Bet({
                    bettor: bet.bettor,
                    amount: remainingToMatch,
                    matched: true,
                    claimed: false
                }));
                
                remainingToMatch = 0;
            }
        }
        
        // Update total matched amount
        evBets.totalMatchedAmount += _amount - remainingToMatch;
        
        emit BetsMatched(_eventId, _amount - remainingToMatch);
    }
    
    /**
     * @dev Claim unmatched bets for a specific event
     * @param _eventId ID of the event
     * @param _bettor Address of the bettor
     * @return Total unmatched amount claimed
     */
    function claimUnmatchedBets(uint256 _eventId, address _bettor) external onlyMainContract nonReentrant returns (uint256) {
        EventBets storage evBets = eventBets[_eventId];
        uint256 totalUnmatched = 0;
        
        for (uint256 i = 0; i < evBets.bets.length; i++) {
            Bet storage bet = evBets.bets[i];
            
            if (bet.bettor == _bettor && !bet.matched && !bet.claimed) {
                totalUnmatched += bet.amount;
                bet.claimed = true;
            }
        }
        
        if (totalUnmatched > 0) {
            require(baseToken.transfer(_bettor, totalUnmatched), "Token transfer failed");
            emit UnmatchedBetsClaimed(_eventId, _bettor, totalUnmatched);
        }
        
        return totalUnmatched;
    }
    
    /**
     * @dev Claim matched bets for a specific event
     * @param _eventId ID of the event
     * @param _bettor Address of the bettor
     * @return Total matched amount claimed
     */
    function claimMatchedBets(uint256 _eventId, address _bettor) external onlyMainContract nonReentrant returns (uint256) {
        EventBets storage evBets = eventBets[_eventId];
        uint256 totalMatched = 0;
        
        for (uint256 i = 0; i < evBets.bets.length; i++) {
            Bet storage bet = evBets.bets[i];
            
            if (bet.bettor == _bettor && bet.matched && !bet.claimed) {
                totalMatched += bet.amount;
                bet.claimed = true;
            }
        }
        
        if (totalMatched > 0) {
            require(baseToken.transfer(_bettor, totalMatched), "Token transfer failed");
            emit MatchedBetsClaimed(_eventId, _bettor, totalMatched);
        }
        
        return totalMatched;
    }
    
    /**
     * @dev Transfer winnings to a recipient
     * @param _eventId ID of the event
     * @param _recipient Address of the recipient
     * @param _amount Amount to transfer
     */
    function transferWinnings(uint256 _eventId, address _recipient, uint256 _amount) external onlyMainContract nonReentrant {
        require(_amount > 0, "Amount must be greater than 0");
        
        require(baseToken.transfer(_recipient, _amount), "Token transfer failed");
        
        emit WinningsTransferred(_eventId, _recipient, _amount);
    }
    
    /**
     * @dev Get unmatched amount and required opposing amount for a specific event
     * @param _eventId ID of the event
     * @return unmatchedAmount Total unmatched amount
     * @return requiredOpposing Required amount from opposing vault
     */
    function getUnmatchedAmount(uint256 _eventId) external view returns (uint256 unmatchedAmount, uint256 requiredOpposing) {
        EventBets storage evBets = eventBets[_eventId];
        
        unmatchedAmount = evBets.totalAmount - evBets.totalMatchedAmount;
        
        // Calculate required opposing amount based on odds
        if (unmatchedAmount > 0 && evBets.odds > 0 && evBets.opposingOdds > 0) {
            requiredOpposing = (unmatchedAmount * evBets.odds) / evBets.opposingOdds;
        }
        
        return (unmatchedAmount, requiredOpposing);
    }
    
    /**
     * @dev Get total amount bet for a specific event
     * @param _eventId ID of the event
     * @return Total amount bet
     */
    function getTotalAmount(uint256 _eventId) external view returns (uint256) {
        return eventBets[_eventId].totalAmount;
    }
    
    /**
     * @dev Get total matched amount for a specific event
     * @param _eventId ID of the event
     * @return Total matched amount
     */
    function getTotalMatchedAmount(uint256 _eventId) external view returns (uint256) {
        return eventBets[_eventId].totalMatchedAmount;
    }
    
    /**
     * @dev Get odds for a specific event
     * @param _eventId ID of the event
     * @return Odds for this side
     */
    function getOddsForEvent(uint256 _eventId) external view returns (uint256) {
        return eventBets[_eventId].odds;
    }
    
    /**
     * @dev Get user's bet information for a specific event
     * @param _eventId ID of the event
     * @param _bettor Address of the bettor
     * @return totalAmount Total amount bet by the user
     * @return matchedAmount Matched amount bet by the user
     */
    function getUserBetInfo(uint256 _eventId, address _bettor) external view returns (uint256 totalAmount, uint256 matchedAmount) {
        EventBets storage evBets = eventBets[_eventId];
        
        for (uint256 i = 0; i < evBets.bets.length; i++) {
            Bet storage bet = evBets.bets[i];
            
            if (bet.bettor == _bettor) {
                totalAmount += bet.amount;
                
                if (bet.matched && !bet.claimed) {
                    matchedAmount += bet.amount;
                }
            }
        }
        
        return (totalAmount, matchedAmount);
    }
    
    /**
     * @dev Get all bets for a specific event
     * @param _eventId ID of the event
     * @return bettors Array of bettor addresses
     * @return amounts Array of bet amounts
     * @return matchedStatuses Array of bet matched statuses
     * @return claimedStatuses Array of bet claimed statuses
     */
    function getEventBets(uint256 _eventId) external view returns (
        address[] memory bettors,
        uint256[] memory amounts,
        bool[] memory matchedStatuses,
        bool[] memory claimedStatuses
    ) {
        EventBets storage evBets = eventBets[_eventId];
        uint256 betCount = evBets.bets.length;
        
        bettors = new address[](betCount);
        amounts = new uint256[](betCount);
        matchedStatuses = new bool[](betCount);
        claimedStatuses = new bool[](betCount);
        
        for (uint256 i = 0; i < betCount; i++) {
            Bet storage bet = evBets.bets[i];
            bettors[i] = bet.bettor;
            amounts[i] = bet.amount;
            matchedStatuses[i] = bet.matched;
            claimedStatuses[i] = bet.claimed;
        }
        
        return (bettors, amounts, matchedStatuses, claimedStatuses);
    }
    
    /**
     * @dev Check if a user has any unmatched bets for a specific event
     * @param _eventId ID of the event
     * @param _bettor Address of the bettor
     * @return Whether the user has any unmatched bets
     */
    function hasUnmatchedBets(uint256 _eventId, address _bettor) external view returns (bool) {
        EventBets storage evBets = eventBets[_eventId];
        
        for (uint256 i = 0; i < evBets.bets.length; i++) {
            Bet storage bet = evBets.bets[i];
            
            if (bet.bettor == _bettor && !bet.matched && !bet.claimed) {
                return true;
            }
        }
        
        return false;
    }
    
    /**
     * @dev Check if a user has any matched bets for a specific event
     * @param _eventId ID of the event
     * @param _bettor Address of the bettor
     * @return Whether the user has any matched bets
     */
    function hasMatchedBets(uint256 _eventId, address _bettor) external view returns (bool) {
        EventBets storage evBets = eventBets[_eventId];
        
        for (uint256 i = 0; i < evBets.bets.length; i++) {
            Bet storage bet = evBets.bets[i];
            
            if (bet.bettor == _bettor && bet.matched && !bet.claimed) {
                return true;
            }
        }
        
        return false;
    }
    
    function getEventCount() external view returns (uint256 count) {
        // This function is not efficient as it iterates through all possible event IDs
        // In a production environment, we would track active events separately
        for (uint256 i = 0; i < 1000; i++) { // Arbitrary limit for demonstration
            if (eventBets[i].bets.length > 0) {
                count++;
            }
        }
        return count;
    }
    
    /**
     * @dev Emergency function to recover tokens sent to this contract by mistake
     * @param _token Address of the token to recover
     * @param _amount Amount to recover
     * @param _recipient Address to send the recovered tokens to
     * @notice This function can only be called by the main contract
     */
    function recoverTokens(address _token, uint256 _amount, address _recipient) external onlyMainContract nonReentrant {
        require(_token != address(0), "Invalid token address");
        require(_recipient != address(0), "Invalid recipient address");
        
        IERC20(_token).transfer(_recipient, _amount);
    }
}