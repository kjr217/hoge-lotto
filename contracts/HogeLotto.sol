pragma solidity 0.6.12;
pragma experimental ABIEncoderV2;


import "./utils/SortitionSumTreeFactory.sol";
import "./utils/UniformRandomNumber.sol";
import "./utils/VRFConsumer.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/**
 * @author 217
 * @title HogeLotto
 * @notice A raffle/lottery contract that derives its odds for a user from that user's proportion of the pool
 * @dev the contract can be repurposed for any raffle/lottery by just refactoring "hoge/HOGE/Hoge"
 *      and changing the HOGE address. CAUTION: The contract places a large amount of control to the
 *      owners.
 */
contract HogeLotto is Ownable, VRFConsumer, ReentrancyGuard {

    using SafeERC20 for IERC20;
    using SortitionSumTreeFactory for SortitionSumTreeFactory.SortitionSumTrees;
    using Counters for Counters.Counter;

    struct HogeLottoRound {
        // winner of the round, only announced after concludeLottoStep2
        address winner;
        // totalAmount in the round
        uint256 totalAmount;
        // whether the round has been concluded
        bool isConcluded;
        // whether the winner has claimed their winnings
        bool isWinningClaimed;
        // whether the HOGE team has taken their cut
        bool isCutClaimed;
    }
    // storage for the sortition trees, this allows for gas efficient proportional
    // stake matching, a similar implementation can be seen in the PoolTogether contracts
    SortitionSumTreeFactory.SortitionSumTrees internal sortitionSumTrees;
    // Data struct for a lotto round mapped by the lottoId
    mapping(uint256 => HogeLottoRound) public HogeLottoData;
    // HOGE Token
    IERC20 public HOGE;
    // the number for the next lottoId
    Counters.Counter public lottoIdTracker;
    // 100 percent
    uint256 constant public MAX_BPS = 10000;
    // the cut that HOGE team takes on a pot
    uint256 public HOGE_CUT = 1500;
    // used in sortition factory
    uint256 constant private MAX_TREE_LEAVES = 5;

    event LottoStarted(uint256 lottoId);
    event Entered(uint256 indexed lottoId, address entrant, uint256 stake);
    event WinnerAnnounced(uint256 indexed lottoId, address winner, uint256 potSize);

    constructor(bytes32 _keyhash, address _vrfCoordinator, address _linkToken, address _hoge)
        VRFConsumer(
            _keyhash,
            _vrfCoordinator, // VRF Coordinator
            _linkToken  // LINK Token
        ) public
    {
        HOGE = IERC20(_hoge);
    }

    /**
     * @notice allow HOGE holder to enter the lottery
     * @param _amount HOGE to stake in the lottery
     * @param _lottoId the id of the lotto to be processed
     * @dev due to the deflationary behaviour of HOGE the enter amount must be calculated slightly differently
     */
    function enter(uint256 _amount, uint256 _lottoId) external nonReentrant {
        require(_lottoId < lottoIdTracker.current(), "enter: lotto not started");
        HogeLottoRound storage lottoData_ = HogeLottoData[_lottoId];
        require(!lottoData_.isConcluded, "enter: this lotto has concluded");
        uint256 balancePrior = HOGE.balanceOf(address(this));
        HOGE.safeTransferFrom(msg.sender, address(this), _amount);
        uint256 balancePost = HOGE.balanceOf(address(this));
        uint256 _finalAmount = balancePost.sub(balancePrior);
        sortitionSumTrees.set(bytes32(_lottoId), _finalAmount, bytes32(uint256(msg.sender)));
        lottoData_.totalAmount += _finalAmount;

        emit Entered(_lottoId, msg.sender, _finalAmount);
    }

    /**
     * @notice allow owner to initiate a lottery
     */
    function startLotto() external onlyOwner {
        uint256 lottoId_ = lottoIdTracker.current();
        lottoIdTracker.increment();
        sortitionSumTrees.createTree(bytes32(lottoId_), MAX_TREE_LEAVES);
        emit LottoStarted(lottoId_);
    }

    /**
     * @notice allow owner to conclude a lottery by first requesting a random number from Chainlink VRF
     * @dev it is assumed that the LINK for this transaction is already in the contract (2 LINK per rng)
     */
    function requestRandomNumber() external onlyOwner returns (bytes32){
        request.requestExpected = getRandomNumber(420);
        return request.requestExpected;
    }

    /**
     * @notice allow owner to conclude a lottery and set a winner, must have completed requestRandomNumber
     * @param _lottoId the id of the lotto to be processed
     * @dev requestRandomNumber must have been called prior to this in order to get a random number
     */
    function concludeLotto(uint256 _lottoId) external onlyOwner {
        require(_lottoId < lottoIdTracker.current(), "concludeLotto: lotto not started");
        require(
            request.requestExpected == request.requestReceived &&
            request.requestReceived != request.previousRequest,
            "concludeLotto: random number not returned yet"
        );
        HogeLottoRound storage lottoData_ = HogeLottoData[_lottoId];
        require(!lottoData_.isConcluded, "concludeLotto: lotto already concluded");
        uint256 bound = lottoData_.totalAmount;
        address winner_;
        if (bound == 0) {
            winner_ = address(0);
        } else {
            uint256 randomNumber = randomResult;
            uint256 token = UniformRandomNumber.uniform(randomNumber, bound);
            winner_ = address(uint256(sortitionSumTrees.draw(bytes32(_lottoId), token)));
        }
        lottoData_.winner = winner_;
        lottoData_.isConcluded = true;
        request.previousRequest = request.requestReceived;
        emit WinnerAnnounced(_lottoId, winner_, bound);
    }

    /**
     * @notice allow winner to redeem their winnings of a specific lottery
     * @param _lottoId the id of the lotto to be processed
     */
    function claimWinnings(uint256 _lottoId) external {
        require(_lottoId < lottoIdTracker.current(), "claimWinnings: lotto not started");
        HogeLottoRound storage lottoData_ = HogeLottoData[_lottoId];
        require(lottoData_.isConcluded, "claimWinnings: lotto not concluded");
        require(msg.sender == lottoData_.winner, "claimWinnings: msg.sender not winner");
        require(!lottoData_.isWinningClaimed, "claimWinnings: winnings already claimed");
        uint256 val = lottoData_.totalAmount;
        uint256 winnings_ = val.mul((MAX_BPS - HOGE_CUT)).div(MAX_BPS);
        lottoData_.isWinningClaimed = true;
        HOGE.safeTransfer(msg.sender, winnings_);
    }

    /**
     * @notice allow owner to redeem their cut of a specific lottery
     * @param _lottoId the id of the lotto to be processed
     */
    function claimHogeCut(uint256 _lottoId) external onlyOwner {
        require(_lottoId < lottoIdTracker.current(), "claimHogeCut: lotto not started");
        HogeLottoRound storage lottoData_ = HogeLottoData[_lottoId];
        require(lottoData_.isConcluded, "claimHogeCut: lotto not concluded");
        require(!lottoData_.isCutClaimed, "claimHogeCut: cut already claimed");
        uint256 val = lottoData_.totalAmount;
        uint256 cut_ = val.mul(HOGE_CUT).div(MAX_BPS);
        lottoData_.isCutClaimed = true;
        HOGE.safeTransfer(msg.sender, cut_);
    }

    /*** VIEW FUNCTIONS ***/

    /**
     * @notice Returns the user's stake in the pool
     * @param _user the user to check
     * @param _lottoId the id of the lotto to be processed
     * @return stake of the user
     */
    function stakeOf(address _user, uint256 _lottoId) external view returns (uint256) {
        require(_lottoId < lottoIdTracker.current(), "lotto not started");
        return sortitionSumTrees.stakeOf(bytes32(_lottoId), bytes32(uint256(_user)));
    }

    function nextLottoId() external view returns (uint256){
        return lottoIdTracker.current();
    }

    function winner(uint256 _lottoId) external view returns (address){
        require(_lottoId < lottoIdTracker.current(), "lotto not started");
        return HogeLottoData[_lottoId].winner;
    }

    function totalAmount(uint256 _lottoId) external view returns (uint256){
        require(_lottoId < lottoIdTracker.current(), "lotto not started");
        return HogeLottoData[_lottoId].totalAmount;
    }

    function isWinningClaimed(uint256 _lottoId) external view returns (bool){
        require(_lottoId < lottoIdTracker.current(), "lotto not started");
        return HogeLottoData[_lottoId].isWinningClaimed;
    }

    function isConcluded(uint256 _lottoId) external view returns (bool){
        require(_lottoId < lottoIdTracker.current(), "lotto not started");
        return HogeLottoData[_lottoId].isConcluded;
    }

    function isCutClaimed(uint256 _lottoId) external view returns (bool){
        require(_lottoId < lottoIdTracker.current(), "lotto not started");
        return HogeLottoData[_lottoId].isCutClaimed;
    }

    function withdrawLINK(uint256 _amount) external onlyOwner {
        // owner put the LINK in in the first place
        LINK.transfer(msg.sender, _amount);
    }

}
